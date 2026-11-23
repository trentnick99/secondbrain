import Foundation

/// Calendar arithmetic helpers. Everything is relative to an injected `Calendar`
/// so behaviour is deterministic in tests and correct across time zones.
public struct DateMath: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// The first instant of the following day (exclusive upper bound for "this day").
    public func startOfNextDay(_ date: Date) -> Date { addingDays(1, to: startOfDay(date)) }

    public func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days * 86_400))
    }

    public func addingMinutes(_ minutes: Int, to date: Date) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: date) ?? date.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public func addingMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// Whole calendar days from `a` to `b` (positive when b is later).
    public func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day ?? 0
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    public func weekday(_ date: Date) -> Int { calendar.component(.weekday, from: date) }

    /// Start of the week containing `date`, with weeks beginning on `firstWeekday` (1 = Sunday … 7 = Saturday).
    public func startOfWeek(containing date: Date, firstWeekday: Int) -> Date {
        let day = startOfDay(date)
        let offset = (weekday(day) - firstWeekday + 7) % 7
        return addingDays(-offset, to: day)
    }

    public func weekDays(containing date: Date, firstWeekday: Int) -> [Date] {
        let start = startOfWeek(containing: date, firstWeekday: firstWeekday)
        return (0..<7).map { addingDays($0, to: start) }
    }

    /// `minutes` after midnight on the given day.
    public func date(on day: Date, minutes: Int) -> Date {
        let start = startOfDay(day)
        let hour = max(0, min(23, minutes / 60))
        let minute = max(0, min(59, minutes % 60))
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? addingMinutes(minutes, to: start)
    }

    public func minutesSinceMidnight(_ date: Date) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// The next date (on or after / strictly after `from`) that falls on `weekday`.
    public func nextDate(onWeekday target: Int, from date: Date, includingToday: Bool) -> Date {
        let day = startOfDay(date)
        var offset = (target - weekday(day) + 7) % 7
        if offset == 0 && !includingToday { offset = 7 }
        return addingDays(offset, to: day)
    }

    public func lastDayOfMonth(containing date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let firstOfMonth = calendar.date(from: comps),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) else { return startOfDay(date) }
        return addingDays(-1, to: nextMonth)
    }

    public func firstDayOfNextMonth(after date: Date) -> Date {
        addingDays(1, to: lastDayOfMonth(containing: date))
    }

    public func daysInMonth(of date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// Builds a date from components, returning nil for invalid dates (e.g. Feb 30).
    public func makeDate(year: Int, month: Int, day: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = calendar.date(from: comps) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
