import Foundation

/// A point-in-time reading of the battery and power adapter.
public struct BatterySnapshot: Codable, Equatable, Sendable {
    /// Percentage as macOS reports it.
    public var percentage: Int
    /// Raw percentage from the battery management system, when available.
    public var hardwarePercentage: Int?
    public var isPluggedIn: Bool
    public var isCharging: Bool
    /// Battery temperature in °C, when readable.
    public var temperature: Double?
    public var cycleCount: Int?
    public var designCapacity: Int?
    public var fullChargeCapacity: Int?
    /// Battery voltage in millivolts.
    public var voltage: Int?
    /// Battery current in milliamps. Positive = charging, negative = discharging.
    public var amperage: Int?
    /// Adapter rating in watts.
    public var adapterWatts: Int?
    /// Measured power flowing in from the adapter, in watts.
    public var systemPowerIn: Double?
    /// Measured total system load, in watts.
    public var systemLoad: Double?

    public init(percentage: Int, hardwarePercentage: Int? = nil, isPluggedIn: Bool, isCharging: Bool,
                temperature: Double? = nil, cycleCount: Int? = nil, designCapacity: Int? = nil,
                fullChargeCapacity: Int? = nil, voltage: Int? = nil, amperage: Int? = nil,
                adapterWatts: Int? = nil, systemPowerIn: Double? = nil, systemLoad: Double? = nil) {
        self.percentage = percentage
        self.hardwarePercentage = hardwarePercentage
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.temperature = temperature
        self.cycleCount = cycleCount
        self.designCapacity = designCapacity
        self.fullChargeCapacity = fullChargeCapacity
        self.voltage = voltage
        self.amperage = amperage
        self.adapterWatts = adapterWatts
        self.systemPowerIn = systemPowerIn
        self.systemLoad = systemLoad
    }

    /// Battery health as full-charge capacity relative to design capacity.
    public var health: Int? {
        guard let design = designCapacity, let full = fullChargeCapacity, design > 0 else { return nil }
        return Int((Double(full) / Double(design) * 100).rounded())
    }

    /// Power flowing into (+) or out of (−) the battery, in watts.
    public var batteryWatts: Double? {
        guard let voltage, let amperage else { return nil }
        return Double(voltage) * Double(amperage) / 1_000_000
    }

    public func effectivePercentage(useHardware: Bool) -> Int {
        useHardware ? (hardwarePercentage ?? percentage) : percentage
    }
}

/// How the daemon can control this particular Mac.
public enum ChargeBackend: String, Codable, Sendable {
    /// Apple Silicon, older firmware: CH0B/CH0C + CH0I.
    case appleSiliconLegacy
    /// Apple Silicon, macOS 15–26 firmware: CHTE + CHIE.
    case appleSiliconModern
    /// Intel: BCLM hardware ceiling, CH0B/CH0C + CH0I where present.
    case intel
    /// No known, documented charge-inhibit key (for example macOS 27 firmware). Read-only mode.
    case unsupported
}

public struct Capabilities: Codable, Equatable, Sendable {
    public var backend: ChargeBackend
    public var canInhibitCharging: Bool
    public var canDrain: Bool
    public var hasMagSafeLED: Bool
    /// macOS's own charge limit (macOS 26.4+), when it can be read.
    public var nativeChargeLimit: Int?
    public var modelIdentifier: String
    public var osVersion: String

    public init(backend: ChargeBackend, canInhibitCharging: Bool, canDrain: Bool, hasMagSafeLED: Bool,
                nativeChargeLimit: Int? = nil, modelIdentifier: String = "", osVersion: String = "") {
        self.backend = backend
        self.canInhibitCharging = canInhibitCharging
        self.canDrain = canDrain
        self.hasMagSafeLED = hasMagSafeLED
        self.nativeChargeLimit = nativeChargeLimit
        self.modelIdentifier = modelIdentifier
        self.osVersion = osVersion
    }

    public static let none = Capabilities(backend: .unsupported, canInhibitCharging: false, canDrain: false, hasMagSafeLED: false)
}

/// What Calma is currently doing. Drives the menu bar icon.
public enum ChargeState: String, Codable, Sendable {
    case charging
    case paused
    case draining
    case onBattery
    case heatPaused
}

/// The special modes that temporarily override the normal limit.
public enum ActiveMode: Codable, Equatable, Sendable {
    case normal
    /// Charge to 100% once; ends when the Mac is unplugged.
    case fullCharge
    /// Drain to a specific level while plugged in.
    case drain(target: Int)
    case recalibrate(RecalibrationStage)
}

public enum RecalibrationStage: String, Codable, CaseIterable, Sendable {
    case chargeToFull
    case drainToLow
    case rechargeToFull
    case holdAtFull

    public var title: String {
        switch self {
        case .chargeToFull: return "Charging to 100%"
        case .drainToLow: return "Draining to 10%"
        case .rechargeToFull: return "Recharging to 100%"
        case .holdAtFull: return "Holding at 100% for one hour"
        }
    }
}

/// Heat Guard hysteresis state.
public enum HeatGuardPhase: Codable, Equatable, Sendable {
    case idle
    case paused(until: Date)
    case resumed(until: Date)
}

/// State the engine carries between evaluations. Persisted so it survives daemon restarts.
public struct RuntimeState: Codable, Equatable, Sendable {
    public var mode: ActiveMode = .normal
    public var modeStartedAt: Date?
    /// For Recalibrate: when the hold stage started.
    public var stageStartedAt: Date?
    /// Limit in force before Recalibrate started.
    public var limitBeforeRecalibration: Int?
    public var heatGuard: HeatGuardPhase = .idle
    /// Drift Range latch: true while we're allowed to charge up toward the limit.
    public var chargingLatch: Bool = true
    public var wasPluggedIn: Bool = false

    public init() {}
}

/// Everything the app and CLI need to render the current situation.
public struct CalmaStatus: Codable, Equatable, Sendable {
    public var battery: BatterySnapshot
    public var settings: CalmaSettings
    public var runtime: RuntimeState
    public var state: ChargeState
    public var capabilities: Capabilities
    /// Plain-language description, e.g. "Paused at 80% · Adapter 61 W".
    public var summary: String
    /// Short name of the user who last changed settings (fast user switching).
    public var lastChangedBy: String?
    public var daemonVersion: String
    public var taskHistory: [TaskHistoryEntry]

    public init(battery: BatterySnapshot, settings: CalmaSettings, runtime: RuntimeState, state: ChargeState,
                capabilities: Capabilities, summary: String, lastChangedBy: String?, daemonVersion: String,
                taskHistory: [TaskHistoryEntry]) {
        self.battery = battery
        self.settings = settings
        self.runtime = runtime
        self.state = state
        self.capabilities = capabilities
        self.summary = summary
        self.lastChangedBy = lastChangedBy
        self.daemonVersion = daemonVersion
        self.taskHistory = taskHistory
    }
}

public enum CalmaVersion {
    public static let current = "0.1.1"
}
