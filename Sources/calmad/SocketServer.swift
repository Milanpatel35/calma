import CalmaKit
import Foundation

/// Identity of the process on the other end of a socket connection.
struct Peer {
    let uid: uid_t
    let userName: String
    let isAdmin: Bool
}

/// Unix domain socket server. Accepts connections on a background queue and hands each decoded
/// command to `handler` on the main queue, where all daemon state lives.
final class SocketServer {
    typealias Handler = (CalmaCommand, Peer) -> CalmaResponse

    private let path: String
    private let handler: Handler
    private let log: DaemonLog
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "calmad.socket", attributes: .concurrent)

    init(path: String, log: DaemonLog, handler: @escaping Handler) {
        self.path = path
        self.log = log
        self.handler = handler
    }

    func start() throws {
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw CalmaIPCError.transport("socket(): \(String(cString: strerror(errno)))") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw CalmaIPCError.transport("socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw CalmaIPCError.transport("bind(\(path)): \(String(cString: strerror(errno)))") }
        // Anyone may connect (so non-admin users can see status); authorization happens per command.
        chmod(path, 0o666)
        guard listen(listenFD, 16) == 0 else { throw CalmaIPCError.transport("listen(): \(String(cString: strerror(errno)))") }

        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: ioQueue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        if listenFD >= 0 { close(listenFD) }
        unlink(path)
    }

    private func acceptConnection() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        ioQueue.async { [self] in
            defer { close(fd) }
            var tv = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            let response: CalmaResponse
            if let peer = Self.peer(of: fd) {
                do {
                    let line = try SocketIO.readLine(fd)
                    let command = try CalmaJSON.decoder().decode(CalmaCommand.self, from: line)
                    if command.requiresAdmin && !peer.isAdmin {
                        log.warn("Refused \(command) from non-admin user \(peer.userName)")
                        response = .failure("Only administrators can change Calma's settings")
                    } else {
                        response = DispatchQueue.main.sync { handler(command, peer) }
                    }
                } catch {
                    response = .failure("Malformed request")
                }
            } else {
                response = .failure("Couldn't verify the connecting process")
            }

            if var data = try? CalmaJSON.encoder().encode(response) {
                data.append(0x0A)
                try? SocketIO.writeAll(fd, data)
            }
        }
    }

    /// Uses the kernel-reported credentials of the connecting process; these can't be spoofed by the client.
    static func peer(of fd: Int32) -> Peer? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return nil }
        let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? "uid \(uid)"
        return Peer(uid: uid, userName: name, isAdmin: uid == 0 || isMemberOfAdmin(userName: name, primaryGroup: gid))
    }

    static func isMemberOfAdmin(userName: String, primaryGroup: gid_t) -> Bool {
        guard let adminGroup = getgrnam("admin") else { return false }
        let adminGID = adminGroup.pointee.gr_gid
        if primaryGroup == adminGID { return true }
        var count: Int32 = 64
        var groups = [Int32](repeating: 0, count: Int(count))
        if getgrouplist(userName, Int32(bitPattern: primaryGroup), &groups, &count) == -1 {
            groups = [Int32](repeating: 0, count: Int(count) + 1)
            count = Int32(groups.count)
            guard getgrouplist(userName, Int32(bitPattern: primaryGroup), &groups, &count) != -1 else { return false }
        }
        return groups.prefix(Int(count)).contains(Int32(bitPattern: adminGID))
    }
}
