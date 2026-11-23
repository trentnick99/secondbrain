import Foundation

/// On-device natural-language interpreter for Quick Capture.
///
/// Turns "Check with John tomorrow about his schedule." into a structured suggestion
/// (title, person, department, due date, reminder, category, priority, quadrant, recurrence).
/// It never silently invents dates, people or commitments: every guess is reported as a
/// `CaptureAmbiguity`, and the UI shows the interpretation for confirmation.
public struct NaturalLanguageParser: Sendable {
    public init() {}

    private static let prefixPatterns: [(String, CaptureKind)] = [
        (#"^(?:please\s+)?remind\s+me\s+(?:to\s+)?"#, .reminder),
        (#"^(?:don'?t|don’t|do\s+not)\s+forget\s+(?:to\s+)?"#, .reminder),
        (#"^(?:notes?)\s*[:\-–]\s*"#, .note),
        (#"^idea\s*[:\-–]\s*"#, .idea),
        (#"^(?:meeting(?:\s+notes)?|mtg)\s*[:\-–]\s*"#, .meetingNote),
        (#"^(?:issue|problem)\s*[:\-–]\s*"#, .issue),
        (#"^(?:todo|to-do|task)\s*[:\-–]\s*"#, .task),
        (#"^(?:follow[ -]?up|f/u)\s*[:\-–]\s*"#, .followUp)
    ]

    public func parse(_ input: String, context: CaptureContext) -> ParsedCapture {
        let normalized = Self.normalizeWhitespace(input)
        let scan = CaptureScan(normalized)
        let math = DateMath(calendar: context.calendar)
        let cal = context.calendar
        var ambiguities: [CaptureAmbiguity] = []
        var notes: [String] = []

        // 1. Explicit prefixes ("remind me to", "note:", "idea:")
        var explicitKind: CaptureKind?
        for (pattern, kind) in Self.prefixPatterns {
            if let m = scan.firstMatch(pattern) {
                scan.consume(m.range, recordPhrase: false)
                explicitKind = kind
                break
            }
        }

        // 2. Schedule phrases ("next shift" first, so "next" isn't read as a weekday modifier)
        var nextShiftDay: Date?
        if let schedule = context.schedule,
           let m = scan.firstMatch(#"\b(?:on\s+|at\s+the\s+start\s+of\s+|by\s+)?(?:my\s+|the\s+)?next\s+shift\b"#) {
            scan.consume(m.range)
            let day = schedule.nextWorkday(after: context.now, calendar: cal)
            nextShiftDay = day
            notes.append("“next shift” → \(RelativeDateText.dayLabel(for: day, now: context.now, calendar: cal))")
        }
        let recurrence = ScheduleExtraction.recurrence(scan, context, &ambiguities)
        let time = ScheduleExtraction.time(scan, context, &ambiguities, &notes)
        let dateHit = ScheduleExtraction.date(scan, context, &ambiguities, &notes)

        // 3. People and department
        let people = PeopleExtraction.extract(scan, context)
        let primary = people.first
        let department = DepartmentLexicon.match(in: normalized)

        let delegate = Self.detectDelegation(scan: scan, people: people)

        // 4. Kind (a hand-off is a task you're waiting on, not a follow-up you owe)
        let lower = " " + normalized.lowercased() + " "
        var kind = explicitKind ?? Self.inferKind(text: normalized, lower: lower, hasPerson: primary != nil)
        if delegate != nil && explicitKind == nil && kind == .followUp { kind = .task }

        // 5. Category and priority
        let category = Self.inferCategory(lower: lower, kind: kind)
        let priority = Self.inferPriority(text: normalized, lower: lower)

        // 6. Due date / time
        var dueDate: Date?
        var hasDueTime = false
        var recurrenceMinutes: Int?
        var reminderDate: Date?
        var reminderSource: ReminderSource = .none
        let today = math.startOfDay(context.now)

        if let recurrence {
            recurrenceMinutes = time?.minutes ?? recurrence.timeMinutes
            let startDay = dateHit.map { math.startOfDay($0.date) } ?? today
            if var first = recurrence.rule.firstOccurrence(onOrAfter: startDay, anchor: startDay, calendar: cal) {
                if let minutes = recurrenceMinutes {
                    var candidate = math.date(on: first, minutes: minutes)
                    if candidate < context.now, let next = recurrence.rule.nextOccurrence(after: first, anchor: startDay, calendar: cal) {
                        first = next
                        candidate = math.date(on: next, minutes: minutes)
                    }
                    dueDate = candidate
                    hasDueTime = true
                } else {
                    dueDate = first
                }
            }
        } else if let absolute = time?.absolute {
            dueDate = absolute
            hasDueTime = true
            reminderDate = absolute
            reminderSource = .relative
        } else if let anchor = time?.shiftAnchor, let schedule = context.schedule {
            // "by end of shift", "first thing" — follow the schedule for that day.
            func minutes(on day: Date) -> Int {
                anchor == .end
                    ? schedule.endMinutes(on: day, calendar: cal, fallback: context.shiftEndMinutes)
                    : schedule.startMinutes(on: day, calendar: cal, fallback: context.shiftStartMinutes)
            }
            if let explicitDay = dateHit?.date ?? nextShiftDay {
                let day = math.startOfDay(explicitDay)
                dueDate = math.date(on: day, minutes: minutes(on: day))
            } else {
                var day = schedule.currentOrNextWorkday(context.now, calendar: cal)
                if math.date(on: day, minutes: minutes(on: day)) <= context.now {
                    day = schedule.nextWorkday(after: day, calendar: cal)
                }
                dueDate = math.date(on: day, minutes: minutes(on: day))
            }
            hasDueTime = true
        } else if let minutes = time?.minutes {
            if let explicitDay = dateHit?.date ?? nextShiftDay {
                dueDate = math.date(on: explicitDay, minutes: minutes)
            } else if time?.impliesToday == true {
                dueDate = math.date(on: today, minutes: minutes)
            } else {
                let candidate = math.date(on: today, minutes: minutes)
                if candidate > context.now {
                    dueDate = candidate
                } else {
                    let tomorrow = math.date(on: math.addingDays(1, to: today), minutes: minutes)
                    dueDate = tomorrow
                    ambiguities.append(CaptureAmbiguity(field: .time, message: "\(RelativeDateText.timeText(candidate, calendar: cal)) already passed today — set for tomorrow."))
                }
            }
            hasDueTime = true
        } else if let dateHit {
            dueDate = math.startOfDay(dateHit.date)
        } else if let nextShiftDay {
            dueDate = nextShiftDay
        }

        if let due = dueDate, let schedule = context.schedule, recurrence == nil,
           !schedule.isWorkday(due, calendar: cal), !(time?.absolute != nil) {
            notes.append("Heads up: you're off \(RelativeDateText.dayLabel(for: due, now: context.now, calendar: cal)) on your schedule.")
        }

        if let due = dueDate, hasDueTime, due < context.now, reminderSource != .relative {
            ambiguities.append(CaptureAmbiguity(field: .time, message: "That time has already passed."))
        }

        // 7. Reminder
        if reminderSource == .none, let due = dueDate {
            if hasDueTime {
                if due > context.now {
                    reminderDate = due
                    reminderSource = .explicitTime
                }
            } else if var defaultMinutes = context.defaultReminderMinutes {
                if context.defaultReminderAtShiftStart, let shift = context.schedule?.shift(on: due, calendar: cal) {
                    defaultMinutes = shift.startMinutes
                }
                let candidate = math.date(on: due, minutes: defaultMinutes)
                if candidate > context.now {
                    reminderDate = candidate
                    reminderSource = .defaultTime
                    notes.append("Reminder at \(RelativeDateText.timeText(candidate, calendar: cal)) (your default)")
                }
            }
        }
        if kind == .reminder && dueDate == nil {
            ambiguities.append(CaptureAmbiguity(field: .time, message: "When should I remind you? Add a date or time."))
        }

        // 8. People ambiguity
        var associateName: String?
        var associateIsKnown = false
        var associateIsRole = false
        if let primary {
            associateName = primary.name
            associateIsKnown = primary.isKnown
            associateIsRole = primary.isRole
            if !primary.isKnown {
                let message = primary.isRole
                    ? "“\(primary.name)” isn't in Associates yet — it will be added as a contact."
                    : "“\(primary.name)” isn't in Associates yet — a new associate will be added."
                ambiguities.append(CaptureAmbiguity(field: .person, message: message))
            }
            if people.count > 1 {
                let names = people.map(\.name).joined(separator: ", ")
                ambiguities.append(CaptureAmbiguity(field: .person, message: "Several people mentioned (\(names)) — linked to \(primary.name)."))
            }
        }

        // 9. Title and details
        var (title, details) = Self.buildTitle(from: scan.remainingText())
        if title.isEmpty {
            title = Self.capitalizeFirst(normalized.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!")))
            if !normalized.isEmpty {
                ambiguities.append(CaptureAmbiguity(field: .kind, message: "Add a few words describing what needs to happen."))
            }
        }

        if let delegate {
            notes.append("Hand-off to \(delegate.name) — shows as waiting until they confirm.")
        }

        var request: String?
        var commitment: String?
        if kind == .followUp {
            request = title
            commitment = details.isEmpty ? nil : details
        }

        // 10. Classification
        let classification = EisenhowerClassifier.classify(ClassificationInput(
            text: normalized,
            category: category,
            kind: kind.taskKind ?? .task,
            priority: priority,
            dueDate: dueDate,
            hasDueTime: hasDueTime,
            now: context.now,
            calendar: cal
        ))

        return ParsedCapture(
            rawText: input,
            title: title,
            details: details,
            kind: kind,
            associateName: associateName,
            associateIsKnown: associateIsKnown,
            associateIsRole: associateIsRole,
            department: department,
            dueDate: dueDate,
            hasDueTime: hasDueTime,
            reminderDate: reminderDate,
            reminderSource: reminderSource,
            category: category,
            priority: priority,
            classification: classification,
            recurrence: recurrence?.rule,
            recurrenceTimeMinutes: recurrenceMinutes,
            ambiguities: Self.dedupe(ambiguities),
            notes: notes,
            matchedPhrases: scan.phrases,
            request: request,
            commitment: commitment,
            delegateTo: delegate?.name,
            delegateIsKnown: delegate?.isKnown ?? false
        )
    }

    // MARK: - Delegation

    /// "have Maria zone aisle 5", "ask the fresh TL to check dates", "delegate this to Jordan",
    /// "tell my TLs to work the truck". The target must be a person or role the parser found.
    static func detectDelegation(scan: CaptureScan, people: [PersonHit]) -> PersonHit? {
        guard !people.isEmpty else { return nil }
        let text = scan.text
        let ns = scan.ns
        let determiner = #"(?:the\s+|my\s+|our\s+)?"#
        let patterns: [(String, Bool)] = [
            (#"\b(?:delegate|assign|hand\s+off|hand)\b[^.!?]{0,60}?\bto\s+"# + determiner + #"(\S)"#, false),
            (#"\b(?:give|pass)\s+(?:this|it|that)\s+(?:off\s+)?to\s+"# + determiner + #"(\S)"#, false),
            (#"\b(?:have|get)\s+"# + determiner + #"(\S)"#, false),
            (#"\b(?:ask|tell)\s+"# + determiner + #"(\S)"#, true)
        ]
        for (pattern, needsTo) in patterns {
            guard let regex = Lexicon.regex(pattern, caseInsensitive: true) else { continue }
            for m in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                let target = m.range(at: 1).location
                guard let hit = people.first(where: { $0.location == target }) else { continue }
                let rest = ns.substring(from: target)
                if needsTo {
                    // "ask Maria to zone…" (a request), not "ask Maria about her schedule" (a follow-up).
                    guard Lexicon.regex(#"^\S+(?:\s+(?:[A-Z]\S*|TLs?|coach(?:es)?|leads?|manager))*\s+to\s+[a-z]"#, caseInsensitive: false)?
                        .firstMatch(in: rest, options: [], range: NSRange(location: 0, length: (rest as NSString).length)) != nil
                    else { continue }
                } else if pattern.contains("have|get") {
                    // "have Maria zone…" — not "get Maria's schedule" / "have John about…".
                    if Lexicon.regex(#"^\S+(?:['’]s\b|\s+(?:about|with|on|for)\b)"#, caseInsensitive: true)?
                        .firstMatch(in: rest, options: [], range: NSRange(location: 0, length: (rest as NSString).length)) != nil { continue }
                }
                return hit
            }
        }
        return nil
    }

    // MARK: - Inference helpers

    static func inferKind(text: String, lower: String, hasPerson: Bool) -> CaptureKind {
        let firstWord = text.split(whereSeparator: { $0 == " " }).first.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
        if hasPerson && Lexicon.containsAny(lower, Lexicon.followUpPhrases) { return .followUp }
        if Lexicon.containsAny(lower, Lexicon.issueWords) && !Lexicon.actionStartVerbs.contains(firstWord) { return .issue }
        return .task
    }

    static func inferCategory(lower: String, kind: CaptureKind) -> TaskCategory {
        var best: (TaskCategory, Int)?
        for (category, words) in Lexicon.categoryKeywords {
            var score = Lexicon.countMatches(lower, words)
            if category.isSafetyCritical { score *= 2 }
            guard score > 0 else { continue }
            if let current = best {
                if score > current.1 { best = (category, score) }
            } else {
                best = (category, score)
            }
        }
        if let best { return best.0 }
        switch kind {
        case .followUp: return .people
        case .issue: return .operations
        case .meetingNote: return .meeting
        default: return .general
        }
    }

    static func inferPriority(text: String, lower: String) -> TaskPriority {
        if Lexicon.containsAny(lower, Lexicon.criticalWords) { return .critical }
        if Lexicon.containsAny(lower, Lexicon.highWords) || text.contains("!!") { return .high }
        if Lexicon.containsAny(lower, Lexicon.lowValueWords) { return .low }
        return .normal
    }

    // MARK: - Text helpers

    static func normalizeWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func buildTitle(from remaining: String) -> (String, String) {
        var text = normalizeWhitespace(remaining)
        // Remove spaces left before punctuation and empty punctuation runs.
        if let regex = Lexicon.regex(#"\s+([.,!?;:])"#) {
            let ns = text as NSString
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
        }
        if let regex = Lexicon.regex(#"([,;:])\s*([.!?])"#) {
            let ns = text as NSString
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "$2")
        }
        let sentences = splitSentences(text).map(cleanFragment).filter { !$0.isEmpty }
        guard let first = sentences.first else { return ("", "") }
        let title = capitalizeFirst(first.trimmingCharacters(in: CharacterSet(charactersIn: ".!?")))
        let rest = sentences.dropFirst().map { s -> String in
            let c = capitalizeFirst(s)
            if let last = c.last, ".!?".contains(last) { return c }
            return c + "."
        }.joined(separator: " ")
        return (title, rest)
    }

    static func splitSentences(_ text: String) -> [String] {
        guard let regex = Lexicon.regex(#"(?<=[.!?])\s+"#) else { return [text] }
        let ns = text as NSString
        var parts: [String] = []
        var start = 0
        for m in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: start))
        return parts
    }

    static func cleanFragment(_ fragment: String) -> String {
        var s = fragment.trimmingCharacters(in: .whitespaces)
        let leading = #"^(?:to|on|by|at|for|and|then|also|,|-|–)\s+"#
        let trailing = #"\s+(?:on|by|at|before|for|due|until|this|next|in|every|each|to|and|then|from|starting|of)$"#
        var changed = true
        while changed {
            changed = false
            for pattern in [leading, trailing] {
                if let regex = Lexicon.regex(pattern) {
                    let ns = s as NSString
                    let replaced = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
                    if replaced != s { s = replaced; changed = true }
                }
            }
            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–"))
            if trimmed != s { s = trimmed; changed = true }
            // A trailing "." directly after a dangling word: "cleaned up by." → "cleaned up"
            if s.hasSuffix("."), let regex = Lexicon.regex(#"\s+(?:on|by|at|before|for|due|until|this|next|in|to)\.$"#) {
                let ns = s as NSString
                let replaced = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: ".")
                if replaced != s { s = replaced; changed = true }
            }
        }
        return s
    }

    static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    static func dedupe(_ items: [CaptureAmbiguity]) -> [CaptureAmbiguity] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
