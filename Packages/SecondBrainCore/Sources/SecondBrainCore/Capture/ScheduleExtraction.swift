import Foundation

struct RecurrenceHit {
    var rule: RecurrenceRule
    var timeMinutes: Int?
    var timeLabel: String?
}

struct TimeHit {
    /// Minutes after midnight (nil when `absolute` is set).
    var minutes: Int?
    /// For relative times like "in 30 minutes".
    var absolute: Date?
    var label: String
    var impliesToday: Bool
    /// Set for "end of shift" / "first thing", so the time follows the person's schedule for that day.
    var shiftAnchor: ShiftAnchor? = nil
}

enum ShiftAnchor { case start, end }

struct DateHit {
    var date: Date
    var label: String
    var location: Int
}

/// Extracts recurrence, time and date phrases. Every interpretation that involves a guess
/// records a `CaptureAmbiguity` so the person sees it before saving.
enum ScheduleExtraction {
    // MARK: - Recurrence

    static func recurrence(_ scan: CaptureScan, _ ctx: CaptureContext, _ ambiguities: inout [CaptureAmbiguity]) -> RecurrenceHit? {
        let wd = CalendarWords.weekdayAny
        let plural = CalendarWords.weekdayPlural
        let math = DateMath(calendar: ctx.calendar)

        func weekdays(in text: String) -> [Int] {
            guard let regex = Lexicon.regex(#"\b(?:\#(plural)|\#(wd))\b"#) else { return [] }
            let ns = text as NSString
            return regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
                .compactMap { CalendarWords.weekdayNumber(ns.substring(with: $0.range)) }
        }

        func partOfDay(_ word: String) -> (Int, String)? {
            switch word.lowercased() {
            case "morning": return (9 * 60, "morning")
            case "afternoon": return (13 * 60, "afternoon")
            case "evening": return (18 * 60, "evening")
            case "night": return (20 * 60, "night")
            default: return nil
            }
        }

        // "on the 5th of every month"
        if let m = scan.firstMatch(#"\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)\s+of\s+(?:every|each)\s+month\b"#),
           let day = scan.group(m, 1).flatMap({ Int($0) }), (1...31).contains(day) {
            scan.consume(m.range)
            return RecurrenceHit(rule: .monthly(day: day))
        }
        // "every 15th (of the month)"
        if let m = scan.firstMatch(#"\b(?:every|each)\s+(\d{1,2})(?:st|nd|rd|th)(?:\s+(?:of\s+)?(?:the\s+|each\s+|every\s+)?month)?\b"#),
           let day = scan.group(m, 1).flatMap({ Int($0) }), (1...31).contains(day) {
            scan.consume(m.range)
            return RecurrenceHit(rule: .monthly(day: day))
        }
        // "every other week / day / Monday"
        if let m = scan.firstMatch(#"\b(?:every|each)\s+other\s+(day|week|month|\#(wd))\b"#),
           let unit = scan.group(m, 1)?.lowercased() {
            scan.consume(m.range)
            switch unit {
            case "day": return RecurrenceHit(rule: RecurrenceRule(frequency: .daily, interval: 2))
            case "week": return RecurrenceHit(rule: weeklyWithOptionalDay(scan, interval: 2, math: math, ctx: ctx))
            case "month": return RecurrenceHit(rule: monthlyWithOptionalDay(scan, interval: 2))
            default:
                if let n = CalendarWords.weekdayNumber(unit) { return RecurrenceHit(rule: .weekly(on: [n], interval: 2)) }
            }
        }
        // "every 2 weeks"
        if let m = scan.firstMatch(#"\b(?:every|each)\s+(\d{1,2}|two|three|four|five|six|seven|eight|nine|ten)\s+(days?|weeks?|months?)\b"#),
           let n = scan.group(m, 1).flatMap({ NumberWords.value($0) }), n > 0,
           let unit = scan.group(m, 2)?.lowercased() {
            scan.consume(m.range)
            if unit.hasPrefix("day") { return RecurrenceHit(rule: RecurrenceRule(frequency: .daily, interval: n)) }
            if unit.hasPrefix("week") { return RecurrenceHit(rule: weeklyWithOptionalDay(scan, interval: n, math: math, ctx: ctx)) }
            return RecurrenceHit(rule: monthlyWithOptionalDay(scan, interval: n))
        }
        // "every weekday"
        if let m = scan.firstMatch(#"\b(?:(?:every|each)\s+(?:weekday|weekdays|work\s?days?|business\s+days?)|on\s+weekdays|weekdays)\b"#) {
            scan.consume(m.range)
            return RecurrenceHit(rule: .weekdaysOnly)
        }
        // "every Monday", "every Mon and Thu"
        if let m = scan.firstMatch(#"\b(?:every|each)\s+((?:\#(wd))\b\.?(?:\s*(?:,|and|&|/|\+)\s*(?:\#(wd))\b\.?)*)"#),
           let list = scan.group(m, 1) {
            let days = weekdays(in: list)
            if !days.isEmpty {
                scan.consume(m.range)
                return RecurrenceHit(rule: .weekly(on: days))
            }
        }
        // "on Mondays", "Mondays and Thursdays"
        if let m = scan.firstMatch(#"\b(?:on\s+)?((?:\#(plural))(?:\s*(?:,|and|&|/)\s*(?:\#(plural)))*)\b"#),
           let list = scan.group(m, 1) {
            let days = weekdays(in: list)
            if !days.isEmpty {
                scan.consume(m.range)
                return RecurrenceHit(rule: .weekly(on: days))
            }
        }
        // "every day / morning / shift"
        if let m = scan.firstMatch(#"\b(?:every|each)\s+(day|morning|afternoon|evening|night|shift)\b"#),
           let unit = scan.group(m, 1)?.lowercased() {
            scan.consume(m.range)
            if unit == "shift" {
                return RecurrenceHit(rule: .daily, timeMinutes: ctx.shiftStartMinutes, timeLabel: "start of shift")
            }
            if let (minutes, label) = partOfDay(unit) {
                ambiguities.append(CaptureAmbiguity(field: .time, message: "“every \(label)” — set to \(RelativeDateText.minutesText(minutes, calendar: ctx.calendar)). Adjust if needed."))
                return RecurrenceHit(rule: .daily, timeMinutes: minutes, timeLabel: label)
            }
            return RecurrenceHit(rule: .daily)
        }
        // "every week" / "every month"
        if let m = scan.firstMatch(#"\b(?:every|each)\s+(week|month)\b"#), let unit = scan.group(m, 1)?.lowercased() {
            scan.consume(m.range)
            if unit == "week" { return RecurrenceHit(rule: weeklyWithOptionalDay(scan, interval: 1, math: math, ctx: ctx)) }
            return RecurrenceHit(rule: monthlyWithOptionalDay(scan, interval: 1))
        }
        // "daily", "weekly", "biweekly", "monthly"
        if let m = scan.firstMatch(#"\b(daily|nightly|weekly|monthly|bi-?weekly|fortnightly)\b"#), let word = scan.group(m, 1)?.lowercased() {
            scan.consume(m.range)
            switch word {
            case "daily", "nightly": return RecurrenceHit(rule: .daily)
            case "weekly": return RecurrenceHit(rule: weeklyWithOptionalDay(scan, interval: 1, math: math, ctx: ctx))
            case "monthly": return RecurrenceHit(rule: monthlyWithOptionalDay(scan, interval: 1))
            default: return RecurrenceHit(rule: weeklyWithOptionalDay(scan, interval: 2, math: math, ctx: ctx))
            }
        }
        return nil
    }

    private static func weeklyWithOptionalDay(_ scan: CaptureScan, interval: Int, math: DateMath, ctx: CaptureContext) -> RecurrenceRule {
        let wd = CalendarWords.weekdayAny
        if let m = scan.firstMatch(#"\bon\s+(\#(wd))\b\.?"#), let token = scan.group(m, 1), let n = CalendarWords.weekdayNumber(token) {
            scan.consume(m.range)
            return .weekly(on: [n], interval: interval)
        }
        return .weekly(on: [math.weekday(ctx.now)], interval: interval)
    }

    private static func monthlyWithOptionalDay(_ scan: CaptureScan, interval: Int) -> RecurrenceRule {
        if let m = scan.firstMatch(#"\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)\b"#), let day = scan.group(m, 1).flatMap({ Int($0) }), (1...31).contains(day) {
            scan.consume(m.range)
            return .monthly(day: day, interval: interval)
        }
        return .monthly(day: nil, interval: interval)
    }

    // MARK: - Time

    static func time(_ scan: CaptureScan, _ ctx: CaptureContext, _ ambiguities: inout [CaptureAmbiguity], _ notes: inout [String]) -> TimeHit? {
        let cal = ctx.calendar

        // "in 30 minutes", "in an hour", "in half an hour"
        if let m = scan.firstMatch(#"\bin\s+(half\s+an?|\#(NumberWords.pattern))\s+(minutes?|mins?|hours?|hrs?)\b"#),
           let amountText = scan.group(m, 1), let unit = scan.group(m, 2)?.lowercased() {
            var minutes: Int?
            if amountText.lowercased().hasPrefix("half") {
                minutes = unit.hasPrefix("h") ? 30 : nil
            } else if let n = NumberWords.value(amountText) {
                minutes = unit.hasPrefix("h") ? n * 60 : n
            }
            if let minutes, minutes > 0 {
                scan.consume(m.range)
                let date = DateMath(calendar: cal).addingMinutes(minutes, to: ctx.now)
                return TimeHit(minutes: nil, absolute: date, label: scan.substring(m.range), impliesToday: false)
            }
        }

        // "3pm", "at 3:30 p.m."
        if let m = scan.firstMatch(#"(?:(?:\bat|\bby|\baround|\bbefore|@)\s*)?\b(\d{1,2})(?::([0-5]\d))?\s*(a\.m\.?|p\.m\.?|am|pm)(?![a-z])"#),
           let hourText = scan.group(m, 1), var hour = Int(hourText), (1...12).contains(hour),
           let meridiem = scan.group(m, 3)?.lowercased() {
            let minute = scan.group(m, 2).flatMap { Int($0) } ?? 0
            let pm = meridiem.hasPrefix("p")
            if pm && hour < 12 { hour += 12 }
            if !pm && hour == 12 { hour = 0 }
            scan.consume(m.range)
            return TimeHit(minutes: hour * 60 + minute, absolute: nil, label: scan.substring(m.range), impliesToday: false)
        }

        // "at 14:30", "at 3:30" (no meridiem)
        if let m = scan.firstMatch(#"(?:\bat|\bby|\baround|@)\s*(\d{1,2}):([0-5]\d)\b"#),
           let h = scan.group(m, 1).flatMap({ Int($0) }), let minute = scan.group(m, 2).flatMap({ Int($0) }), h <= 23 {
            scan.consume(m.range)
            let hour = resolveHour(h, ctx: ctx, ambiguities: &ambiguities)
            return TimeHit(minutes: hour * 60 + minute, absolute: nil, label: scan.substring(m.range), impliesToday: false)
        }

        // "at 3", "by 5"
        if let m = scan.firstMatch(#"(?:\bat|\bby|\baround|@)\s*(\d{1,2})\b(?!\s*(?:/|:|%|\.\d|st\b|nd\b|rd\b|th\b|days?\b|weeks?\b|months?\b|hours?\b|minutes?\b|mins?\b|percent|units?\b|cases?\b|pallets?\b|items?\b|people\b|associates?\b))"#),
           let h = scan.group(m, 1).flatMap({ Int($0) }), h <= 23 {
            scan.consume(m.range)
            let hour = resolveHour(h, ctx: ctx, ambiguities: &ambiguities)
            return TimeHit(minutes: hour * 60, absolute: nil, label: scan.substring(m.range), impliesToday: false)
        }

        // bare "14:30"
        if let m = scan.firstMatch(#"(?<![\d/])\b(\d{1,2}):([0-5]\d)\b"#),
           let h = scan.group(m, 1).flatMap({ Int($0) }), let minute = scan.group(m, 2).flatMap({ Int($0) }), h <= 23 {
            scan.consume(m.range)
            let hour = resolveHour(h, ctx: ctx, ambiguities: &ambiguities)
            return TimeHit(minutes: hour * 60 + minute, absolute: nil, label: scan.substring(m.range), impliesToday: false)
        }

        // noon / midnight
        if let m = scan.firstMatch(#"(?:\b(?:at|by|around|before)\s+)?\b(noon|midday|lunchtime)\b"#) {
            scan.consume(m.range)
            return TimeHit(minutes: 12 * 60, absolute: nil, label: scan.substring(m.range), impliesToday: false)
        }
        if let m = scan.firstMatch(#"(?:\b(?:at|by|before)\s+)?\bmidnight\b"#) {
            scan.consume(m.range)
            notes.append("“midnight” → 11:59 PM")
            return TimeHit(minutes: 23 * 60 + 59, absolute: nil, label: scan.substring(m.range), impliesToday: false)
        }

        // end of shift / end of day
        if let m = scan.firstMatch(#"(?:\b(?:by|at|before|until)\s+)?(?:the\s+)?(?:\bend\s+of\s+(?:my\s+|the\s+)?shift\b|\bbefore\s+i\s+(?:leave|go\s+home|clock\s+out)\b|\beos\b|\bend\s+of\s+(?:the\s+)?day\b|\beod\b|\bcob\b|\bclose\s+of\s+business\b)"#) {
            scan.consume(m.range)
            notes.append("“\(scan.substring(m.range).trimmingCharacters(in: .whitespaces))” → \(RelativeDateText.minutesText(ctx.shiftEndMinutes, calendar: cal)) (shift end)")
            return TimeHit(minutes: ctx.shiftEndMinutes, absolute: nil, label: scan.substring(m.range), impliesToday: false, shiftAnchor: .end)
        }

        // start of shift / first thing
        if let m = scan.firstMatch(#"(?:\b(?:at|by)\s+)?(?:the\s+)?(?:\b(?:start|beginning)\s+of\s+(?:my\s+|the\s+)?shift\b|\bfirst\s+thing(?:\s+in\s+the\s+morning)?\b)"#) {
            scan.consume(m.range)
            notes.append("“\(scan.substring(m.range).trimmingCharacters(in: .whitespaces))” → \(RelativeDateText.minutesText(ctx.shiftStartMinutes, calendar: cal)) (shift start)")
            return TimeHit(minutes: ctx.shiftStartMinutes, absolute: nil, label: scan.substring(m.range), impliesToday: false, shiftAnchor: .start)
        }

        // "this afternoon", "tonight", "in the morning"
        if let m = scan.firstMatch(#"\b(?:(?:this|in\s+the)\s+)?(morning|afternoon|evening)\b|\b(tonight)\b"#) {
            let word = (scan.group(m, 1) ?? scan.group(m, 2) ?? "").lowercased()
            let mapping: [String: Int] = ["morning": 9 * 60, "afternoon": 13 * 60, "evening": 18 * 60, "tonight": 19 * 60]
            if let minutes = mapping[word] {
                scan.consume(m.range)
                ambiguities.append(CaptureAmbiguity(field: .time, message: "“\(word)” has no exact time — set to \(RelativeDateText.minutesText(minutes, calendar: cal))."))
                return TimeHit(minutes: minutes, absolute: nil, label: scan.substring(m.range), impliesToday: word == "tonight")
            }
        }
        return nil
    }

    /// Resolves an hour typed without am/pm, preferring the person's shift window, then business hours.
    private static func resolveHour(_ h: Int, ctx: CaptureContext, ambiguities: inout [CaptureAmbiguity]) -> Int {
        if h == 0 || h >= 13 { return h }
        let am = h == 12 ? 0 : h
        let pm = h == 12 ? 12 : h + 12
        func inShift(_ hour: Int) -> Bool {
            let minutes = hour * 60
            let start = ctx.shiftStartMinutes, end = ctx.shiftEndMinutes
            if start <= end { return minutes >= start && minutes <= end }
            return minutes >= start || minutes <= end   // overnight shift
        }
        let chosen: Int
        switch (inShift(am), inShift(pm)) {
        case (true, false): chosen = am
        case (false, true): chosen = pm
        default: chosen = (h == 12 || h <= 6) ? pm : am
        }
        let label = RelativeDateText.minutesText(chosen * 60, calendar: ctx.calendar)
        ambiguities.append(CaptureAmbiguity(field: .time, message: "No AM/PM given — assumed \(label)."))
        return chosen
    }

    // MARK: - Date

    static func date(_ scan: CaptureScan, _ ctx: CaptureContext, _ ambiguities: inout [CaptureAmbiguity], _ notes: inout [String]) -> DateHit? {
        let math = DateMath(calendar: ctx.calendar)
        let cal = ctx.calendar
        let today = math.startOfDay(ctx.now)
        let prep = #"(?:\b(by|before|on|due|until|for)\s+)?"#
        var hits: [DateHit] = []

        func apply(_ date: Date, _ m: NSTextCheckingResult, before: Bool, label: String? = nil) {
            var resolved = date
            let phrase = scan.substring(m.range).trimmingCharacters(in: .whitespaces)
            if before {
                resolved = math.addingDays(-1, to: date)
                notes.append("“\(phrase)” → due \(RelativeDateText.mediumDate(resolved, calendar: cal))")
            }
            scan.consume(m.range)
            hits.append(DateHit(date: resolved, label: label ?? phrase, location: m.range.location))
        }
        func isBefore(_ m: NSTextCheckingResult) -> Bool { scan.group(m, 1)?.lowercased() == "before" }

        // day after tomorrow
        for m in scan.matches(prep + #"(?:the\s+)?\bday\s+after\s+tomorrow\b"#) {
            apply(math.addingDays(2, to: today), m, before: isBefore(m))
        }
        // today / tonight
        for m in scan.matches(prep + #"\b(today|tonight)\b"#) {
            apply(today, m, before: isBefore(m))
        }
        // tomorrow
        for m in scan.matches(prep + #"\b(tomorrow|tmrw|tmr|tmw|tomorow|tommorow|tommorrow)\b"#) {
            apply(math.addingDays(1, to: today), m, before: isBefore(m))
        }
        // Holidays — only after "by", "before", "on", "until" or "ahead of", because a bare name
        // ("the Halloween set", "Christmas trees") is a season or product, not a due date.
        let holidayOrder: [RetailCalendar.Holiday] = [.christmasEve, .newYearsEve] +
            RetailCalendar.Holiday.allCases.filter { $0 != .christmasEve && $0 != .newYearsEve }
        for holiday in holidayOrder {
            for m in scan.matches(#"\b(by|before|on|until|till|ahead\s+of)\s+(?:"# + holiday.spokenPattern + #")\b"#) {
                let word = (scan.group(m, 1) ?? "").lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                let date = RetailCalendar.nextDate(of: holiday, onOrAfter: ctx.now, calendar: cal)
                apply(date, m, before: word == "before" || word == "ahead of", label: holiday.title)
            }
        }

        // next / this week, weekend, month
        for m in scan.matches(prep + #"\b(next|this|coming)\s+(week|weekend|month)\b"#) {
            guard let which = scan.group(m, 2)?.lowercased(), let unit = scan.group(m, 3)?.lowercased() else { continue }
            let weekStart = math.startOfWeek(containing: today, firstWeekday: ctx.weekStartsOn)
            var date: Date
            switch (which, unit) {
            case ("next", "week"):
                // First weekday (Mon–Fri) of next week.
                let nextWeekStart = math.addingDays(7, to: weekStart)
                date = (0..<7).map { math.addingDays($0, to: nextWeekStart) }.first { (2...6).contains(math.weekday($0)) } ?? nextWeekStart
                ambiguities.append(CaptureAmbiguity(field: .date, message: "“next week” has no day — set to \(RelativeDateText.mediumDate(date, calendar: cal))."))
            case (_, "week"):
                date = math.addingDays(6, to: weekStart)
                if date < today { date = today }
                ambiguities.append(CaptureAmbiguity(field: .date, message: "“this week” — due by the end of the week (\(RelativeDateText.mediumDate(date, calendar: cal)))."))
            case ("next", "weekend"):
                date = math.addingDays(7, to: math.nextDate(onWeekday: 7, from: today, includingToday: true))
                ambiguities.append(CaptureAmbiguity(field: .date, message: "“next weekend” — set to \(RelativeDateText.mediumDate(date, calendar: cal))."))
            case (_, "weekend"):
                date = math.nextDate(onWeekday: 7, from: today, includingToday: true)
            case ("next", "month"):
                date = math.firstDayOfNextMonth(after: today)
                ambiguities.append(CaptureAmbiguity(field: .date, message: "“next month” has no day — set to \(RelativeDateText.mediumDate(date, calendar: cal))."))
            default:
                date = math.lastDayOfMonth(containing: today)
                ambiguities.append(CaptureAmbiguity(field: .date, message: "“this month” — due by \(RelativeDateText.mediumDate(date, calendar: cal))."))
            }
            apply(date, m, before: isBefore(m))
        }
        // end of the week / month
        for m in scan.matches(prep + #"(?:the\s+)?\bend\s+of\s+(?:the\s+|this\s+)?(week|month)\b"#) {
            guard let unit = scan.group(m, 2)?.lowercased() else { continue }
            let date = unit == "week"
                ? math.addingDays(6, to: math.startOfWeek(containing: today, firstWeekday: ctx.weekStartsOn))
                : math.lastDayOfMonth(containing: today)
            apply(date, m, before: isBefore(m))
        }
        // in 3 days / in two weeks
        for m in scan.matches(#"\bin\s+(\#(NumberWords.pattern))\s+(days?|weeks?|months?)\b"#) {
            guard let n = scan.group(m, 1).flatMap({ NumberWords.value($0) }), let unit = scan.group(m, 2)?.lowercased() else { continue }
            let date: Date
            if unit.hasPrefix("day") { date = math.addingDays(n, to: today) }
            else if unit.hasPrefix("week") { date = math.addingDays(7 * n, to: today) }
            else { date = math.addingMonths(n, to: today) }
            apply(date, m, before: false)
        }
        // weekdays: "Friday", "by Thu", "next Monday"
        let wd = CalendarWords.weekdayAny
        for m in scan.matches(prep + #"(?:\b(next|this|coming)\s+)?\b(\#(wd))\b\.?"#) {
            guard let token = scan.group(m, 3), let weekday = CalendarWords.weekdayNumber(token) else { continue }
            let modifier = scan.group(m, 2)?.lowercased()
            let lowerToken = token.lowercased()
            if CalendarWords.restrictedAbbreviations.contains(lowerToken) && scan.group(m, 1) == nil && modifier == nil { continue }
            var date: Date
            if modifier == "next" {
                let nextWeekStart = math.addingDays(7, to: math.startOfWeek(containing: today, firstWeekday: ctx.weekStartsOn))
                date = (0..<7).map { math.addingDays($0, to: nextWeekStart) }.first { math.weekday($0) == weekday } ?? nextWeekStart
                ambiguities.append(CaptureAmbiguity(field: .date, message: "“next \(token)” — set to \(RelativeDateText.mediumDate(date, calendar: cal))."))
            } else {
                date = math.nextDate(onWeekday: weekday, from: today, includingToday: true)
                if math.isSameDay(date, today) {
                    ambiguities.append(CaptureAmbiguity(field: .date, message: "Today is \(token.capitalized) — set for today. Change it if you meant next week."))
                }
            }
            apply(date, m, before: isBefore(m))
        }
        // 12/5, 12/5/26
        for m in scan.matches(prep + #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#) {
            guard let month = scan.group(m, 2).flatMap({ Int($0) }), let day = scan.group(m, 3).flatMap({ Int($0) }) else { continue }
            let year = scan.group(m, 4).flatMap { Int($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
            if let date = resolveCalendarDate(month: month, day: day, year: year, today: today, math: math, ambiguities: &ambiguities) {
                apply(date, m, before: isBefore(m))
            }
        }
        // Dec 5, December 5th, 2026
        for m in scan.matches(prep + #"\b(\#(CalendarWords.months))\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4})\b)?"#) {
            guard let month = scan.group(m, 2).flatMap({ CalendarWords.monthNumber($0) }), let day = scan.group(m, 3).flatMap({ Int($0) }) else { continue }
            let year = scan.group(m, 4).flatMap { Int($0) }
            if let date = resolveCalendarDate(month: month, day: day, year: year, today: today, math: math, ambiguities: &ambiguities) {
                apply(date, m, before: isBefore(m))
            }
        }
        // 5th of December
        for m in scan.matches(prep + #"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(\#(CalendarWords.months))\b(?:,?\s+(\d{4})\b)?"#) {
            guard let day = scan.group(m, 2).flatMap({ Int($0) }), let month = scan.group(m, 3).flatMap({ CalendarWords.monthNumber($0) }) else { continue }
            let year = scan.group(m, 4).flatMap { Int($0) }
            if let date = resolveCalendarDate(month: month, day: day, year: year, today: today, math: math, ambiguities: &ambiguities) {
                apply(date, m, before: isBefore(m))
            }
        }
        // on the 15th
        for m in scan.matches(prep + #"\bthe\s+(\d{1,2})(?:st|nd|rd|th)\b"#) {
            guard let day = scan.group(m, 2).flatMap({ Int($0) }), (1...31).contains(day) else { continue }
            var candidate = today
            var found: Date?
            for _ in 0..<3 {
                let comps = cal.dateComponents([.year, .month], from: candidate)
                if let y = comps.year, let mo = comps.month, let d = math.makeDate(year: y, month: mo, day: day), d >= today {
                    found = d
                    break
                }
                candidate = math.firstDayOfNextMonth(after: candidate)
            }
            if let found { apply(found, m, before: isBefore(m)) }
        }

        guard !hits.isEmpty else { return nil }
        let ordered = hits.sorted { $0.location < $1.location }
        let distinct = Set(ordered.map { math.startOfDay($0.date) })
        if distinct.count > 1 {
            ambiguities.append(CaptureAmbiguity(field: .date, message: "More than one date mentioned — using \(RelativeDateText.mediumDate(ordered[0].date, calendar: cal))."))
        }
        return ordered[0]
    }

    private static func resolveCalendarDate(month: Int, day: Int, year: Int?, today: Date, math: DateMath,
                                            ambiguities: inout [CaptureAmbiguity]) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let currentYear = math.calendar.component(.year, from: today)
        if let year {
            return math.makeDate(year: year, month: month, day: day)
        }
        guard let thisYear = math.makeDate(year: currentYear, month: month, day: day) else { return nil }
        if thisYear >= today { return thisYear }
        // A date that already passed this year — most likely next year, but say so.
        let next = math.makeDate(year: currentYear + 1, month: month, day: day)
        if let next {
            ambiguities.append(CaptureAmbiguity(field: .date, message: "That date already passed this year — set to \(RelativeDateText.mediumDate(next, calendar: math.calendar))."))
        }
        return next
    }
}
