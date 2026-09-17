import Foundation

/// The complete set of things a client may ask `calmad` to do.
///
/// Deliberately small and explicit: there is no "write arbitrary SMC key" command, and there never will be.
public enum CalmaCommand: Codable, Equatable, Sendable {
    case status
    case updateSettings(CalmaSettings)
    case setChargeLimit(Int)
    case setChargingPaused(Bool)
    case startFullCharge
    case startDrain(target: Int)
    case startRecalibration
    case cancelMode
    /// Sent periodically by the menu bar app so the daemon knows it is running.
    case appHeartbeat
    /// Sent when the menu bar app quits.
    case appWillQuit
    /// Restore stock charging behaviour on every key and clear all special modes.
    case emergencyReset
    case setLowPowerMode(Bool)
    case setHighPowerMode(Bool)

    /// Everything except reading status needs an administrator.
    public var requiresAdmin: Bool {
        switch self {
        case .status, .appHeartbeat, .appWillQuit: return false
        default: return true
        }
    }
}

public struct CalmaResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var message: String?
    public var status: CalmaStatus?

    public init(ok: Bool, error: String? = nil, message: String? = nil, status: CalmaStatus? = nil) {
        self.ok = ok
        self.error = error
        self.message = message
        self.status = status
    }

    public static func failure(_ error: String) -> CalmaResponse { CalmaResponse(ok: false, error: error) }
}

/// Validates a command against the current battery and hardware before the daemon acts on it.
public enum CommandValidator {
    /// Returns a user-facing error, or nil when the command may proceed.
    public static func validate(_ command: CalmaCommand, battery: BatterySnapshot, settings: CalmaSettings,
                                capabilities caps: Capabilities) -> String? {
        let level = battery.effectivePercentage(useHardware: settings.useHardwarePercentage)
        switch command {
        case .setChargeLimit(let limit):
            guard (CalmaLimits.minimumChargeLimit...100).contains(limit) else {
                return "Charge limit must be between \(CalmaLimits.minimumChargeLimit) and 100"
            }
            guard caps.canInhibitCharging else { return unsupportedMessage(caps) }
        case .setChargingPaused:
            guard caps.canInhibitCharging else { return unsupportedMessage(caps) }
        case .startFullCharge:
            guard caps.canInhibitCharging else { return unsupportedMessage(caps) }
        case .startDrain(let target):
            guard caps.canDrain, caps.canInhibitCharging else { return "Draining while plugged in isn't supported on this Mac" }
            guard (CalmaLimits.minimumChargeLimit...100).contains(target) else {
                return "Drain target must be between \(CalmaLimits.minimumChargeLimit) and 100"
            }
            guard level >= CalmaLimits.minimumDrainStartLevel else {
                return "Battery is below \(CalmaLimits.minimumDrainStartLevel)% — draining refused"
            }
            guard battery.temperature != nil else { return "Battery temperature is unreadable — draining refused for safety" }
            guard target < level else { return "Battery is already at or below \(target)%" }
        case .startRecalibration:
            guard caps.canDrain, caps.canInhibitCharging else { return "Recalibration needs drain support, which this Mac doesn't have" }
            guard battery.isPluggedIn else { return "Plug in your Mac to start recalibration" }
            guard battery.temperature != nil else { return "Battery temperature is unreadable — recalibration refused for safety" }
        case .updateSettings(let new):
            if new.autoDrain && !caps.canDrain { return "Auto Drain isn't supported on this Mac" }
            if new.magSafeLED != .system && !caps.hasMagSafeLED { return "This Mac has no controllable MagSafe LED" }
        case .status, .cancelMode, .appHeartbeat, .appWillQuit, .emergencyReset, .setLowPowerMode, .setHighPowerMode:
            break
        }
        return nil
    }

    static func unsupportedMessage(_ caps: Capabilities) -> String {
        "This Mac's firmware doesn't expose a documented charge-control key (backend: \(caps.backend.rawValue)). See docs/SMC_KEYS.md."
    }
}

public enum CalmaIPCError: Error, CustomStringConvertible {
    case daemonNotRunning
    case transport(String)
    case badResponse

    public var description: String {
        switch self {
        case .daemonNotRunning: return "The Calma helper (calmad) isn't running. Install it from the app or run Scripts/install-daemon.sh."
        case .transport(let detail): return "Couldn't talk to calmad: \(detail)"
        case .badResponse: return "calmad sent an unreadable response"
        }
    }
}

public enum CalmaJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Newline-delimited JSON over the daemon's Unix domain socket. One request per connection.
public enum CalmaClient {
    public static func send(_ command: CalmaCommand, socketPath: String = CalmaPaths.socketPath,
                            timeout: TimeInterval = 5) throws -> CalmaResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CalmaIPCError.transport(String(cString: strerror(errno))) }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw CalmaIPCError.transport("socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in pathBytes.enumerated() { buffer[index] = byte }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED { throw CalmaIPCError.daemonNotRunning }
            throw CalmaIPCError.transport(String(cString: strerror(errno)))
        }

        var payload = try CalmaJSON.encoder().encode(command)
        payload.append(0x0A)
        try SocketIO.writeAll(fd, payload)
        let data = try SocketIO.readLine(fd)
        guard let response = try? CalmaJSON.decoder().decode(CalmaResponse.self, from: data) else {
            throw CalmaIPCError.badResponse
        }
        return response
    }
}

public enum SocketIO {
    public static let maxMessageSize = 1 << 20

    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, base + offset, buffer.count - offset)
                if written <= 0 { throw CalmaIPCError.transport(String(cString: strerror(errno))) }
                offset += written
            }
        }
    }

    /// Reads until a newline or EOF.
    public static func readLine(_ fd: Int32) throws -> Data {
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while result.count < maxMessageSize {
            let count = read(fd, &chunk, chunk.count)
            if count < 0 { throw CalmaIPCError.transport(String(cString: strerror(errno))) }
            if count == 0 { break }
            if let newline = chunk[0..<count].firstIndex(of: 0x0A) {
                result.append(contentsOf: chunk[0..<newline])
                return result
            }
            result.append(contentsOf: chunk[0..<count])
        }
        return result
    }
}
