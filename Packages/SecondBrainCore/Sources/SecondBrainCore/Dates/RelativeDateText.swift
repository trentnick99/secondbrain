import Foundation

/// Human-friendly, compact date labels for lists, widgets, Siri dialogs and notifications.
public enum RelativeDateText {
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale ?? Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }

    public static func timeText(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale ?? Locale(identifier: "en_US")
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// "Today", "Tomorrow", "Yesterday", "Thursday" (within the next 6 days), otherwise "Dec 4".
    public static func dayLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let math = DateMath(calendar: calendar)
        let delta = math.daysBetween(now, date)
        switch delta {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return formatter("EEEE", calendar: calendar).string(from: date)
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return formatter(sameYear ? "MMMd" : "MMMdyyyy", calendar: calendar).string(from: date)
        }
    }

    /// Short weekday + day number, e.g. "Thu 4".
    public static func shortDay(_ date: Date, calendar: Calendar) -> String {
        formatter("EEEd", calendar: calendar).string(from: date)
    }

    public static func weekdayShort(_ date: Date, calendar: Calendar) -> String {
        formatter("EEE", calendar: calendar).string(from: date)
    }

    public static func mediumDate(_ date: Date, calendar: Calendar) -> String {
        formatter("EEEMMMd", calendar: calendar).string(from: date)
    }

    /// Due label used on task rows: "Today 3:00 PM", "Tomorrow", "Overdue · Mon", "Dec 4".
    public static func dueText(due: Date, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        let math = DateMath(calendar: calendar)
        let overdue = hasTime ? due < now : math.startOfDay(due) < math.startOfDay(now)
        let day = dayLabel(for: due, now: now, calendar: calendar)
        if overdue {
            if hasTime && math.isSameDay(due, now) { return "Overdue · \(timeText(due, calendar: calendar))" }
            return "Overdue · \(day)"
        }
        return hasTime ? "\(day) \(timeText(due, calendar: calendar))" : day
    }

    public static func minutesText(_ minutes: Int, calendar: Calendar) -> String {
        let math = DateMath(calendar: calendar)
        return timeText(math.date(on: Date(timeIntervalSince1970: 1_700_000_000), minutes: minutes), calendar: calendar)
    }
}
