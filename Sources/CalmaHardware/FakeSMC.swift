import Foundation

/// In-memory SMC used by unit tests and by `calmad --simulate` for development on any Mac.
public final class FakeSMC: SMCAccess {
    public private(set) var keys: [String: SMCValue]
    public private(set) var writes: [(key: String, bytes: [UInt8])] = []
    public var failWrites = false

    public init(keys: [String: SMCValue]) {
        self.keys = keys
    }

    public func read(_ key: String) throws -> SMCValue {
        guard let value = keys[key] else { throw SMCError.keyNotFound(key) }
        return value
    }

    public func write(_ key: String, _ value: SMCValue) throws {
        guard var existing = keys[key] else { throw SMCError.keyNotFound(key) }
        if failWrites { throw SMCError.writeFailed(key, -1) }
        guard existing.bytes.count == value.bytes.count else { throw SMCError.writeFailed(key, -1) }
        existing.bytes = value.bytes
        keys[key] = existing
        writes.append((key, value.bytes))
    }

    /// Apple Silicon on macOS 15–26 firmware.
    public static func modernAppleSilicon() -> FakeSMC {
        FakeSMC(keys: [
            "CHTE": SMCValue(bytes: [0, 0, 0, 0], type: "ui32"),
            "CHIE": SMCValue(bytes: [0], type: "hex_"),
            "ACLC": SMCValue(bytes: [0], type: "ui8 "),
            "TB0T": SMCValue(bytes: [0x9A, 0x99, 0xF9, 0x41], type: "flt "),
        ])
    }

    /// Apple Silicon on older firmware.
    public static func legacyAppleSilicon() -> FakeSMC {
        FakeSMC(keys: [
            "CH0B": SMCValue(bytes: [0], type: "hex_"),
            "CH0C": SMCValue(bytes: [0], type: "hex_"),
            "CH0I": SMCValue(bytes: [0], type: "hex_"),
            "TB0T": SMCValue(bytes: [0x9A, 0x99, 0xF9, 0x41], type: "flt "),
        ])
    }

    /// macOS 27 firmware as observed on a Mac16,1: no documented inhibit key.
    public static func goldenGate() -> FakeSMC {
        FakeSMC(keys: [
            "CHIE": SMCValue(bytes: [0], type: "hex_"),
            "ACLC": SMCValue(bytes: [2], type: "ui8 "),
            "CHLT": SMCValue(bytes: [0x50, 0x05, 0x05], type: "hex_"),
        ])
    }
}
