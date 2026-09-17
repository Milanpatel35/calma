import CalmaKit
import XCTest

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    private func task(_ rule: RepeatRule, start: String, runIfMissed: Bool = true, lastRun: Date? = nil) -> ScheduledTask {
        ScheduledTask(name: "t", action: .setChargeLimit(80), repeatRule: rule, startDate: date(start),
                      runIfMissed: runIfMissed, lastRun: lastRun)
    }

    func testOnceFiresOnlyInFuture() {
        let t = task(.once, start: "2026-09-20T08:00:00Z")
        XCTAssertEqual(ScheduleCalculator.nextFire(for: t, after: date("2026-09-19T00:00:00Z"), calendar: calendar), date("2026-09-20T08:00:00Z"))
        XCTAssertNil(ScheduleCalculator.nextFire(for: t, after: date("2026-09-21T00:00:00Z"), calendar: calendar))
    }

    func testDaily() {
        let t = task(.daily, start: "2026-09-01T22:00:00Z")
        XCTAssertEqual(ScheduleCalculator.nextFire(for: t, after: date("2026-09-17T23:00:00Z"), calendar: calendar), date("2026-09-18T22:00:00Z"))
        XCTAssertEqual(ScheduleCalculator.nextFire(for: t, after: date("2026-09-17T21:00:00Z"), calendar: calendar), date("2026-09-17T22:00:00Z"))
    }

    func testWeekdaysSkipWeekend() {
        // 2026-09-18 is a Friday.
        let t = task(.weekdays, start: "2026-09-14T07:00:00Z")
        XCTAssertEqual(ScheduleCalculator.nextFire(for: t, after: date("2026-09-18T08:00:00Z"), calendar: calendar), date("2026-09-21T07:00:00Z"))
    }

    func testWeeklyBiweeklyMonthly() {
        let weekly = task(.weekly, start: "2026-09-01T10:00:00Z")
        XCTAssertEqual(ScheduleCalculator.nextFire(for: weekly, after: date("2026-09-02T00:00:00Z"), calendar: calendar), date("2026-09-08T10:00:00Z"))
        let biweekly = task(.biweekly, start: "2026-09-01T10:00:00Z")
        XCTAssertEqual(ScheduleCalculator.nextFire(for: biweekly, after: date("2026-09-02T00:00:00Z"), calendar: calendar), date("2026-09-15T10:00:00Z"))
        let monthly = task(.monthly, start: "2026-01-31T10:00:00Z")
        XCTAssertEqual(ScheduleCalculator.nextFire(for: monthly, after: date("2026-03-01T00:00:00Z"), calendar: calendar), date("2026-03-31T10:00:00Z"))
    }

    func testDueOccurrenceCollapsesMissedRuns() {
        // Daily task, last ran three days ago: only the most recent occurrence is due.
        let t = task(.daily, start: "2026-09-01T09:00:00Z", lastRun: date("2026-09-14T09:00:00Z"))
        let due = ScheduleCalculator.dueOccurrence(for: t, now: date("2026-09-17T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(due, date("2026-09-17T09:00:00Z"))
        XCTAssertTrue(ScheduleCalculator.shouldRun(t, occurrence: due!, now: date("2026-09-17T12:00:00Z")))

        let strict = task(.daily, start: "2026-09-01T09:00:00Z", runIfMissed: false, lastRun: date("2026-09-14T09:00:00Z"))
        XCTAssertFalse(ScheduleCalculator.shouldRun(strict, occurrence: due!, now: date("2026-09-17T12:00:00Z")))
        XCTAssertTrue(ScheduleCalculator.shouldRun(strict, occurrence: due!, now: date("2026-09-17T09:01:00Z")))
    }

    func testNothingDueAfterRunning() {
        let t = task(.daily, start: "2026-09-01T09:00:00Z", lastRun: date("2026-09-17T09:00:00Z"))
        XCTAssertNil(ScheduleCalculator.dueOccurrence(for: t, now: date("2026-09-17T12:00:00Z"), calendar: calendar))
    }
}

final class ValidationTests: XCTestCase {
    private let modern = Capabilities(backend: .appleSiliconModern, canInhibitCharging: true, canDrain: true, hasMagSafeLED: false)

    private func battery(_ level: Int, temperature: Double? = 30, plugged: Bool = true) -> BatterySnapshot {
        BatterySnapshot(percentage: level, isPluggedIn: plugged, isCharging: false, temperature: temperature)
    }

    func testLimitRange() {
        XCTAssertNotNil(CommandValidator.validate(.setChargeLimit(10), battery: battery(50), settings: CalmaSettings(), capabilities: modern))
        XCTAssertNil(CommandValidator.validate(.setChargeLimit(20), battery: battery(50), settings: CalmaSettings(), capabilities: modern))
        XCTAssertNotNil(CommandValidator.validate(.setChargeLimit(101), battery: battery(50), settings: CalmaSettings(), capabilities: modern))
    }

    func testDrainSafetyRules() {
        let settings = CalmaSettings()
        XCTAssertNotNil(CommandValidator.validate(.startDrain(target: 20), battery: battery(19), settings: settings, capabilities: modern), "Below 20%")
        // swiftlint:disable:next line_length
        XCTAssertNotNil(CommandValidator.validate(.startDrain(target: 40), battery: battery(80, temperature: nil), settings: settings, capabilities: modern), "No temperature")
        // swiftlint:disable:next line_length
        XCTAssertNotNil(CommandValidator.validate(.startDrain(target: 80), battery: battery(70), settings: settings, capabilities: modern), "Already below target")
        XCTAssertNil(CommandValidator.validate(.startDrain(target: 60), battery: battery(80), settings: settings, capabilities: modern))
    }

    func testUnsupportedHardwareRefusesWrites() {
        XCTAssertNotNil(CommandValidator.validate(.setChargeLimit(80), battery: battery(50), settings: CalmaSettings(), capabilities: .none))
        XCTAssertNotNil(CommandValidator.validate(.startRecalibration, battery: battery(50), settings: CalmaSettings(), capabilities: .none))
        XCTAssertNil(CommandValidator.validate(.emergencyReset, battery: battery(50), settings: CalmaSettings(), capabilities: .none))
    }

    func testMagSafeSettingNeedsHardware() {
        var settings = CalmaSettings()
        settings.magSafeLED = .status
        XCTAssertNotNil(CommandValidator.validate(.updateSettings(settings), battery: battery(50), settings: CalmaSettings(), capabilities: modern))
    }

    func testOnlyReadCommandsSkipAdmin() {
        XCTAssertFalse(CalmaCommand.status.requiresAdmin)
        XCTAssertFalse(CalmaCommand.appHeartbeat.requiresAdmin)
        XCTAssertTrue(CalmaCommand.setChargeLimit(80).requiresAdmin)
        XCTAssertTrue(CalmaCommand.emergencyReset.requiresAdmin)
    }

    func testSettingsDecodeWithMissingFields() throws {
        let json = Data(#"{"chargeLimit": 65}"#.utf8)
        let settings = try CalmaJSON.decoder().decode(CalmaSettings.self, from: json)
        XCTAssertEqual(settings.chargeLimit, 65)
        XCTAssertEqual(settings.driftRange, 5)
        XCTAssertFalse(settings.keepLimitWhenAppClosed)
    }

    func testCommandRoundTrip() throws {
        let commands: [CalmaCommand] = [.status, .setChargeLimit(70), .startDrain(target: 55), .updateSettings(CalmaSettings()), .setLowPowerMode(true)]
        for command in commands {
            let data = try CalmaJSON.encoder().encode(command)
            XCTAssertEqual(try CalmaJSON.decoder().decode(CalmaCommand.self, from: data), command)
        }
    }

    func testSanitizeClampsValues() {
        var settings = CalmaSettings()
        settings.chargeLimit = 5
        settings.driftRange = 90
        settings.heatGuardThreshold = 90
        settings.sanitize()
        XCTAssertEqual(settings.chargeLimit, 20)
        XCTAssertEqual(settings.driftRange, 20)
        XCTAssertEqual(settings.heatGuardThreshold, 50)
    }
}
