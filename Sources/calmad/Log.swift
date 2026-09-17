import CalmaKit
import Foundation

/// Local rotating log. Nothing written here ever leaves the machine.
final class DaemonLog {
    private let directory: String
    private let path: String
    private let maxBytes = 1_000_000
    private let keepFiles = 3
    private let queue = DispatchQueue(label: "calmad.log")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(directory: String = CalmaPaths.logDirectory) {
        self.directory = directory
        self.path = directory + "/calmad.log"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    func info(_ message: String) { write("INFO", message) }
    func warn(_ message: String) { write("WARN", message) }
    func error(_ message: String) { write("ERROR", message) }

    func smcWrite(key: String, old: String, new: String, reason: String) {
        write("SMC", "\(key) \(old) -> \(new) (\(reason))")
    }

    private func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.sync {
            rotateIfNeeded()
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: Data(line.utf8),
                                               attributes: [.posixPermissions: 0o644])
            }
        }
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > maxBytes else { return }
        for index in stride(from: keepFiles - 1, through: 1, by: -1) {
            let from = "\(path).\(index)"
            let to = "\(path).\(index + 1)"
            try? fm.removeItem(atPath: to)
            try? fm.moveItem(atPath: from, toPath: to)
        }
        try? fm.removeItem(atPath: "\(path).1")
        try? fm.moveItem(atPath: path, toPath: "\(path).1")
    }
}
