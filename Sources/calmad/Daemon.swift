import CalmaHardware
import CalmaKit
import Foundation

/// What calmad persists between launches besides settings.
struct PersistedRuntime: Codable {
    var runtime = RuntimeState()
    var history: [TaskHistoryEntry] = []
    var lastChangedBy: String?
}

/// The control loop. All state is touched only on the main queue.
final class Daemon {
    private let log: DaemonLog
    private let controller: ChargeController?
    private let batteryReader: BatteryReader
    private let simulatedBattery: BatterySnapshot?

    private var settings: CalmaSettings
    private var persisted: PersistedRuntime
    private var lastDecision: ChargeDecision = .stock
    private var lastBattery: BatterySnapshot?

    /// True while control is handed back to macOS (app quit without Keep Limit After Quit, or emergency reset).
    private var suspended = false
    /// Set once the menu bar app has checked in; the heartbeat watchdog only applies to app-driven sessions.
    private var lastHeartbeat: Date?
    private let heartbeatTimeout: TimeInterval = 90

    private var tickTimer: DispatchSourceTimer?
    private var blinkTimer: DispatchSourceTimer?
    private var blinkOn = false
    private var powerSourceObserver: PowerSourceObserver?
    private var systemPowerObserver: SystemPowerObserver?
    private let sleepAssertion = SleepAssertion(name: "Calma: charging to limit / draining")
    private var consecutiveWriteFailures = 0

    init(log: DaemonLog, smc: SMCAccess?, simulatedBattery: BatterySnapshot? = nil) {
        self.log = log
        self.simulatedBattery = simulatedBattery
        self.batteryReader = BatteryReader(smc: smc)
        if let smc {
            controller = ChargeController(smc: smc, modelIdentifier: MachineInfo.modelIdentifier, osVersion: MachineInfo.osVersion)
        } else {
            controller = nil
        }
        settings = Self.load(CalmaSettings.self, from: CalmaPaths.settingsFile) ?? CalmaSettings()
        settings.sanitize()
        persisted = Self.load(PersistedRuntime.self, from: CalmaPaths.runtimeFile) ?? PersistedRuntime()

        controller?.onWrite = { [log] record in
            log.smcWrite(key: record.key, old: record.old, new: record.new, reason: record.reason)
        }
    }

    var capabilities: Capabilities { controller?.capabilities ?? .none }

    // MARK: Lifecycle

    func start() {
        try? FileManager.default.createDirectory(atPath: CalmaPaths.supportDirectory, withIntermediateDirectories: true)
        let caps = capabilities
        log.info("calmad \(CalmaVersion.current) starting · model \(caps.modelIdentifier) · \(caps.osVersion)")
        log.info("Backend \(caps.backend.rawValue) · drain \(caps.canDrain) · MagSafe LED \(caps.hasMagSafeLED)")
        if caps.backend == .unsupported {
            log.warn("No documented charge-inhibit key found on this firmware. Running in monitoring mode; no SMC writes will be made.")
        }
        runFirstProbeIfNeeded()

        powerSourceObserver = PowerSourceObserver { [weak self] in self?.tick(reason: "power source changed") }
        systemPowerObserver = SystemPowerObserver { [weak self] event in self?.handle(powerEvent: event) }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(10), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.tick(reason: "timer") }
        timer.resume()
        tickTimer = timer
    }

    /// Called on SIGTERM (shutdown, uninstall, launchctl bootout).
    func shutdown() {
        if settings.keepLimitWhenAppClosed && !suspended {
            log.info("Stopping · Keep Limit After Quit is on, leaving charge state in place")
        } else {
            log.info("Stopping · restoring stock charging")
            restoreStock(reason: "daemon stopping")
        }
        sleepAssertion.set(false)
        save()
    }

    private func runFirstProbeIfNeeded() {
        guard let controller, !FileManager.default.fileExists(atPath: CalmaPaths.probeFile) else { return }
        let probe = controller.probe()
        let record: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "model": capabilities.modelIdentifier,
            "os": capabilities.osVersion,
            "backend": capabilities.backend.rawValue,
            "keys": probe,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
            FileManager.default.createFile(atPath: CalmaPaths.probeFile, contents: data)
            log.info("First-run SMC probe saved to \(CalmaPaths.probeFile): \(probe)")
        }
    }

    // MARK: Control loop

    private func readBattery() -> BatterySnapshot? {
        simulatedBattery ?? batteryReader.read()
    }

    func tick(reason: String) {
        runSchedule()
        checkHeartbeat()

        guard let battery = readBattery() else {
            log.warn("Battery unreadable (\(reason)) — leaving hardware untouched")
            return
        }
        lastBattery = battery

        if suspended {
            sleepAssertion.set(false)
            return
        }

        let before = persisted.runtime
        let input = EngineInput(settings: settings, battery: battery, capabilities: capabilities, now: Date())
        let decision = ChargeEngine.evaluate(input, runtime: &persisted.runtime)
        decision.events.forEach { log.info($0) }
        apply(decision, battery: battery)
        lastDecision = decision
        if persisted.runtime != before { save() }
    }

    private func apply(_ decision: ChargeDecision, battery: BatterySnapshot) {
        guard let controller, capabilities.backend != .unsupported else {
            sleepAssertion.set(false)
            return
        }
        let reason = "\(decision.state.rawValue), limit \(settings.chargeLimit)%, level \(battery.percentage)%"
        do {
            if controller.usesIntelCeilingOnly {
                let ceiling = persisted.runtime.mode == .normal ? settings.chargeLimit : 100
                try controller.setIntelCeiling(ceiling, reason: reason)
            }
            // Order matters: never leave a moment where the adapter is off *and* charging is being enabled.
            if decision.adapterEnabled {
                try controller.setAdapterEnabled(true, reason: reason)
                try controller.setChargingAllowed(decision.chargingAllowed, reason: reason)
            } else {
                try controller.setChargingAllowed(false, reason: reason)
                try controller.setAdapterEnabled(false, reason: reason)
            }
            try applyLED(decision.led, reason: reason)
            consecutiveWriteFailures = 0
        } catch {
            consecutiveWriteFailures += 1
            if consecutiveWriteFailures <= 3 || consecutiveWriteFailures % 60 == 0 {
                log.error("Applying decision failed: \(error)")
            }
        }
        sleepAssertion.set(decision.preventSleep)
    }

    private func applyLED(_ led: LEDDecision, reason: String) throws {
        guard let controller, capabilities.hasMagSafeLED else { return }
        if led != .amberBlink {
            blinkTimer?.cancel()
            blinkTimer = nil
        }
        switch led {
        case .system: try controller.setLED(.system, reason: reason)
        case .off: try controller.setLED(.off, reason: reason)
        case .green: try controller.setLED(.green, reason: reason)
        case .amber: try controller.setLED(.amber, reason: reason)
        case .amberBlink:
            guard blinkTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(800))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.blinkOn.toggle()
                // Blink writes are not logged individually; they'd flood the log.
                let saved = controller.onWrite
                controller.onWrite = nil
                try? controller.setLED(self.blinkOn ? .amber : .off, reason: "blink")
                controller.onWrite = saved
            }
            timer.resume()
            blinkTimer = timer
        }
    }

    private func restoreStock(reason: String) {
        blinkTimer?.cancel()
        blinkTimer = nil
        guard let controller, capabilities.backend != .unsupported else { return }
        for error in controller.restoreDefaults(reason: reason) {
            log.error("Restore failed: \(error)")
        }
        sleepAssertion.set(false)
    }

    // MARK: Sleep

    private func handle(powerEvent: SystemPowerObserver.Event) {
        switch powerEvent {
        case .willSleep:
            guard !suspended, settings.pauseChargingOnSleep, let controller, capabilities.canInhibitCharging else { return }
            do {
                try controller.setChargingAllowed(false, reason: "Pause on Sleep")
                log.info("Going to sleep · charging paused until wake")
            } catch {
                log.error("Pause on Sleep failed: \(error)")
            }
        case .didWake:
            log.info("Woke from sleep")
            tick(reason: "wake")
        }
    }

    // MARK: Heartbeat watchdog

    private func checkHeartbeat() {
        guard !suspended, let last = lastHeartbeat, !settings.keepLimitWhenAppClosed else { return }
        if Date().timeIntervalSince(last) > heartbeatTimeout {
            log.warn("No heartbeat from Calma.app for \(Int(heartbeatTimeout)) s — restoring stock charging")
            suspend(reason: "app heartbeat lost")
        }
    }

    private func suspend(reason: String) {
        suspended = true
        restoreStock(reason: reason)
    }

    private func resumeIfSuspended(_ why: String) {
        guard suspended else { return }
        suspended = false
        log.info("Resuming control (\(why))")
    }

    // MARK: Schedule

    private var isRunningSchedule = false

    private func runSchedule() {
        // perform() re-enters tick(); don't evaluate the schedule recursively.
        guard !isRunningSchedule else { return }
        isRunningSchedule = true
        defer { isRunningSchedule = false }
        let now = Date()
        var changed = false
        for index in settings.schedule.indices {
            let task = settings.schedule[index]
            guard let occurrence = ScheduleCalculator.dueOccurrence(for: task, now: now) else { continue }
            settings.schedule[index].lastRun = occurrence
            if task.repeatRule == .once { settings.schedule[index].enabled = false }
            changed = true

            guard ScheduleCalculator.shouldRun(task, occurrence: occurrence, now: now) else {
                record(task: task.name, result: "Skipped — missed while asleep")
                continue
            }
            let result = perform(task.action.command, peerName: "Schedule")
            record(task: task.name, result: result.ok ? "Done — \(task.action.title)" : "Failed — \(result.error ?? "unknown error")")
        }
        if changed { save() }
    }

    private func record(task: String, result: String) {
        persisted.history.insert(TaskHistoryEntry(taskName: task, date: Date(), result: result), at: 0)
        if persisted.history.count > 50 { persisted.history.removeLast(persisted.history.count - 50) }
        log.info("Scheduled task \"\(task)\": \(result)")
    }

    // MARK: Commands

    func handle(_ command: CalmaCommand, peer: Peer) -> CalmaResponse {
        switch command {
        case .status:
            return CalmaResponse(ok: true, status: status())
        case .appHeartbeat:
            lastHeartbeat = Date()
            resumeIfSuspended("app running")
            return CalmaResponse(ok: true)
        case .appWillQuit:
            lastHeartbeat = nil
            if !settings.keepLimitWhenAppClosed {
                log.info("Calma.app quit · Keep Limit After Quit is off, restoring stock charging")
                suspend(reason: "app quit")
            }
            return CalmaResponse(ok: true)
        default:
            // A direct command (CLI, Shortcuts) is an explicit request to be in control.
            if command != .emergencyReset { resumeIfSuspended("command from \(peer.userName)") }
            let response = perform(command, peerName: peer.userName)
            var withStatus = response
            withStatus.status = status()
            return withStatus
        }
    }

    private func perform(_ command: CalmaCommand, peerName: String) -> CalmaResponse {
        let battery = readBattery() ?? lastBattery ?? BatterySnapshot(percentage: 0, isPluggedIn: false, isCharging: false)
        if let problem = CommandValidator.validate(command, battery: battery, settings: settings, capabilities: capabilities) {
            return .failure(problem)
        }
        let now = Date()
        var message: String?

        switch command {
        case .status, .appHeartbeat, .appWillQuit:
            break
        case .updateSettings(var new):
            new.sanitize()
            settings = new
            message = "Settings saved"
        case .setChargeLimit(let limit):
            settings.chargeLimit = limit
            persisted.runtime.chargingLatch = true
            message = "Charge limit set to \(limit)%"
        case .setChargingPaused(let paused):
            settings.chargingPaused = paused
            message = paused ? "Charging paused" : "Charging resumed"
        case .startFullCharge:
            ChargeEngine.setMode(.fullCharge, runtime: &persisted.runtime, now: now)
            message = "Charging to 100% until you unplug"
        case .startDrain(let target):
            ChargeEngine.setMode(.drain(target: target), runtime: &persisted.runtime, now: now)
            message = "Draining to \(target)%"
        case .startRecalibration:
            ChargeEngine.setMode(.recalibrate(.chargeToFull), runtime: &persisted.runtime, now: now)
            message = "Recalibration started"
        case .cancelMode:
            ChargeEngine.setMode(.normal, runtime: &persisted.runtime, now: now)
            message = "Back to your charge limit"
        case .emergencyReset:
            ChargeEngine.setMode(.normal, runtime: &persisted.runtime, now: now)
            persisted.runtime.heatGuard = .idle
            settings.chargeLimit = 100
            settings.chargingPaused = false
            settings.autoDrain = false
            settings.magSafeLED = .system
            restoreStock(reason: "emergency reset by \(peerName)")
            log.warn("Emergency reset by \(peerName)")
            message = "All charging controls restored to macOS defaults"
        case .setLowPowerMode(let on):
            return runPmset(["-a", "lowpowermode", on ? "1" : "0"], success: on ? "Low Power Mode on" : "Low Power Mode off")
        case .setHighPowerMode(let on):
            return runPmset(["-a", "powermode", on ? "2" : "0"], success: on ? "High Power Mode on" : "High Power Mode off")
        }

        persisted.lastChangedBy = peerName
        save()
        log.info("\(peerName): \(message ?? "\(command)")")
        tick(reason: "command")
        return CalmaResponse(ok: true, message: message)
    }

    private func runPmset(_ arguments: [String], success: String) -> CalmaResponse {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure("pmset couldn't run: \(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return .failure("pmset failed — this Mac may not support that mode. \(detail)".trimmingCharacters(in: .whitespacesAndNewlines))
        }
        log.info(success)
        return CalmaResponse(ok: true, message: success)
    }

    // MARK: Status & persistence

    func status() -> CalmaStatus {
        let battery = lastBattery ?? readBattery() ?? BatterySnapshot(percentage: 0, isPluggedIn: false, isCharging: false)
        let level = battery.effectivePercentage(useHardware: settings.useHardwarePercentage)
        var state = lastDecision.state
        if !battery.isPluggedIn { state = .onBattery }
        var summary = ChargeEngine.summary(state: state, level: level, settings: settings, runtime: persisted.runtime,
                                           battery: battery, caps: capabilities)
        if suspended {
            summary = "Paused — macOS is managing charging"
        }
        return CalmaStatus(battery: battery, settings: settings, runtime: persisted.runtime, state: state,
                           capabilities: capabilities, summary: summary, lastChangedBy: persisted.lastChangedBy,
                           daemonVersion: CalmaVersion.current, taskHistory: persisted.history)
    }

    private func save() {
        Self.store(settings, to: CalmaPaths.settingsFile)
        Self.store(persisted, to: CalmaPaths.runtimeFile)
    }

    private static func load<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? CalmaJSON.decoder().decode(type, from: data)
    }

    private static func store<T: Encodable>(_ value: T, to path: String) {
        let encoder = CalmaJSON.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

extension ScheduledAction {
    var command: CalmaCommand {
        switch self {
        case .setChargeLimit(let value): return .setChargeLimit(value)
        case .fullCharge: return .startFullCharge
        case .recalibrate: return .startRecalibration
        case .pauseCharging(let paused): return .setChargingPaused(paused)
        case .drainTo(let value): return .startDrain(target: value)
        }
    }
}
