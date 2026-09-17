import Foundation

/// Every SMC key Calma knows about, and the only keys `calmad` will ever write.
///
/// See docs/SMC_KEYS.md for meanings, values and model compatibility. Adding a key here
/// requires documenting it there first — this list is the safety boundary of the project.
public enum SMCKey {
    // MARK: Charging inhibit
    /// Apple Silicon, firmware before ~macOS 15.4: 1 byte, `0x02` inhibits, `0x00` allows. Paired with CH0C.
    public static let chargeInhibitB = "CH0B"
    /// Apple Silicon legacy firmware + many Intel Macs: 1 byte, `0x02` inhibits, `0x00` allows.
    public static let chargeInhibitC = "CH0C"
    /// Apple Silicon, newer firmware: 4 bytes, `01 00 00 00` inhibits, `00 00 00 00` allows.
    public static let chargeInhibitTE = "CHTE"

    // MARK: Adapter (force discharge while plugged in)
    /// Legacy firmware: 1 byte, `0x01` disconnects the adapter (battery powers the Mac), `0x00` reconnects.
    public static let adapterInhibitI = "CH0I"
    /// Newer firmware: 1 byte, `0x08` disconnects the adapter, `0x00` reconnects.
    public static let adapterInhibitIE = "CHIE"

    // MARK: Intel
    /// Intel only: hardware charge ceiling in percent (1 byte). `0x64` (100) is the default.
    public static let intelChargeLimit = "BCLM"

    // MARK: MagSafe
    /// MagSafe 3 LED: `0x00` system control, `0x01` off, `0x03` green, `0x04` amber.
    public static let magSafeLED = "ACLC"

    // MARK: Read-only telemetry
    public static let batteryTemperatureKeys = ["TB0T", "TB1T", "TB2T"]
    /// Battery management system's own state of charge (read-only).
    public static let hardwareStateOfCharge = "BRSC"

    /// Keys calmad is permitted to write. Anything else is refused before reaching IOKit.
    public static let writeAllowlist: Set<String> = [
        chargeInhibitB, chargeInhibitC, chargeInhibitTE,
        adapterInhibitI, adapterInhibitIE,
        intelChargeLimit, magSafeLED,
    ]

    /// Keys captured by the first-run probe so their original values are on record.
    public static let probeKeys: [String] = [
        chargeInhibitB, chargeInhibitC, chargeInhibitTE,
        adapterInhibitI, adapterInhibitIE,
        intelChargeLimit, magSafeLED, hardwareStateOfCharge,
        "CHWA", "CHBI",
    ] + batteryTemperatureKeys
}

/// Values for the MagSafe LED key.
public enum MagSafeLEDValue: UInt8 {
    case system = 0x00
    case off = 0x01
    case green = 0x03
    case amber = 0x04
}

/// Wraps any `SMCAccess` and refuses writes to keys outside the allowlist.
public final class AllowlistedSMC: SMCAccess {
    private let base: SMCAccess
    private let allowlist: Set<String>

    public init(_ base: SMCAccess, allowlist: Set<String> = SMCKey.writeAllowlist) {
        self.base = base
        self.allowlist = allowlist
    }

    public func read(_ key: String) throws -> SMCValue {
        try base.read(key)
    }

    public func write(_ key: String, _ value: SMCValue) throws {
        guard allowlist.contains(key) else { throw SMCError.notAllowed(key) }
        try base.write(key, value)
    }
}
