import Foundation

/// All user-configurable behaviour. Owned by `calmad`, persisted as JSON, edited by the app and CLI.
///
/// Every field has a default so older settings files decode cleanly after upgrades.
public struct CalmaSettings: Codable, Equatable, Sendable {
    // MARK: Charge
    /// Target maximum charge, 20...100.
    public var chargeLimit: Int = 80
    /// Drift Range: once at the limit, don't resume charging until the level falls this far below it.
    public var driftRangeEnabled: Bool = false
    public var driftRange: Int = 5
    /// Auto Drain: if the level is above the limit while plugged in, drain down to it automatically.
    public var autoDrain: Bool = false
    /// Use the battery controller's raw percentage instead of the value macOS displays.
    public var useHardwarePercentage: Bool = false
    /// Stop all charging until switched off again.
    public var chargingPaused: Bool = false

    // MARK: Protection
    public var heatGuardEnabled: Bool = false
    public var heatGuardThreshold: Double = 35

    // MARK: Sleep & lifecycle
    /// Inhibit charging right before sleep so the Mac can't charge to 100% overnight.
    public var pauseChargingOnSleep: Bool = false
    /// Keep the Mac awake while it charges toward the limit (display may still sleep).
    public var stayAwakeUntilLimit: Bool = false
    /// Keep enforcing the limit when the app is quit. When off, charging is restored on quit.
    public var keepLimitWhenAppClosed: Bool = false

    // MARK: MagSafe
    public var magSafeLED: MagSafeLEDMode = .system
    public var magSafeBlinkWhileDraining: Bool = false

    // MARK: Schedule
    public var schedule: [ScheduledTask] = []

    public init() {}

    /// Clamp everything into safe ranges. Called on every write.
    public mutating func sanitize() {
        chargeLimit = min(100, max(CalmaLimits.minimumChargeLimit, chargeLimit))
        driftRange = min(20, max(1, driftRange))
        heatGuardThreshold = min(50, max(25, heatGuardThreshold))
    }

    private enum CodingKeys: String, CodingKey {
        case chargeLimit, driftRangeEnabled, driftRange, autoDrain, useHardwarePercentage, chargingPaused
        case heatGuardEnabled, heatGuardThreshold
        case pauseChargingOnSleep, stayAwakeUntilLimit, keepLimitWhenAppClosed
        case magSafeLED, magSafeBlinkWhileDraining, schedule
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CalmaSettings.defaults
        chargeLimit = try c.decodeIfPresent(Int.self, forKey: .chargeLimit) ?? d.chargeLimit
        driftRangeEnabled = try c.decodeIfPresent(Bool.self, forKey: .driftRangeEnabled) ?? d.driftRangeEnabled
        driftRange = try c.decodeIfPresent(Int.self, forKey: .driftRange) ?? d.driftRange
        autoDrain = try c.decodeIfPresent(Bool.self, forKey: .autoDrain) ?? d.autoDrain
        useHardwarePercentage = try c.decodeIfPresent(Bool.self, forKey: .useHardwarePercentage) ?? d.useHardwarePercentage
        chargingPaused = try c.decodeIfPresent(Bool.self, forKey: .chargingPaused) ?? d.chargingPaused
        heatGuardEnabled = try c.decodeIfPresent(Bool.self, forKey: .heatGuardEnabled) ?? d.heatGuardEnabled
        heatGuardThreshold = try c.decodeIfPresent(Double.self, forKey: .heatGuardThreshold) ?? d.heatGuardThreshold
        pauseChargingOnSleep = try c.decodeIfPresent(Bool.self, forKey: .pauseChargingOnSleep) ?? d.pauseChargingOnSleep
        stayAwakeUntilLimit = try c.decodeIfPresent(Bool.self, forKey: .stayAwakeUntilLimit) ?? d.stayAwakeUntilLimit
        keepLimitWhenAppClosed = try c.decodeIfPresent(Bool.self, forKey: .keepLimitWhenAppClosed) ?? d.keepLimitWhenAppClosed
        magSafeLED = try c.decodeIfPresent(MagSafeLEDMode.self, forKey: .magSafeLED) ?? d.magSafeLED
        magSafeBlinkWhileDraining = try c.decodeIfPresent(Bool.self, forKey: .magSafeBlinkWhileDraining) ?? d.magSafeBlinkWhileDraining
        schedule = try c.decodeIfPresent([ScheduledTask].self, forKey: .schedule) ?? d.schedule
    }

    public static let defaults = CalmaSettings()
}

public enum MagSafeLEDMode: String, Codable, CaseIterable, Sendable {
    /// Leave the LED to macOS.
    case system
    /// Green at the limit, amber while charging or draining toward it.
    case status
    /// Always off.
    case off
}

public enum CalmaLimits {
    public static let minimumChargeLimit = 20
    /// Draining is refused below this level.
    public static let minimumDrainStartLevel = 20
    /// Heat Guard pause / guaranteed-resume window.
    public static let heatGuardWindow: TimeInterval = 5 * 60
    /// Recalibrate holds the battery at 100% for this long before finishing.
    public static let recalibrationHold: TimeInterval = 60 * 60
    public static let recalibrationLowPoint = 10
}

/// Filesystem and IPC locations shared by every component.
public enum CalmaPaths {
    public static let bundleIdentifier = "io.github.milanpatel35.calma"
    public static let daemonLabel = "io.github.milanpatel35.calmad"

    private static let environment = ProcessInfo.processInfo.environment

    /// Overridable with `CALMA_SOCKET` so the daemon can be run unprivileged during development.
    public static var socketPath: String { environment["CALMA_SOCKET"] ?? "/var/run/calmad.sock" }
    /// Overridable with `CALMA_SUPPORT_DIR` for development and tests.
    public static var supportDirectory: String { environment["CALMA_SUPPORT_DIR"] ?? "/Library/Application Support/Calma" }
    public static var settingsFile: String { supportDirectory + "/settings.json" }
    public static var runtimeFile: String { supportDirectory + "/runtime.json" }
    public static var probeFile: String { supportDirectory + "/smc-probe.json" }
    /// Overridable with `CALMA_LOG_DIR`.
    public static var logDirectory: String { environment["CALMA_LOG_DIR"] ?? "/Library/Logs/Calma" }

    public static let daemonBinary = "/Library/PrivilegedHelperTools/calmad"
    public static let daemonPlist = "/Library/LaunchDaemons/\(daemonLabel).plist"
    public static let cliSymlink = "/usr/local/bin/calma"
    public static let repository = "Milanpatel35/calma"
    // swiftlint:disable:next force_unwrapping
    public static let repositoryURL = URL(string: "https://github.com/\(repository)")!
}
