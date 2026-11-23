import Foundation

/// A recurrence definition evaluated at day granularity. Time of day is stored separately
/// on the recurring series so that "every Monday at 7:00 AM" stays stable across DST.
public struct RecurrenceRule: Codable, Hashable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Identifiable, Sendable {
        case daily, weekly, monthly
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            }
        }
    }

    public var frequency: Frequency
    /// Every N days / weeks / months (minimum 1).
    public var interval: Int
    /// Weekday numbers (1 = Sunday … 7 = Saturday). Used by weekly rules; empty = the anchor's weekday.
    public var weekdays: [Int]
    /// Day of month for monthly rules; nil = the anchor's day. Clamped to short months.
    public var dayOfMonth: Int?
    /// Optional last day (inclusive).
    public var endDate: Date?

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = [], dayOfMonth: Int? = nil, endDate: Date? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        self.dayOfMonth = dayOfMonth.map { max(1, min(31, $0)) }
        self.endDate = endDate
    }

    public static var daily: RecurrenceRule { RecurrenceRule(frequency: .daily) }
    public static var weekdaysOnly: RecurrenceRule { RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6]) }
    public static func weekly(on weekdays: [Int], interval: Int = 1) -> RecurrenceRule {
        RecurrenceRule(frequency: .weekly, interval: interval, weekdays: weekdays)
    }
    public static func monthly(day: Int?, interval: Int = 1) -> RecurrenceRule {
        RecurrenceRule(frequency: .monthly, interval: interval, dayOfMonth: day)
    }

    // MARK: Evaluation

    /// Whether `day` is an occurrence for a series anchored (first eligible) on `anchor`.
    public func isOccurrence(_ day: Date, anchor: Date, calendar: Calendar) -> Bool {
        let math = DateMath(calendar: calendar)
        let d = math.startOfDay(day)
        let a = math.startOfDay(anchor)
        guard d >= a else { return false }
        if let end = endDate, d > math.startOfDay(end) { return false }

        switch frequency {
        case .daily:
            return math.daysBetween(a, d) % interval == 0
        case .weekly:
            let set = weekdays.isEmpty ? [math.weekday(a)] : weekdays
            guard set.contains(math.weekday(d)) else { return false }
            let first = calendar.firstWeekday
            let weeks = math.daysBetween(math.startOfWeek(containing: a, firstWeekday: first),
                                         math.startOfWeek(containing: d, firstWeekday: first)) / 7
            return weeks % interval == 0
        case .monthly:
            let ac = calendar.dateComponents([.year, .month, .day], from: a)
            let dc = calendar.dateComponents([.year, .month, .day], from: d)
            guard let ay = ac.year, let am = ac.month, let dy = dc.year, let dm = dc.month, let dd = dc.day else { return false }
            let months = (dy * 12 + dm) - (ay * 12 + am)
            guard months >= 0, months % interval == 0 else { return false }
            let target = dayOfMonth ?? (ac.day ?? 1)
            let clamped = min(target, math.daysInMonth(of: d))
            return dd == clamped
        }
    }

    /// The first occurrence strictly after `date` (day granularity), or nil if the rule has ended.
    public func nextOccurrence(after date: Date, anchor: Date, calendar: Calendar) -> Date? {
        let math = DateMath(calendar: calendar)
        var candidate = math.addingDays(1, to: math.startOfDay(date))
        let a = math.startOfDay(anchor)
        if candidate < a { candidate = a }
        let limit = 400 * interval + 31
        for _ in 0..<limit {
            if let end = endDate, candidate > math.startOfDay(end) { return nil }
            if isOccurrence(candidate, anchor: anchor, calendar: calendar) { return candidate }
            candidate = math.addingDays(1, to: candidate)
        }
        return nil
    }

    /// The first occurrence on or after `date`.
    public func firstOccurrence(onOrAfter date: Date, anchor: Date, calendar: Calendar) -> Date? {
        let math = DateMath(calendar: calendar)
        let day = math.startOfDay(date)
        if isOccurrence(day, anchor: anchor, calendar: calendar) { return day }
        return nextOccurrence(after: day, anchor: anchor, calendar: calendar)
    }

    /// All occurrences in [from, to] (inclusive, day granularity).
    public func occurrences(from: Date, to: Date, anchor: Date, calendar: Calendar) -> [Date] {
        let math = DateMath(calendar: calendar)
        var result: [Date] = []
        var day = math.startOfDay(from)
        let end = math.startOfDay(to)
        var guardCount = 0
        while day <= end && guardCount < 1000 {
            if isOccurrence(day, anchor: anchor, calendar: calendar) { result.append(day) }
            day = math.addingDays(1, to: day)
            guardCount += 1
        }
        return result
    }

    // MARK: Description

    public func summary(calendar: Calendar) -> String {
        let symbols = Self.weekdayNames(calendar: calendar, short: false)
        let shortSymbols = Self.weekdayNames(calendar: calendar, short: true)
        switch frequency {
        case .daily:
            return interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            if weekdays == [2, 3, 4, 5, 6] && interval == 1 { return "Every weekday" }
            if weekdays.isEmpty { return interval == 1 ? "Every week" : "Every \(interval) weeks" }
            let ordered = orderedWeekdays(calendar: calendar)
            if interval == 1 {
                if ordered.count == 1 { return "Every \(symbols[ordered[0] - 1])" }
                return "Every " + ordered.map { shortSymbols[$0 - 1] }.joined(separator: ", ")
            }
            return "Every \(interval) weeks on " + ordered.map { shortSymbols[$0 - 1] }.joined(separator: ", ")
        case .monthly:
            let dayText = dayOfMonth.map { "the \(Self.ordinal($0))" } ?? "the same day"
            return interval == 1 ? "Monthly on \(dayText)" : "Every \(interval) months on \(dayText)"
        }
    }

    private func orderedWeekdays(calendar: Calendar) -> [Int] {
        // Present Monday-first for readability, matching how shifts are usually discussed.
        weekdays.sorted { (($0 + 5) % 7) < (($1 + 5) % 7) }
    }

    static func weekdayNames(calendar: Calendar, short: Bool) -> [String] {
        let f = DateFormatter()
        f.locale = calendar.locale ?? Locale(identifier: "en_US")
        let names: [String]? = short ? f.shortWeekdaySymbols : f.weekdaySymbols
        if let names = names, names.count == 7 { return names }
        return short ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                     : ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }

    public static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10
        let ones = n % 10
        let suffix: String
        if tens == 1 { suffix = "th" } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
