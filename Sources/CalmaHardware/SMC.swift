import CSMC
import Foundation

/// A value read from, or written to, a System Management Controller key.
public struct SMCValue: Equatable, Sendable {
    public var bytes: [UInt8]
    /// Four-character data type (for example `ui8 `, `ui32`, `flt `, `hex_`, `sp78`).
    public var type: String

    public init(bytes: [UInt8], type: String = "") {
        self.bytes = bytes
        self.type = type
    }

    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// Interprets the value as a temperature/float, handling Apple Silicon (`flt `) and Intel (`sp78`).
    public var doubleValue: Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return nil
        }
    }
}

public enum SMCError: Error, CustomStringConvertible, Equatable {
    case unavailable
    case keyNotFound(String)
    case readFailed(String, Int32)
    case writeFailed(String, Int32)
    case notAllowed(String)

    public var description: String {
        switch self {
        case .unavailable: return "AppleSMC service is not available"
        case .keyNotFound(let key): return "SMC key \(key) does not exist on this Mac"
        case .readFailed(let key, let code): return "Reading SMC key \(key) failed (\(code))"
        case .writeFailed(let key, let code): return "Writing SMC key \(key) failed (\(code)). Is calmad running as root?"
        case .notAllowed(let key): return "SMC key \(key) is not on Calma's write allowlist"
        }
    }
}

/// Anything that can read and write SMC keys. The real implementation talks to IOKit;
/// tests use an in-memory fake so they never touch hardware.
public protocol SMCAccess: AnyObject {
    func read(_ key: String) throws -> SMCValue
    func write(_ key: String, _ value: SMCValue) throws
}

public extension SMCAccess {
    func exists(_ key: String) -> Bool {
        (try? read(key)) != nil
    }
}

/// Direct IOKit connection to `AppleSMC`.
public final class SMCConnection: SMCAccess {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

    public init() throws {
        var conn: io_connect_t = 0
        guard calma_smc_open(&conn) == KERN_SUCCESS else { throw SMCError.unavailable }
        connection = conn
    }

    deinit {
        calma_smc_close(connection)
    }

    public func read(_ key: String) throws -> SMCValue {
        lock.lock(); defer { lock.unlock() }
        var value = calma_smc_value()
        let result = key.withCString { calma_smc_read(connection, $0, &value) }
        if result == KERN_INVALID_ARGUMENT { throw SMCError.keyNotFound(key) }
        guard result == KERN_SUCCESS else { throw SMCError.readFailed(key, result) }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(value.size))) }
        return SMCValue(bytes: bytes, type: Self.fourCharString(value.type))
    }

    public func write(_ key: String, _ value: SMCValue) throws {
        lock.lock(); defer { lock.unlock() }
        var raw = calma_smc_value()
        raw.size = UInt32(value.bytes.count)
        withUnsafeMutableBytes(of: &raw.bytes) { buffer in
            for (index, byte) in value.bytes.prefix(Int(CALMA_SMC_MAX_BYTES)).enumerated() {
                buffer[index] = byte
            }
        }
        let result = key.withCString { calma_smc_write(connection, $0, &raw) }
        guard result == KERN_SUCCESS else { throw SMCError.writeFailed(key, result) }
    }

    /// Every key name the SMC reports (read-only; used by `calma probe` for hardware reports).
    public func allKeys() -> [String] {
        guard let count = try? read("#KEY") else { return [] }
        let total = count.bytes.reduce(0) { $0 << 8 | Int($1) }
        lock.lock(); defer { lock.unlock() }
        var names: [String] = []
        var buffer = [CChar](repeating: 0, count: 5)
        for index in 0..<total where calma_smc_key_at_index(connection, UInt32(index), &buffer) == KERN_SUCCESS {
            names.append(String(cString: buffer))
        }
        return names
    }

    static func fourCharString(_ code: UInt32) -> String {
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> UInt32($0)) & 0xff))) }
        return String(chars)
    }
}
