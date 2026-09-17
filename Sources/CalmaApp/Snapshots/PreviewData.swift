import CalmaKit
import Foundation

/// Realistic fixed data for screenshots. Never used at runtime outside `--render-screenshots`.
enum PreviewData {
    static func status(state: ChargeState = .paused) -> CalmaStatus {
        var settings = CalmaSettings()
        settings.chargeLimit = 80
        settings.driftRangeEnabled = true
        settings.driftRange = 5
        settings.heatGuardEnabled = true
        settings.heatGuardThreshold = 35
        settings.pauseChargingOnSleep = true
        settings.keepLimitWhenAppClosed = true
        settings.magSafeLED = .status

        let calendar = Calendar.current
        let friday = calendar.nextDate(after: Date(), matching: DateComponents(hour: 18, minute: 0, weekday: 6),
                                       matchingPolicy: .nextTime) ?? Date()
        let sunday = calendar.nextDate(after: Date(), matching: DateComponents(hour: 21, minute: 0, weekday: 1),
                                       matchingPolicy: .nextTime) ?? Date()
        let monthly = calendar.date(byAdding: .day, value: 12, to: calendar.startOfDay(for: Date())) ?? Date()
            .addingTimeInterval(9 * 3600)
        settings.schedule = [
            ScheduledTask(name: "Weekend trip", action: .setChargeLimit(100), repeatRule: .weekly, startDate: friday),
            ScheduledTask(name: "Back to desk mode", action: .setChargeLimit(80), repeatRule: .weekly, startDate: sunday),
            ScheduledTask(name: "Monthly recalibration", action: .recalibrate, repeatRule: .monthly, startDate: monthly,
                          enabled: false),
        ]

        let battery = BatterySnapshot(
            percentage: 78, hardwarePercentage: 77, isPluggedIn: true, isCharging: false,
            temperature: 31.2, cycleCount: 312, designCapacity: 6249, fullChargeCapacity: 5874,
            voltage: 12_480, amperage: 0, adapterWatts: 96, systemPowerIn: 14.6, systemLoad: 14.6
        )

        let now = Date()
        let history = [
            TaskHistoryEntry(taskName: "Back to desk mode", date: now.addingTimeInterval(-3 * 86_400 + 3_600), result: "Charge limit set to 80%"),
            TaskHistoryEntry(taskName: "Weekend trip", date: now.addingTimeInterval(-5 * 86_400), result: "Charge limit set to 100%"),
        ]

        var runtime = RuntimeState()
        runtime.wasPluggedIn = true
        runtime.chargingLatch = false

        let caps = Capabilities(backend: .appleSiliconModern, canInhibitCharging: true, canDrain: true,
                                hasMagSafeLED: true, modelIdentifier: "Mac15,6", osVersion: "15.6")
        let summary = ChargeEngine.summary(state: state, level: 78, settings: settings, runtime: runtime,
                                           battery: battery, caps: caps)
        return CalmaStatus(battery: battery, settings: settings, runtime: runtime, state: state, capabilities: caps,
                           summary: summary, lastChangedBy: NSUserName(), daemonVersion: CalmaVersion.current,
                           taskHistory: history)
    }

    /// Same Mac, but charging from a busy adapter — makes the Power Flow diagram more interesting.
    static func chargingStatus() -> CalmaStatus {
        var status = status(state: .charging)
        status.battery.percentage = 64
        status.battery.hardwarePercentage = 63
        status.battery.isCharging = true
        status.battery.amperage = 2_150
        status.battery.voltage = 12_310
        status.battery.systemPowerIn = 48.2
        status.battery.systemLoad = 21.7
        status.runtime.chargingLatch = true
        status.summary = ChargeEngine.summary(state: .charging, level: 64, settings: status.settings,
                                              runtime: status.runtime, battery: status.battery, caps: status.capabilities)
        return status
    }
}
