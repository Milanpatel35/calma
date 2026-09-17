import Foundation

/// What the hardware should be told to do after one evaluation.
public struct ChargeDecision: Equatable, Sendable {
    /// Whether the battery may charge.
    public var chargingAllowed: Bool
    /// Whether the adapter powers the Mac. `false` = run from battery while plugged in (draining).
    public var adapterEnabled: Bool
    /// Whether to hold a system-sleep assertion.
    public var preventSleep: Bool
    public var led: LEDDecision
    public var state: ChargeState
    /// Human-readable notes about transitions that happened in this evaluation (for the log).
    public var events: [String]

    public init(chargingAllowed: Bool, adapterEnabled: Bool, preventSleep: Bool, led: LEDDecision,
                state: ChargeState, events: [String] = []) {
        self.chargingAllowed = chargingAllowed
        self.adapterEnabled = adapterEnabled
        self.preventSleep = preventSleep
        self.led = led
        self.state = state
        self.events = events
    }

    /// The "hands off" decision: stock macOS behaviour.
    public static let stock = ChargeDecision(chargingAllowed: true, adapterEnabled: true, preventSleep: false,
                                             led: .system, state: .charging)
}

public enum LEDDecision: String, Codable, Equatable, Sendable {
    case system, off, green, amber, amberBlink
}

public struct EngineInput: Sendable {
    public var settings: CalmaSettings
    public var battery: BatterySnapshot
    public var capabilities: Capabilities
    public var now: Date

    public init(settings: CalmaSettings, battery: BatterySnapshot, capabilities: Capabilities, now: Date) {
        self.settings = settings
        self.battery = battery
        self.capabilities = capabilities
        self.now = now
    }
}

/// The heart of Calma: a pure function from (settings, battery, previous state) to a decision.
///
/// It performs no I/O, so every rule — limits, Drift Range, Heat Guard, Recalibrate, Full Charge,
/// draining — is covered by unit tests without touching hardware.
public enum ChargeEngine {
    public static func evaluate(_ input: EngineInput, runtime: inout RuntimeState) -> ChargeDecision {
        let settings = input.settings
        let battery = input.battery
        let caps = input.capabilities
        let now = input.now
        let level = battery.effectivePercentage(useHardware: settings.useHardwarePercentage)
        let plugged = battery.isPluggedIn
        var events: [String] = []

        // Full Charge ends the moment the adapter is removed.
        if runtime.wasPluggedIn && !plugged, runtime.mode == .fullCharge {
            setMode(.normal, runtime: &runtime, now: now)
            events.append("Adapter removed — full charge finished, limit restored")
        }
        runtime.wasPluggedIn = plugged

        // Without hardware support, nothing but stock behaviour is possible.
        if !caps.canDrain, isDrainingMode(runtime.mode) {
            setMode(.normal, runtime: &runtime, now: now)
            events.append("Draining isn't supported on this Mac — cancelled")
        }

        var allowCharge = true
        var adapterOn = true

        // MARK: Mode-specific rules
        advanceRecalibration(level: level, runtime: &runtime, now: now, events: &events)

        switch runtime.mode {
        case .recalibrate(let stage):
            switch stage {
            case .chargeToFull, .rechargeToFull, .holdAtFull:
                allowCharge = true
            case .drainToLow:
                allowCharge = false
                adapterOn = false
            }

        case .fullCharge:
            allowCharge = true

        case .drain(let target):
            if level <= target {
                setMode(.normal, runtime: &runtime, now: now)
                events.append("Reached \(target)% — draining stopped")
                (allowCharge, adapterOn) = normalRules(level: level, plugged: plugged, settings: settings, caps: caps, runtime: &runtime)
            } else {
                allowCharge = false
                adapterOn = false
            }

        case .normal:
            (allowCharge, adapterOn) = normalRules(level: level, plugged: plugged, settings: settings, caps: caps, runtime: &runtime)
        }

        // MARK: Heat Guard (suspended during recalibration)
        var heatPaused = false
        if case .recalibrate = runtime.mode {
            runtime.heatGuard = .idle
        } else if settings.heatGuardEnabled, plugged {
            heatPaused = applyHeatGuard(temperature: battery.temperature, threshold: settings.heatGuardThreshold,
                                        wantsToCharge: allowCharge, runtime: &runtime, now: now, events: &events)
            if heatPaused { allowCharge = false }
        } else {
            runtime.heatGuard = .idle
        }

        // MARK: Hardware capability clamps
        if !caps.canInhibitCharging { allowCharge = true }
        if !caps.canDrain { adapterOn = true }
        // Adapter state is meaningless unplugged; always leave it enabled so plugging in is safe.
        if !plugged { adapterOn = true }

        // MARK: Derived outputs
        let state: ChargeState
        if !plugged {
            state = .onBattery
        } else if !adapterOn {
            state = .draining
        } else if heatPaused {
            state = .heatPaused
        } else if allowCharge && level < 100 {
            state = .charging
        } else {
            state = .paused
        }

        var preventSleep = false
        if plugged {
            if !adapterOn { preventSleep = true }
            if case .recalibrate = runtime.mode { preventSleep = true }
            if settings.stayAwakeUntilLimit, runtime.mode == .normal, state == .charging,
               level < settings.chargeLimit {
                preventSleep = true
            }
        }

        let led = ledDecision(settings: settings, caps: caps, plugged: plugged, state: state)
        return ChargeDecision(chargingAllowed: allowCharge, adapterEnabled: adapterOn, preventSleep: preventSleep,
                              led: led, state: state, events: events)
    }

    // MARK: - Rules

    private static func normalRules(level: Int, plugged: Bool, settings: CalmaSettings, caps: Capabilities,
                                    runtime: inout RuntimeState) -> (charge: Bool, adapter: Bool) {
        let limit = settings.chargeLimit

        if settings.chargingPaused {
            return (false, true)
        }

        // Auto Drain: bring an over-limit battery down while plugged in.
        if settings.autoDrain, plugged, caps.canDrain, level > limit {
            runtime.chargingLatch = false
            return (false, false)
        }

        // A 100% limit means stock behaviour.
        if limit >= 100 {
            runtime.chargingLatch = true
            return (true, true)
        }

        let resumeBelow = settings.driftRangeEnabled ? limit - settings.driftRange : limit
        if level >= limit {
            runtime.chargingLatch = false
        } else if level < resumeBelow {
            runtime.chargingLatch = true
        }
        // Between resumeBelow and limit: keep the previous latch (this is the drift band).
        return (runtime.chargingLatch, true)
    }

    private static func advanceRecalibration(level: Int, runtime: inout RuntimeState, now: Date, events: inout [String]) {
        // Loop so multiple stages can complete in a single evaluation (e.g. after a long sleep).
        for _ in 0..<RecalibrationStage.allCases.count {
            guard case .recalibrate(let stage) = runtime.mode else { return }
            switch stage {
            case .chargeToFull where level >= 100:
                runtime.mode = .recalibrate(.drainToLow)
                runtime.stageStartedAt = now
                events.append("Recalibration: reached 100%, draining to \(CalmaLimits.recalibrationLowPoint)%")
            case .drainToLow where level <= CalmaLimits.recalibrationLowPoint:
                runtime.mode = .recalibrate(.rechargeToFull)
                runtime.stageStartedAt = now
                events.append("Recalibration: reached \(CalmaLimits.recalibrationLowPoint)%, recharging")
            case .rechargeToFull where level >= 100:
                runtime.mode = .recalibrate(.holdAtFull)
                runtime.stageStartedAt = now
                events.append("Recalibration: full again, holding for one hour")
            case .holdAtFull:
                let started = runtime.stageStartedAt ?? now
                if runtime.stageStartedAt == nil { runtime.stageStartedAt = now }
                if now.timeIntervalSince(started) >= CalmaLimits.recalibrationHold {
                    setMode(.normal, runtime: &runtime, now: now)
                    events.append("Recalibration complete — charge limit restored")
                }
                return
            default:
                return
            }
        }
    }

    private static func applyHeatGuard(temperature: Double?, threshold: Double, wantsToCharge: Bool,
                                       runtime: inout RuntimeState, now: Date, events: inout [String]) -> Bool {
        let window = CalmaLimits.heatGuardWindow
        switch runtime.heatGuard {
        case .idle:
            guard let temperature, wantsToCharge, temperature >= threshold else { return false }
            runtime.heatGuard = .paused(until: now.addingTimeInterval(window))
            events.append(String(format: "Heat Guard: battery at %.1f °C, pausing charging for 5 minutes", temperature))
            return true

        case .paused(let until):
            guard now >= until else { return true }
            // Unknown temperature while paused: stay cautious and extend the pause.
            if temperature.map({ $0 >= threshold }) ?? true {
                runtime.heatGuard = .paused(until: now.addingTimeInterval(window))
                events.append("Heat Guard: still hot, pausing another 5 minutes")
                return true
            }
            runtime.heatGuard = .resumed(until: now.addingTimeInterval(window))
            events.append("Heat Guard: cooled down, charging resumes for at least 5 minutes")
            return false

        case .resumed(let until):
            if now >= until { runtime.heatGuard = .idle }
            return false
        }
    }

    private static func ledDecision(settings: CalmaSettings, caps: Capabilities, plugged: Bool, state: ChargeState) -> LEDDecision {
        guard caps.hasMagSafeLED, plugged else { return .system }
        switch settings.magSafeLED {
        case .system: return .system
        case .off: return .off
        case .status:
            switch state {
            case .draining: return settings.magSafeBlinkWhileDraining ? .amberBlink : .amber
            case .charging: return .amber
            case .paused, .heatPaused, .onBattery: return .green
            }
        }
    }

    private static func isDrainingMode(_ mode: ActiveMode) -> Bool {
        switch mode {
        case .drain, .recalibrate: return true
        case .normal, .fullCharge: return false
        }
    }

    public static func setMode(_ mode: ActiveMode, runtime: inout RuntimeState, now: Date) {
        runtime.mode = mode
        runtime.modeStartedAt = mode == .normal ? nil : now
        runtime.stageStartedAt = nil
        if mode == .normal { runtime.chargingLatch = true }
    }

    // MARK: - Presentation

    public static func summary(state: ChargeState, level: Int, settings: CalmaSettings, runtime: RuntimeState,
                               battery: BatterySnapshot, caps: Capabilities) -> String {
        var parts: [String] = []
        switch runtime.mode {
        case .recalibrate(let stage): parts.append("Recalibrating · \(stage.title)")
        case .fullCharge: parts.append(state == .onBattery ? "Full charge armed · \(level)%" : "Full charge · \(level)%")
        case .drain(let target): parts.append(state == .onBattery ? "On battery · \(level)%" : "Draining \(level)% → \(target)%")
        case .normal:
            switch state {
            case .charging: parts.append("Charging to \(settings.chargeLimit)%")
            case .paused: parts.append(settings.chargingPaused ? "Charging paused · \(level)%" : "Holding at \(level)%")
            case .draining: parts.append("Draining \(level)% → \(settings.chargeLimit)%")
            case .onBattery: parts.append("On battery · \(level)%")
            case .heatPaused: parts.append("Paused — battery warm")
            }
        }
        if battery.isPluggedIn, let watts = battery.adapterWatts, watts > 0 {
            parts.append("Adapter \(watts) W")
        }
        if caps.backend == .unsupported {
            parts = ["Monitoring only · \(level)%"]
        }
        return parts.joined(separator: " · ")
    }
}
