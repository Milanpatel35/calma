import CalmaKit
import XCTest

final class ChargeEngineTests: XCTestCase {
    private let modern = Capabilities(backend: .appleSiliconModern, canInhibitCharging: true, canDrain: true, hasMagSafeLED: true)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func battery(_ level: Int, plugged: Bool = true, temperature: Double? = 30) -> BatterySnapshot {
        BatterySnapshot(percentage: level, hardwarePercentage: level - 3, isPluggedIn: plugged, isCharging: false,
                        temperature: temperature, adapterWatts: 96)
    }

    private func evaluate(_ settings: CalmaSettings, _ battery: BatterySnapshot, _ runtime: inout RuntimeState,
                          caps: Capabilities? = nil, at date: Date? = nil) -> ChargeDecision {
        ChargeEngine.evaluate(EngineInput(settings: settings, battery: battery, capabilities: caps ?? modern, now: date ?? t0),
                              runtime: &runtime)
    }

    // MARK: Charge limit

    func testChargesBelowLimitAndStopsAtLimit() {
        var settings = CalmaSettings()
        settings.chargeLimit = 80
        var runtime = RuntimeState()

        let below = evaluate(settings, battery(70), &runtime)
        XCTAssertTrue(below.chargingAllowed)
        XCTAssertTrue(below.adapterEnabled)
        XCTAssertEqual(below.state, .charging)

        let at = evaluate(settings, battery(80), &runtime)
        XCTAssertFalse(at.chargingAllowed)
        XCTAssertTrue(at.adapterEnabled, "Holding at the limit runs the Mac from the adapter")
        XCTAssertEqual(at.state, .paused)

        let justBelow = evaluate(settings, battery(79), &runtime)
        XCTAssertTrue(justBelow.chargingAllowed, "Without Drift Range, charging resumes as soon as the level drops")
    }

    func testLimitOf100IsStockBehaviour() {
        var settings = CalmaSettings()
        settings.chargeLimit = 100
        var runtime = RuntimeState()
        let decision = evaluate(settings, battery(100), &runtime)
        XCTAssertTrue(decision.chargingAllowed)
        XCTAssertTrue(decision.adapterEnabled)
    }

    func testPauseChargingOverridesLimit() {
        var settings = CalmaSettings()
        settings.chargingPaused = true
        var runtime = RuntimeState()
        XCTAssertFalse(evaluate(settings, battery(30), &runtime).chargingAllowed)
    }

    func testTruePercentageIsUsedWhenEnabled() {
        var settings = CalmaSettings()
        settings.chargeLimit = 80
        settings.useHardwarePercentage = true
        var runtime = RuntimeState()
        // macOS says 81 but the controller says 78: keep charging.
        XCTAssertTrue(evaluate(settings, battery(81), &runtime).chargingAllowed)
    }

    // MARK: Drift Range

    func testDriftRangeWaitsForLowerThreshold() {
        var settings = CalmaSettings()
        settings.chargeLimit = 80
        settings.driftRangeEnabled = true
        settings.driftRange = 5
        var runtime = RuntimeState()

        XCTAssertFalse(evaluate(settings, battery(80), &runtime).chargingAllowed)
        XCTAssertFalse(evaluate(settings, battery(78), &runtime).chargingAllowed, "Inside the drift band")
        XCTAssertFalse(evaluate(settings, battery(75), &runtime).chargingAllowed, "At the band's floor")
        XCTAssertTrue(evaluate(settings, battery(74), &runtime).chargingAllowed, "Below the band: charge")
        XCTAssertTrue(evaluate(settings, battery(77), &runtime).chargingAllowed, "Keeps charging back up through the band")
        XCTAssertFalse(evaluate(settings, battery(80), &runtime).chargingAllowed)
    }

    // MARK: Draining

    func testAutoDrainDrainsDownToLimit() {
        var settings = CalmaSettings()
        settings.chargeLimit = 60
        settings.autoDrain = true
        var runtime = RuntimeState()

        let over = evaluate(settings, battery(75), &runtime)
        XCTAssertFalse(over.adapterEnabled)
        XCTAssertFalse(over.chargingAllowed)
        XCTAssertEqual(over.state, .draining)
        XCTAssertTrue(over.preventSleep, "Draining holds a sleep assertion")

        let reached = evaluate(settings, battery(60), &runtime)
        XCTAssertTrue(reached.adapterEnabled)
        XCTAssertFalse(reached.chargingAllowed)
    }

    func testManualDrainStopsAtTarget() {
        let settings = CalmaSettings()
        var runtime = RuntimeState()
        ChargeEngine.setMode(.drain(target: 50), runtime: &runtime, now: t0)

        XCTAssertFalse(evaluate(settings, battery(70), &runtime).adapterEnabled)
        let done = evaluate(settings, battery(50), &runtime)
        XCTAssertTrue(done.adapterEnabled)
        XCTAssertEqual(runtime.mode, .normal)
        XCTAssertFalse(done.events.isEmpty)
    }

    func testAdapterIsAlwaysEnabledWhenUnplugged() {
        let settings = CalmaSettings()
        var runtime = RuntimeState()
        ChargeEngine.setMode(.drain(target: 40), runtime: &runtime, now: t0)
        let decision = evaluate(settings, battery(70, plugged: false), &runtime)
        XCTAssertTrue(decision.adapterEnabled)
        XCTAssertEqual(decision.state, .onBattery)
    }

    // MARK: Full Charge

    func testFullChargeChargesPastLimitAndEndsOnUnplug() {
        var settings = CalmaSettings()
        settings.chargeLimit = 70
        var runtime = RuntimeState()
        ChargeEngine.setMode(.fullCharge, runtime: &runtime, now: t0)

        XCTAssertTrue(evaluate(settings, battery(90), &runtime).chargingAllowed)
        XCTAssertEqual(runtime.mode, .fullCharge)

        _ = evaluate(settings, battery(95, plugged: false), &runtime)
        XCTAssertEqual(runtime.mode, .normal)
        XCTAssertFalse(evaluate(settings, battery(95), &runtime).chargingAllowed)
    }

    // MARK: Recalibrate

    func testRecalibrationWalksThroughAllStages() {
        var settings = CalmaSettings()
        settings.chargeLimit = 80
        settings.heatGuardEnabled = true
        settings.heatGuardThreshold = 30
        var runtime = RuntimeState()
        ChargeEngine.setMode(.recalibrate(.chargeToFull), runtime: &runtime, now: t0)

        let charging = evaluate(settings, battery(90, temperature: 40), &runtime)
        XCTAssertTrue(charging.chargingAllowed, "Heat Guard is suspended during recalibration")
        XCTAssertEqual(runtime.mode, .recalibrate(.chargeToFull))

        let draining = evaluate(settings, battery(100), &runtime)
        XCTAssertEqual(runtime.mode, .recalibrate(.drainToLow))
        XCTAssertFalse(draining.adapterEnabled)

        _ = evaluate(settings, battery(10), &runtime)
        XCTAssertEqual(runtime.mode, .recalibrate(.rechargeToFull))

        _ = evaluate(settings, battery(100), &runtime, at: t0.addingTimeInterval(100))
        XCTAssertEqual(runtime.mode, .recalibrate(.holdAtFull))

        _ = evaluate(settings, battery(100), &runtime, at: t0.addingTimeInterval(100 + 1800))
        XCTAssertEqual(runtime.mode, .recalibrate(.holdAtFull))

        let finished = evaluate(settings, battery(100), &runtime, at: t0.addingTimeInterval(100 + 3600))
        XCTAssertEqual(runtime.mode, .normal)
        XCTAssertFalse(finished.chargingAllowed, "Back to the 80% limit")
    }

    // MARK: Heat Guard

    func testHeatGuardHysteresis() {
        var settings = CalmaSettings()
        settings.chargeLimit = 90
        settings.heatGuardEnabled = true
        settings.heatGuardThreshold = 35
        var runtime = RuntimeState()

        let hot = evaluate(settings, battery(50, temperature: 36), &runtime, at: t0)
        XCTAssertFalse(hot.chargingAllowed)
        XCTAssertEqual(hot.state, .heatPaused)

        // Cooled, but the 5-minute pause hasn't elapsed.
        XCTAssertFalse(evaluate(settings, battery(50, temperature: 30), &runtime, at: t0.addingTimeInterval(120)).chargingAllowed)

        // After 5 minutes, still hot: another pause.
        XCTAssertFalse(evaluate(settings, battery(50, temperature: 36), &runtime, at: t0.addingTimeInterval(301)).chargingAllowed)

        // After the second pause, cool: resume for a guaranteed window, even if it heats up again.
        XCTAssertTrue(evaluate(settings, battery(50, temperature: 34), &runtime, at: t0.addingTimeInterval(602)).chargingAllowed)
        XCTAssertTrue(evaluate(settings, battery(50, temperature: 37), &runtime, at: t0.addingTimeInterval(700)).chargingAllowed)

        // Window over: guard re-arms and trips on the next hot reading.
        _ = evaluate(settings, battery(50, temperature: 37), &runtime, at: t0.addingTimeInterval(903))
        XCTAssertFalse(evaluate(settings, battery(50, temperature: 37), &runtime, at: t0.addingTimeInterval(910)).chargingAllowed)
    }

    func testHeatGuardIgnoresUnknownTemperatureWhenIdle() {
        var settings = CalmaSettings()
        settings.heatGuardEnabled = true
        var runtime = RuntimeState()
        XCTAssertTrue(evaluate(settings, battery(50, temperature: nil), &runtime).chargingAllowed)
    }

    // MARK: Capabilities

    func testUnsupportedHardwareNeverRestrictsCharging() {
        var settings = CalmaSettings()
        settings.chargeLimit = 50
        settings.autoDrain = true
        var runtime = RuntimeState()
        let decision = evaluate(settings, battery(90), &runtime, caps: Capabilities.none)
        XCTAssertTrue(decision.chargingAllowed)
        XCTAssertTrue(decision.adapterEnabled)
    }

    func testDrainModesCancelledWithoutDrainSupport() {
        let caps = Capabilities(backend: .intel, canInhibitCharging: true, canDrain: false, hasMagSafeLED: false)
        var runtime = RuntimeState()
        ChargeEngine.setMode(.drain(target: 40), runtime: &runtime, now: t0)
        let decision = evaluate(CalmaSettings(), battery(70), &runtime, caps: caps)
        XCTAssertEqual(runtime.mode, .normal)
        XCTAssertTrue(decision.adapterEnabled)
    }

    // MARK: Sleep & LED

    func testStayAwakeUntilLimit() {
        var settings = CalmaSettings()
        settings.chargeLimit = 80
        settings.stayAwakeUntilLimit = true
        var runtime = RuntimeState()
        XCTAssertTrue(evaluate(settings, battery(60), &runtime).preventSleep)
        XCTAssertFalse(evaluate(settings, battery(80), &runtime).preventSleep)
        XCTAssertFalse(evaluate(settings, battery(60, plugged: false), &runtime).preventSleep)
    }

    func testMagSafeStatusLED() {
        var settings = CalmaSettings()
        settings.chargeLimit = 80
        settings.magSafeLED = .status
        settings.magSafeBlinkWhileDraining = true
        var runtime = RuntimeState()
        XCTAssertEqual(evaluate(settings, battery(60), &runtime).led, .amber)
        XCTAssertEqual(evaluate(settings, battery(80), &runtime).led, .green)
        ChargeEngine.setMode(.drain(target: 50), runtime: &runtime, now: t0)
        XCTAssertEqual(evaluate(settings, battery(70), &runtime).led, .amberBlink)

        let noLED = Capabilities(backend: .appleSiliconLegacy, canInhibitCharging: true, canDrain: true, hasMagSafeLED: false)
        XCTAssertEqual(evaluate(settings, battery(60), &runtime, caps: noLED).led, .system)
    }

    func testSummaryText() {
        var settings = CalmaSettings()
        settings.chargeLimit = 80
        let text = ChargeEngine.summary(state: .paused, level: 80, settings: settings, runtime: RuntimeState(),
                                        battery: battery(80), caps: modern)
        XCTAssertEqual(text, "Holding at 80% · Adapter 96 W")
    }
}
