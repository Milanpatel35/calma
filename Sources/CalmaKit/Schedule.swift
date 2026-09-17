import Foundation

public struct ScheduledTask: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var action: ScheduledAction
    public var repeatRule: RepeatRule
    /// First (or only) time the task fires. Hour/minute are reused for repeating tasks.
    public var startDate: Date
    public var enabled: Bool
    /// Run once on wake/boot if the scheduled moment was missed while the Mac was asleep or off.
    public var runIfMissed: Bool
    public var lastRun: Date?

    public init(id: UUID = UUID(), name: String, action: ScheduledAction, repeatRule: RepeatRule,
                startDate: Date, enabled: Bool = true, runIfMissed: Bool = true, lastRun: Date? = nil) {
        self.id = id
        self.name = name
        self.action = action
        self.repeatRule = repeatRule
        self.startDate = startDate
        self.enabled = enabled
        self.runIfMissed = runIfMissed
        self.lastRun = lastRun
    }
}

public enum ScheduledAction: Codable, Equatable, Sendable {
    case setChargeLimit(Int)
    case fullCharge
    case recalibrate
    case pauseCharging(Bool)
    case drainTo(Int)

    public var title: String {
        switch self {
        case .setChargeLimit(let value): return "Set charge limit to \(value)%"
        case .fullCharge: return "Full charge once"
        case .recalibrate: return "Start recalibration"
        case .pauseCharging(let paused): return paused ? "Pause charging" : "Resume charging"
        case .drainTo(let value): return "Drain to \(value)%"
        }
    }
}

public enum RepeatRule: String, Codable, CaseIterable, Sendable {
    case once, daily, weekdays, weekly, biweekly, monthly

    public var title: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Every week"
        case .biweekly: return "Every two weeks"
        case .monthly: return "Every month"
        }
    }
}

public struct TaskHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var taskName: String
    public var date: Date
    public var result: String

    public init(id: UUID = UUID(), taskName: String, date: Date, result: String) {
        self.id = id
        self.taskName = taskName
        self.date = date
        self.result = result
    }
}

public enum ScheduleCalculator {
    /// The first fire date strictly after `after`, or nil if a one-off task has passed.
    public static func nextFire(for task: ScheduledTask, after: Date, calendar: Calendar = .current) -> Date? {
        let start = task.startDate
        if task.repeatRule == .once {
            return start > after ? start : nil
        }
        if start > after { return start }

        switch task.repeatRule {
        case .once:
            return nil
        case .daily:
            return step(from: start, after: after, calendar: calendar) { calendar.date(byAdding: .day, value: $0, to: start) }
        case .weekly:
            return step(from: start, after: after, calendar: calendar) { calendar.date(byAdding: .day, value: 7 * $0, to: start) }
        case .biweekly:
            return step(from: start, after: after, calendar: calendar) { calendar.date(byAdding: .day, value: 14 * $0, to: start) }
        case .monthly:
            return step(from: start, after: after, calendar: calendar) { calendar.date(byAdding: .month, value: $0, to: start) }
        case .weekdays:
            var candidate = step(from: start, after: after, calendar: calendar) { calendar.date(byAdding: .day, value: $0, to: start) }
            while let date = candidate, calendar.isDateInWeekend(date) {
                candidate = calendar.date(byAdding: .day, value: 1, to: date)
            }
            return candidate
        }
    }

    /// The most recent fire time at or before `now` that is later than `lastRun` (or the start date), if any.
    public static func dueOccurrence(for task: ScheduledTask, now: Date, calendar: Calendar = .current) -> Date? {
        guard task.enabled, task.startDate <= now else { return nil }
        let reference = task.lastRun ?? task.startDate.addingTimeInterval(-1)
        guard let next = nextFire(for: task, after: reference, calendar: calendar), next <= now else { return nil }
        // Walk forward to the latest missed occurrence so a long sleep only runs the task once.
        var latest = next
        while let following = nextFire(for: task, after: latest, calendar: calendar), following <= now {
            latest = following
        }
        return latest
    }

    /// Whether a due occurrence should run now: on time (within `grace`) or missed-but-allowed.
    public static func shouldRun(_ task: ScheduledTask, occurrence: Date, now: Date, grace: TimeInterval = 120) -> Bool {
        now.timeIntervalSince(occurrence) <= grace || task.runIfMissed
    }

    private static func step(from start: Date, after: Date, calendar: Calendar, advance: (Int) -> Date?) -> Date? {
        // Estimate the number of steps, then correct — avoids iterating thousands of times for old tasks.
        var n = 0
        if let one = advance(1) {
            let interval = one.timeIntervalSince(start)
            if interval > 0 {
                n = max(0, Int(after.timeIntervalSince(start) / interval) - 1)
            }
        }
        while let candidate = advance(n) {
            if candidate > after { return candidate }
            n += 1
        }
        return nil
    }
}
