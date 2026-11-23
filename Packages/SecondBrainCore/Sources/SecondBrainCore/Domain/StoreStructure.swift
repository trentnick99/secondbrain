import Foundation

// MARK: - Shifts

/// One shift, in minutes after midnight (same-day shifts: end > start).
public struct ShiftTime: Codable, Hashable, Sendable {
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = max(0, min(startMinutes, 23 * 60 + 59))
        self.endMinutes = max(self.startMinutes + 15, min(endMinutes, 23 * 60 + 59))
    }

    public init(startHour: Int, endHour: Int) {
        self.init(startMinutes: startHour * 60, endMinutes: endHour * 60)
    }

    /// The store's standard 10-hour coach shifts.
    public static let opening = ShiftTime(startHour: 7, endHour: 17)   // 7–5
    public static let mid = ShiftTime(startHour: 10, endHour: 20)      // 10–8
    public static let closing = ShiftTime(startHour: 12, endHour: 22)  // 12–10
    public static let presets: [ShiftTime] = [.opening, .mid, .closing]

    /// "7–5", "10–8", "12–10", or "6:30–4:30".
    public var shortLabel: String {
        "\(Self.compact(startMinutes))–\(Self.compact(endMinutes))"
    }

    public var lengthMinutes: Int { endMinutes - startMinutes }

    static func compact(_ minutes: Int) -> String {
        let h24 = minutes / 60, m = minutes % 60
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return m == 0 ? "\(h12)" : String(format: "%d:%02d", h12, m)
    }
}

/// The person's weekly schedule: a shift (or a day off) for each weekday.
/// Used for "end of shift", the daily briefing, default reminders and End My Shift carry-forward.
public struct ShiftSchedule: Codable, Hashable, Sendable {
    /// Index 0 = Sunday … 6 = Saturday. nil = day off.
    public var shifts: [ShiftTime?]

    public init(shifts: [ShiftTime?]) {
        var normalized = Array(shifts.prefix(7))
        while normalized.count < 7 { normalized.append(nil) }
        self.shifts = normalized
    }

    /// Every day 7–5 until the person sets their real schedule.
    public static let unset = ShiftSchedule(shifts: Array(repeating: ShiftTime.opening, count: 7))

    /// weekday: 1 = Sunday … 7 = Saturday (Calendar convention).
    public func shift(forWeekday weekday: Int) -> ShiftTime? {
        guard (1...7).contains(weekday) else { return nil }
        return shifts[weekday - 1]
    }

    public mutating func setShift(_ shift: ShiftTime?, forWeekday weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        shifts[weekday - 1] = shift
    }

    public func shift(on date: Date, calendar: Calendar) -> ShiftTime? {
        shift(forWeekday: calendar.component(.weekday, from: date))
    }

    public func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        shift(on: date, calendar: calendar) != nil
    }

    public var workdayCount: Int { shifts.compactMap { $0 }.count }

    /// The first scheduled workday strictly after `date` (start of day). Falls back to the next day
    /// when no workdays are set.
    public func nextWorkday(after date: Date, calendar: Calendar) -> Date {
        let math = DateMath(calendar: calendar)
        let start = math.startOfDay(date)
        for offset in 1...7 {
            let day = math.addingDays(offset, to: start)
            if isWorkday(day, calendar: calendar) { return day }
        }
        return math.addingDays(1, to: start)
    }

    /// Today if it's a workday, otherwise the next workday.
    public func currentOrNextWorkday(_ date: Date, calendar: Calendar) -> Date {
        let start = DateMath(calendar: calendar).startOfDay(date)
        return isWorkday(start, calendar: calendar) ? start : nextWorkday(after: start, calendar: calendar)
    }

    public func startMinutes(on date: Date, calendar: Calendar, fallback: Int) -> Int {
        shift(on: date, calendar: calendar)?.startMinutes ?? fallback
    }

    public func endMinutes(on date: Date, calendar: Calendar, fallback: Int) -> Int {
        shift(on: date, calendar: calendar)?.endMinutes ?? fallback
    }

    /// "Mon 7–5 · Tue 10–8 · Wed off …" starting from the given weekday.
    public func summary(calendar: Calendar, startingOn firstWeekday: Int = 1) -> String {
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { i -> String in
            let weekday = ((firstWeekday - 1 + i) % 7) + 1
            let label = shift(forWeekday: weekday)?.shortLabel ?? "off"
            return "\(symbols[weekday - 1]) \(label)"
        }.joined(separator: " · ")
    }
}

// MARK: - Store roles and areas

/// Where someone sits in the store's structure.
public enum StoreRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case storeManager, coach, teamLead, associate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .storeManager: return "Store Manager"
        case .coach: return "Coach"
        case .teamLead: return "Team Lead"
        case .associate: return "Associate"
        }
    }

    public var pluralTitle: String {
        switch self {
        case .storeManager: return "Store Manager"
        case .coach: return "Coaches"
        case .teamLead: return "Team Leads"
        case .associate: return "Associates"
        }
    }

    public var systemImage: String {
        switch self {
        case .storeManager: return "building.2.crop.circle"
        case .coach: return "person.crop.circle.badge.checkmark"
        case .teamLead: return "person.2.circle"
        case .associate: return "person.circle"
        }
    }

    public var sortIndex: Int {
        switch self {
        case .storeManager: return 0
        case .coach: return 1
        case .teamLead: return 2
        case .associate: return 3
        }
    }

    /// Reads a free-text role ("Fresh TL", "Cashier", "AP Coach") into a structural role.
    public static func infer(from text: String) -> StoreRole? {
        let lower = " " + text.lowercased() + " "
        if lower.contains("store manager") || lower.contains(" sm ") { return .storeManager }
        if lower.contains("team lead") || lower.contains(" tl ") || lower.contains(" tls ") { return .teamLead }
        if lower.contains("coach") { return .coach }
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return .associate
    }
}

/// The areas coaches run in the store, in the order shown in pickers.
public enum StoreAreas {
    public static let all: [String] = [
        "Stocking", "Overnight", "Fresh", "Food", "Fashion", "Front End",
        "Digital (OPD)", "Asset Protection", "Auto Care Center (ACC)"
    ]

    /// Common associate job titles, used as role suggestions.
    public static let associateTitles: [String] = [
        "Stocker", "Cashier", "Unloader", "Personal Shopper", "Dispenser", "Fresh Associate",
        "Fashion Associate", "Auto Care Tech", "AP Associate", "Customer Host"
    ]
}
