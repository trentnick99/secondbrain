import Foundation

/// A date in the retail year worth planning for: a holiday, an announced sales event, a typical
/// seasonal set, or a safety/operations change such as the clocks moving.
public struct RetailMoment: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case holiday, salesEvent, seasonal, operations, safety, fiscal, store

        public var title: String {
            switch self {
            case .store: return "Your event"
            case .holiday: return "Holiday"
            case .salesEvent: return "Sales event"
            case .seasonal: return "Seasonal set"
            case .operations: return "Operations"
            case .safety: return "Safety"
            case .fiscal: return "Fiscal"
            }
        }

        public var systemImage: String {
            switch self {
            case .store: return "storefront"
            case .holiday: return "gift"
            case .salesEvent: return "tag"
            case .seasonal: return "leaf.arrow.triangle.circlepath"
            case .operations: return "clock.arrow.2.circlepath"
            case .safety: return "exclamationmark.shield"
            case .fiscal: return "calendar"
            }
        }
    }

    /// How sure the date is, shown next to every item so nothing reads as more official than it is.
    public enum Certainty: String, Sendable {
        /// Fixed by the calendar (Thanksgiving, the clocks changing, the fiscal-week rule).
        case calendar
        /// Dates the company announced publicly.
        case announced
        /// Usual timing only — confirm with your store's modular, feature or company calendar.
        case typical
        /// An event the person added for their store.
        case yours

        public var label: String {
            switch self {
            case .yours: return "Added by you"
            case .calendar: return "Calendar date"
            case .announced: return "Announced"
            case .typical: return "Typical timing — confirm locally"
            }
        }
    }

    public let key: String
    public let title: String
    public let start: Date
    public let end: Date?
    public let kind: Kind
    public let certainty: Certainty
    public let areas: [String]
    public let note: String
    public let prep: [PrepStep]

    public var id: String { key }
}

/// A suggested task for a moment, due a number of days before it (negative = after it).
public struct PrepStep: Identifiable, Hashable, Sendable {
    public let key: String
    public let title: String
    public let daysBefore: Int
    public let category: TaskCategory
    public let department: String?

    public var id: String { key }

    /// When this step should be done: `daysBefore` the moment, moved back to a scheduled workday so it
    /// lands before the moment rather than on a day off, and never earlier than today.
    public func suggestedDue(for moment: RetailMoment, now: Date, schedule: ShiftSchedule?, calendar: Calendar) -> Date {
        let math = DateMath(calendar: calendar)
        let today = math.startOfDay(now)
        var due = math.addingDays(-daysBefore, to: math.startOfDay(moment.start))
        if let schedule, schedule.workdayCount > 0, !schedule.isWorkday(due, calendar: calendar) {
            for back in 1...6 {
                let earlier = math.addingDays(-back, to: due)
                if schedule.isWorkday(earlier, calendar: calendar) { due = earlier; break }
            }
        }
        if due < today {
            due = schedule.map { $0.isWorkday(today, calendar: calendar) ? today : $0.nextWorkday(after: today, calendar: calendar) } ?? today
        }
        return due
    }
}

/// Holidays, Walmart's fiscal week, announced sales events and typical seasonal timing.
/// Everything is computed on the device; nothing is fetched.
public enum RetailCalendar {
    public enum Holiday: String, CaseIterable, Sendable {
        case newYearsDay, bigGame, valentinesDay, easter, mothersDay, memorialDay, fathersDay
        case independenceDay, laborDay, halloween, thanksgiving, blackFriday, cyberMonday
        case christmasEve, christmas, newYearsEve

        public var title: String {
            switch self {
            case .newYearsDay: return "New Year's Day"
            case .bigGame: return "Big Game Sunday"
            case .valentinesDay: return "Valentine's Day"
            case .easter: return "Easter"
            case .mothersDay: return "Mother's Day"
            case .memorialDay: return "Memorial Day"
            case .fathersDay: return "Father's Day"
            case .independenceDay: return "Fourth of July"
            case .laborDay: return "Labor Day"
            case .halloween: return "Halloween"
            case .thanksgiving: return "Thanksgiving"
            case .blackFriday: return "Black Friday"
            case .cyberMonday: return "Cyber Monday"
            case .christmasEve: return "Christmas Eve"
            case .christmas: return "Christmas"
            case .newYearsEve: return "New Year's Eve"
            }
        }

        /// Phrases Quick Capture recognises after "by", "before", "on" or "until".
        var spokenPattern: String {
            switch self {
            case .newYearsDay: return #"new\s+year'?s(?:\s+day)?"#
            case .bigGame: return #"(?:the\s+)?(?:super\s+bowl|big\s+game)(?:\s+sunday)?"#
            case .valentinesDay: return #"valentine'?s(?:\s+day)?"#
            case .easter: return #"easter(?:\s+sunday)?"#
            case .mothersDay: return #"mother'?s\s+day"#
            case .memorialDay: return #"memorial\s+day"#
            case .fathersDay: return #"father'?s\s+day"#
            case .independenceDay: return #"(?:the\s+)?(?:4th|fourth)\s+of\s+july|july\s+(?:4th|fourth)|independence\s+day"#
            case .laborDay: return #"labor\s+day"#
            case .halloween: return #"halloween"#
            case .thanksgiving: return #"thanksgiving(?:\s+day)?"#
            case .blackFriday: return #"black\s+friday"#
            case .cyberMonday: return #"cyber\s+monday"#
            case .christmasEve: return #"christmas\s+eve|xmas\s+eve"#
            case .christmas: return #"christmas(?:\s+day)?|xmas"#
            case .newYearsEve: return #"new\s+year'?s\s+eve|nye"#
            }
        }
    }

    // MARK: Holiday dates

    public static func date(of holiday: Holiday, year: Int, calendar: Calendar) -> Date {
        switch holiday {
        case .newYearsDay: return day(year, 1, 1, calendar)
        case .bigGame: return nthWeekday(2, weekday: 1, month: 2, year: year, calendar)
        case .valentinesDay: return day(year, 2, 14, calendar)
        case .easter: return easter(year, calendar)
        case .mothersDay: return nthWeekday(2, weekday: 1, month: 5, year: year, calendar)
        case .memorialDay: return lastWeekday(2, month: 5, year: year, calendar)
        case .fathersDay: return nthWeekday(3, weekday: 1, month: 6, year: year, calendar)
        case .independenceDay: return day(year, 7, 4, calendar)
        case .laborDay: return nthWeekday(1, weekday: 2, month: 9, year: year, calendar)
        case .halloween: return day(year, 10, 31, calendar)
        case .thanksgiving: return nthWeekday(4, weekday: 5, month: 11, year: year, calendar)
        case .blackFriday: return DateMath(calendar: calendar).addingDays(1, to: date(of: .thanksgiving, year: year, calendar: calendar))
        case .cyberMonday: return DateMath(calendar: calendar).addingDays(4, to: date(of: .thanksgiving, year: year, calendar: calendar))
        case .christmasEve: return day(year, 12, 24, calendar)
        case .christmas: return day(year, 12, 25, calendar)
        case .newYearsEve: return day(year, 12, 31, calendar)
        }
    }

    /// The next time `holiday` falls on or after `now`.
    public static func nextDate(of holiday: Holiday, onOrAfter now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        let thisYear = date(of: holiday, year: year, calendar: calendar)
        return thisYear >= today ? thisYear : date(of: holiday, year: year + 1, calendar: calendar)
    }

    // MARK: Walmart fiscal calendar

    /// Weeks run Saturday–Friday. Each fiscal year starts on the Saturday of the week containing
    /// February 1 and is named for the calendar year it ends in (Feb 2026–Jan 2027 is FY2027).
    public static func fiscalYearStart(fiscalYear: Int, calendar: Calendar) -> Date {
        let feb1 = day(fiscalYear - 1, 2, 1, calendar)
        let weekday = calendar.component(.weekday, from: feb1) // Saturday = 7
        return DateMath(calendar: calendar).addingDays(-(weekday % 7), to: feb1)
    }

    /// Fiscal year and week number (1-based) for a date, e.g. Mon 23 Nov 2026 → FY2027 week 43.
    public static func fiscalWeek(of date: Date, calendar: Calendar) -> (fiscalYear: Int, week: Int) {
        let math = DateMath(calendar: calendar)
        let day = math.startOfDay(date)
        var fy = calendar.component(.year, from: day) + 1
        while fiscalYearStart(fiscalYear: fy, calendar: calendar) > day { fy -= 1 }
        let days = math.daysBetween(fiscalYearStart(fiscalYear: fy, calendar: calendar), day)
        return (fy, days / 7 + 1)
    }

    /// "FY27 · Week 43"
    public static func fiscalWeekLabel(for date: Date, calendar: Calendar) -> String {
        let fw = fiscalWeek(of: date, calendar: calendar)
        return "FY\(fw.fiscalYear % 100) · Week \(fw.week)"
    }

    // MARK: Moments

    /// Everything from the start of `now`'s day through `days` ahead, earliest first, including the
    /// person's own store events.
    public static func upcoming(from now: Date, days: Int, calendar: Calendar,
                                including storeEvents: [StoreEvent] = []) -> [RetailMoment] {
        let math = DateMath(calendar: calendar)
        let today = math.startOfDay(now)
        let horizon = math.addingDays(days, to: today)
        let year = calendar.component(.year, from: today)
        var all: [RetailMoment] = []
        for y in (year - 1)...(year + 1) { all += moments(inYear: y, calendar: calendar) }
        for event in storeEvents where event.isValid { all.append(event.moment(calendar: calendar)) }
        let inRange = all.filter { (moment: RetailMoment) -> Bool in
            (moment.end ?? moment.start) >= today && moment.start <= horizon
        }
        return inRange.sorted { (a: RetailMoment, b: RetailMoment) -> Bool in
            a.start != b.start ? a.start < b.start : a.title < b.title
        }
    }

    /// Every moment for one calendar year.
    public static func moments(inYear year: Int, calendar: Calendar) -> [RetailMoment] {
        let math = DateMath(calendar: calendar)
        var list: [RetailMoment] = []

        func add(_ id: String, _ title: String, _ start: Date, end: Date? = nil, _ kind: RetailMoment.Kind,
                 _ certainty: RetailMoment.Certainty, areas: [String], note: String,
                 prep: [(Int, String, TaskCategory, String?)]) {
            let key = "\(year)-\(id)"
            let steps = prep.enumerated().map { index, step in
                PrepStep(key: "\(key)#\(index)", title: step.1, daysBefore: step.0, category: step.2, department: step.3)
            }
            list.append(RetailMoment(key: key, title: title, start: start, end: end, kind: kind, certainty: certainty,
                                     areas: areas, note: note, prep: steps))
        }
        func h(_ holiday: Holiday) -> Date { date(of: holiday, year: year, calendar: calendar) }
        let hoursCheck = "Confirm store hours and adjust schedules"

        add("new-years-day", "New Year's Day", h(.newYearsDay), .holiday, .calendar,
            areas: [], note: "Holiday hours may differ — confirm with your store manager.",
            prep: [(7, "\(hoursCheck) for New Year's Day", .people, nil)])

        let fyStart = fiscalYearStart(fiscalYear: year + 1, calendar: calendar)
        add("fiscal-year", "New fiscal year — Week 1 (FY\((year + 1) % 100))", fyStart, .fiscal, .calendar,
            areas: [], note: "Walmart weeks run Saturday–Friday, and the fiscal year starts on the Saturday of the week containing February 1.",
            prep: [(7, "Review last year's results and set goals with your TLs", .admin, nil)])

        add("big-game", "Big Game Sunday", h(.bigGame), .salesEvent, .typical,
            areas: ["Food", "Fresh", "Electronics"], note: "The NFL sets the date — usually the second Sunday in February.",
            prep: [(14, "Big Game features set: snacks, drinks, party trays, TVs", .merchandising, "Food"),
                   (3, "Stock check on chips, soda, wings and party trays", .freight, "Food")])

        add("valentines", "Valentine's Day", h(.valentinesDay), .holiday, .calendar,
            areas: ["Seasonal", "Fresh", "Food"], note: "Floral, candy, cards and bakery peak the last few days.",
            prep: [(21, "Valentine's set complete", .merchandising, "Seasonal"),
                   (2, "Floral, candy and card features full", .freight, nil),
                   (-1, "Valentine's clearance and transition to Easter/spring", .merchandising, "Seasonal")])

        add("lawn-garden", "Lawn & Garden season ramps up", day(year, 3, 1, calendar), .seasonal, .typical,
            areas: ["Lawn & Garden"], note: "Timing depends on your region's weather.",
            prep: [(0, "Garden center staffing and live-goods watering plan", .operations, "Lawn & Garden"),
                   (0, "Safety huddle: bagged soil and mulch pallets, PLE, lifting", .safety, "Lawn & Garden")])

        let dstStart = nthWeekday(2, weekday: 1, month: 3, year: year, calendar)
        add("dst-start", "Clocks spring forward (2 AM)", dstStart, .operations, .calendar,
            areas: ["Overnight"], note: "Overnight shifts that night are an hour shorter.",
            prep: [(3, "Check overnight schedules, punches and meal timing for the time change", .people, "Overnight")])

        add("easter", "Easter", h(.easter), .holiday, .calendar,
            areas: ["Seasonal", "Food", "Fresh"], note: "Easter moves every year (\(RelativeDateText.mediumDate(h(.easter), calendar: calendar)) this year).",
            prep: [(28, "Easter set complete", .merchandising, "Seasonal"),
                   (3, "Candy, baskets, ham and bakery stocked up", .freight, nil),
                   (-1, "Easter clearance and spring transition", .merchandising, "Seasonal")])

        add("mothers-day", "Mother's Day", h(.mothersDay), .holiday, .calendar,
            areas: ["Fresh", "Seasonal"], note: "Floral, cards and gifts.",
            prep: [(10, "Mother's Day floral, card and gift features ready", .merchandising, nil)])

        add("memorial-day", "Memorial Day", h(.memorialDay), .holiday, .calendar,
            areas: ["Seasonal", "Food", "Fresh"], note: "Unofficial start of summer: grilling, pool and patio.",
            prep: [(10, "Summer features: grills, charcoal, coolers, water", .merchandising, "Seasonal"),
                   (7, "\(hoursCheck) for Memorial Day", .people, nil)])

        add("hurricane-season", "Hurricane season starts", day(year, 6, 1, calendar), .safety, .calendar, areas: [],
            note: "The Atlantic season runs June 1 – November 30. Skip this if your store isn't in a hurricane area.",
            prep: [(0, "Review the emergency action plan and storm-supply stock (water, batteries, generators)", .safety, nil)])

        add("heat-safety", "Summer heat safety", day(year, 6, 1, calendar), .safety, .typical,
            areas: ["Stocking", "Overnight", "Front End"], note: "Hot trailers, the dock and the cart lot are the usual risks.",
            prep: [(0, "Heat safety huddle: water, breaks, trailer and cart-lot exposure", .safety, nil)])

        add("fathers-day", "Father's Day", h(.fathersDay), .holiday, .calendar,
            areas: ["Seasonal", "Hardware", "Electronics"], note: "Grills, tools, electronics and cards.",
            prep: [(10, "Father's Day features: grills, tools, cards", .merchandising, nil)])

        add("july-4", "Fourth of July", h(.independenceDay), .holiday, .calendar,
            areas: ["Seasonal", "Food", "Fresh"], note: "Grilling, coolers and party supplies.",
            prep: [(10, "July 4th features: grilling, coolers, party supplies", .merchandising, "Seasonal"),
                   (7, "\(hoursCheck) for July 4th", .people, nil)])

        add("back-to-school", "Back-to-school set", day(year, 7, 10, calendar), .seasonal, .typical,
            areas: ["Seasonal", "Fashion", "Electronics"],
            note: "Timing follows your local school start dates — check your modular and feature calendar.",
            prep: [(0, "Back-to-school set: supplies, backpacks, lunch, uniforms", .merchandising, "Seasonal"),
                   (0, "Plan freight and staffing for the back-to-school peak", .freight, nil)])

        let laborDay = h(.laborDay)
        add("labor-day", "Labor Day", laborDay, .holiday, .calendar,
            areas: [], note: "Last summer holiday.",
            prep: [(7, "\(hoursCheck) for Labor Day", .people, nil)])

        add("halloween-set", "Halloween set", math.addingDays(1, to: laborDay), .seasonal, .typical,
            areas: ["Seasonal", "Fashion", "Food"],
            note: "Halloween merchandise usually arrives just after Labor Day; some stores start earlier.",
            prep: [(0, "Halloween set: costumes, candy, décor", .merchandising, "Seasonal"),
                   (0, "Summer and back-to-school clearance; feature-to-home", .merchandising, nil)])

        add("holiday-staffing", "Holiday staffing plan", day(year, 9, 15, calendar), .operations, .typical,
            areas: [], note: "Seasonal hiring, availability and extra hours ahead of Q4.",
            prep: [(0, "Plan holiday staffing: hiring needs, availability, extra-hours sign-up", .people, nil)])

        add("halloween", "Halloween", h(.halloween), .holiday, .calendar,
            areas: ["Seasonal", "Food"], note: "Stores usually convert to holiday right after Halloween.",
            prep: [(7, "Candy and costume stock-up; plan the November 1 conversion", .freight, "Seasonal"),
                   (-1, "Convert Halloween to holiday; Halloween clearance", .merchandising, "Seasonal")])

        let dstEnd = nthWeekday(1, weekday: 1, month: 11, year: year, calendar)
        add("dst-end", "Clocks fall back (2 AM)", dstEnd, .operations, .calendar,
            areas: ["Overnight"], note: "Overnight shifts that night are an hour longer.",
            prep: [(3, "Check overnight schedules, punches and meal timing for the time change", .people, "Overnight")])

        add("winter-safety", "Winter weather prep", day(year, 11, 15, calendar), .safety, .typical,
            areas: [], note: "Skip this if your area doesn't get ice or snow.",
            prep: [(0, "Winter safety: ice melt stocked, entrance mats, parking-lot plan", .safety, nil)])

        add("thanksgiving", "Thanksgiving", h(.thanksgiving), .holiday, .calendar,
            areas: ["Food", "Fresh"], note: "Turkeys, baking and sides peak the week before.",
            prep: [(14, "Thanksgiving meal items stocked and featured: turkeys, baking, sides", .freight, "Food"),
                   (7, "\(hoursCheck) for Thanksgiving", .people, nil)])

        add("black-friday", "Black Friday", h(.blackFriday), .holiday, .calendar,
            areas: ["Electronics", "Seasonal", "Front End", "Asset Protection"], note: "Pallet drops, queues and crowds.",
            prep: [(10, "Black Friday plan: pallet-drop locations, staffing, queue lines", .operations, nil),
                   (3, "Black Friday safety walk: aisles clear, PLE parked, crowd plan", .safety, nil),
                   (1, "Pallet drops staged and wrapped; signing ready", .freight, nil)])

        add("cyber-monday", "Cyber Monday", h(.cyberMonday), .salesEvent, .calendar,
            areas: ["Digital (OPD)"], note: "Online orders spike — OPD picking and dispensing.",
            prep: [(2, "OPD staffing for Cyber Monday orders", .people, "Digital (OPD)")])

        add("christmas-eve", "Christmas Eve", h(.christmasEve), .holiday, .calendar,
            areas: [], note: "Early closing is common — confirm hours.",
            prep: [(7, "\(hoursCheck) for Christmas Eve and Christmas", .people, nil)])

        add("christmas", "Christmas", h(.christmas), .holiday, .calendar,
            areas: ["Seasonal", "Electronics", "Front End"], note: "Last-minute gifts, then returns and clearance on the 26th.",
            prep: [(10, "Last-minute gift features and gift cards full", .merchandising, nil),
                   (-1, "Returns, holiday clearance and transition to Valentine's/organization", .merchandising, "Seasonal")])

        add("new-years-eve", "New Year's Eve", h(.newYearsEve), .holiday, .calendar,
            areas: ["Food", "Seasonal"], note: "Party drinks, snacks and supplies.",
            prep: [(5, "New Year's party features: drinks, snacks, party supplies", .merchandising, "Food")])

        for event in announcedEvents where calendar.component(.year, from: event.start(calendar)) == year {
            add(event.id, event.title, event.start(calendar), end: event.end(calendar), .salesEvent, .announced,
                areas: event.areas, note: event.note, prep: event.prep)
        }
        return list
    }

    // MARK: Announced events (update as dates are announced)

    struct AnnouncedEvent {
        let id: String
        let title: String
        let startDay: (Int, Int, Int)
        let endDay: (Int, Int, Int)
        let areas: [String]
        let note: String
        let prep: [(Int, String, TaskCategory, String?)]

        func start(_ calendar: Calendar) -> Date { RetailCalendar.day(startDay.0, startDay.1, startDay.2, calendar) }
        func end(_ calendar: Calendar) -> Date { RetailCalendar.day(endDay.0, endDay.1, endDay.2, calendar) }
    }

    /// Walmart's publicly announced deal events. Dates for future years are added once announced.
    static let announcedEvents: [AnnouncedEvent] = [
        AnnouncedEvent(id: "walmart-deals", title: "Walmart Deals", startDay: (2026, 6, 22), endDay: (2026, 6, 28),
                       areas: ["Electronics", "Seasonal", "Digital (OPD)"],
                       note: "Summer deals event, moved up from July this year. Walmart+ members got early access online.",
                       prep: [(7, "Walmart Deals features set and OPD staffing planned", .merchandising, nil),
                              (1, "Deals freight worked and features full", .freight, nil)]),
        AnnouncedEvent(id: "early-black-friday", title: "Early Black Friday Deals", startDay: (2026, 11, 12), endDay: (2026, 11, 15),
                       areas: ["Electronics", "Seasonal", "Digital (OPD)"],
                       note: "Online at 12:01 AM ET and in stores at 6 AM local time.",
                       prep: [(7, "Event 1 features set and pallet drops planned", .merchandising, nil),
                              (1, "Event 1 freight worked; PLE and pallet-drop safety huddle", .safety, nil)]),
        AnnouncedEvent(id: "black-friday-deals", title: "Black Friday Deals", startDay: (2026, 11, 23), endDay: (2026, 11, 29),
                       areas: ["Electronics", "Seasonal", "Digital (OPD)", "Front End"],
                       note: "Online from November 23; in stores from Black Friday, November 27 at 6 AM local time.",
                       prep: [(0, "OPD ready for online Black Friday orders starting today", .people, "Digital (OPD)")]),
        AnnouncedEvent(id: "cyber-monday-deals", title: "Cyber Monday Deals", startDay: (2026, 11, 30), endDay: (2026, 12, 2),
                       areas: ["Digital (OPD)"], note: "Three-day online event.",
                       prep: [])
    ]

    // MARK: Date helpers

    static func day(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)).map { calendar.startOfDay(for: $0) } ?? Date()
    }

    /// The nth `weekday` (1 = Sunday … 7 = Saturday) of a month.
    static func nthWeekday(_ n: Int, weekday: Int, month: Int, year: Int, _ calendar: Calendar) -> Date {
        let first = day(year, month, 1, calendar)
        let offset = (weekday - calendar.component(.weekday, from: first) + 7) % 7
        return DateMath(calendar: calendar).addingDays(offset + 7 * (n - 1), to: first)
    }

    /// The last `weekday` of a month.
    static func lastWeekday(_ weekday: Int, month: Int, year: Int, _ calendar: Calendar) -> Date {
        let math = DateMath(calendar: calendar)
        let nextMonth = month == 12 ? day(year + 1, 1, 1, calendar) : day(year, month + 1, 1, calendar)
        let last = math.addingDays(-1, to: nextMonth)
        let offset = (calendar.component(.weekday, from: last) - weekday + 7) % 7
        return math.addingDays(-offset, to: last)
    }

    /// Western Easter (anonymous Gregorian algorithm).
    static func easter(_ year: Int, _ calendar: Calendar) -> Date {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let dayOfMonth = (h + l - 7 * m + 114) % 31 + 1
        return day(year, month, dayOfMonth, calendar)
    }
}

// MARK: - Your store events

/// An event the person adds for their store: a remodel, an inventory count, a local festival, or
/// next year's deal dates once they're announced. Kept on the phone and included in backups.
public struct StoreEvent: Codable, Hashable, Identifiable, Sendable {
    /// A prep step, due a number of days before the event (negative = after it).
    public struct Step: Codable, Hashable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var daysBefore: Int

        public init(id: UUID = UUID(), title: String = "", daysBefore: Int = 7) {
            self.id = id
            self.title = title
            self.daysBefore = daysBefore
        }
    }

    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date?
    public var note: String
    public var steps: [Step]

    public init(id: UUID = UUID(), title: String = "", start: Date = Date(), end: Date? = nil,
                note: String = "", steps: [Step] = []) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.note = note
        self.steps = steps
    }

    public var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The key used for hiding the event; each step's key adds its own id, so editing one step never
    /// changes which steps are already added as tasks.
    public var key: String { "store-" + id.uuidString }

    /// Trimmed title, note and steps, with empty steps dropped and the end never before the start.
    public func cleaned(calendar: Calendar) -> StoreEvent {
        let math = DateMath(calendar: calendar)
        var event = self
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        event.start = math.startOfDay(start)
        if let end { event.end = max(math.startOfDay(end), event.start) }
        if event.end == event.start { event.end = nil }
        event.steps = steps.compactMap { step in
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : Step(id: step.id, title: title, daysBefore: step.daysBefore)
        }
        return event
    }

    public func moment(calendar: Calendar) -> RetailMoment {
        let math = DateMath(calendar: calendar)
        let prep = steps.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.map { step in
            PrepStep(key: "\(key)#\(step.id.uuidString)", title: step.title, daysBefore: step.daysBefore,
                     category: .operations, department: nil)
        }
        return RetailMoment(key: key, title: title, start: math.startOfDay(start), end: end.map(math.startOfDay),
                            kind: .store, certainty: .yours, areas: [], note: note, prep: prep)
    }
}
