import Foundation

/// Quick snooze choices offered in notifications, task rows and End My Shift.
public enum SnoozeOption: String, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case tomorrowMorning

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .tomorrowMorning: return "Tomorrow morning"
        }
    }

    public var systemImage: String {
        switch self {
        case .fifteenMinutes: return "15.circle"
        case .thirtyMinutes: return "30.circle"
        case .oneHour: return "clock"
        case .tomorrowMorning: return "sunrise"
        }
    }

    /// The new reminder time. "Tomorrow morning" uses the person's morning / shift-start time.
    public func date(from now: Date, morningMinutes: Int, calendar: Calendar) -> Date {
        let math = DateMath(calendar: calendar)
        switch self {
        case .fifteenMinutes: return math.addingMinutes(15, to: now)
        case .thirtyMinutes: return math.addingMinutes(30, to: now)
        case .oneHour: return math.addingMinutes(60, to: now)
        case .tomorrowMorning: return math.date(on: math.addingDays(1, to: now), minutes: morningMinutes)
        }
    }
}

/// The result of moving a task to another day.
public struct RescheduleResult: Equatable, Sendable {
    public var dueDate: Date
    public var hasDueTime: Bool
    public var reminderDate: Date?
    /// True when the task moved later than it was due (counts toward "repeatedly postponed").
    public var isPostponement: Bool
}

public enum Rescheduler {
    /// Moves a task to `day`, keeping its time of day and shifting any reminder by the same amount.
    /// Undated tasks get the default reminder time when one is configured and still ahead.
    public static func move(dueDate: Date?, hasDueTime: Bool, reminderDate: Date?, to day: Date,
                            now: Date, defaultReminderMinutes: Int?, calendar: Calendar) -> RescheduleResult {
        let math = DateMath(calendar: calendar)
        let targetDay = math.startOfDay(day)
        let newDue: Date
        if let due = dueDate, hasDueTime {
            newDue = math.date(on: targetDay, minutes: math.minutesSinceMidnight(due))
        } else {
            newDue = targetDay
        }

        var newReminder: Date?
        if let reminder = reminderDate {
            let reminderDay = math.startOfDay(reminder)
            let anchorDay = dueDate.map { math.startOfDay($0) } ?? reminderDay
            let dayOffset = math.daysBetween(anchorDay, reminderDay)
            let shiftedDay = math.addingDays(dayOffset, to: targetDay)
            newReminder = math.date(on: shiftedDay, minutes: math.minutesSinceMidnight(reminder))
        } else if hasDueTime {
            newReminder = nil
        } else if let minutes = defaultReminderMinutes, dueDate == nil {
            newReminder = math.date(on: targetDay, minutes: minutes)
        }
        if let r = newReminder, r <= now { newReminder = nil }

        let postponed: Bool
        if let due = dueDate { postponed = math.startOfDay(newDue) > math.startOfDay(due) } else { postponed = false }
        return RescheduleResult(dueDate: newDue, hasDueTime: hasDueTime && dueDate != nil, reminderDate: newReminder, isPostponement: postponed)
    }

    /// The default "carry forward" target from End My Shift: the next scheduled workday
    /// (or simply the next day when no schedule is set).
    public static func carryForwardDay(now: Date, calendar: Calendar, schedule: ShiftSchedule? = nil) -> Date {
        if let schedule { return schedule.nextWorkday(after: now, calendar: calendar) }
        let math = DateMath(calendar: calendar)
        return math.addingDays(1, to: math.startOfDay(now))
    }
}
