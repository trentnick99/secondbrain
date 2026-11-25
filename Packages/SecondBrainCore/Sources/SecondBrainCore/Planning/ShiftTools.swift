import Foundation

// MARK: - Huddle

/// A 5-minute huddle: safety, yesterday, today's top three, shout-outs and questions.
public struct HuddleScript: Equatable, Sendable {
    public struct Section: Equatable, Sendable, Identifiable {
        public let title: String
        public let lines: [String]
        public var id: String { title }
    }

    public let heading: String
    public let sections: [Section]

    public var text: String {
        ([heading] + sections.map { section in
            "\n" + section.title.uppercased() + "\n" + section.lines.map { "• " + $0 }.joined(separator: "\n")
        }).joined(separator: "\n")
    }
}

public enum Huddle {
    public static let safetyTips = [
        "Keep fire exits, extinguishers and electrical panels clear, even during a freight push.",
        "Clean up or guard a spill right away. Never walk past one.",
        "Use a ladder to reach high, never shelving or carts.",
        "Only trained, authorized associates use powered equipment.",
        "Lift with your legs, keep loads close, and get help with heavy or awkward items.",
        "Keep pallets and freight out of Action Alley and the main aisles while customers shop.",
        "Use safety box cutters the right way: cut away from your body and retract the blade.",
        "Watch for customers and kids around pallet jacks and carts, and slow down at corners.",
        "Tag damaged equipment out of service and report it.",
        "Stack top stock safely: heavy items low, nothing hanging over the edge.",
        "Know where the first aid kit and AED are, and how to report an injury.",
        "Drink water and take your breaks."
    ]

    /// Today's safety message: seasonal when it matters, otherwise rotating daily. `offset` picks another one.
    public static func safetyTip(now: Date, calendar: Calendar, offset: Int = 0) -> String {
        if offset == 0 {
            let blackFriday = RetailCalendar.nextDate(of: .blackFriday, onOrAfter: calendar.startOfDay(for: now), calendar: calendar)
            if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: blackFriday).day, days <= 7 {
                return "Black Friday is close: keep exits and Action Alley clear, set lines up away from the entrances, and know your spot in the event plan."
            }
            let month = calendar.component(.month, from: now)
            if [12, 1, 2].contains(month) {
                return "Wet floors at the entrances: keep mats flat and wet-floor signs out when it's raining or snowing."
            }
            if [6, 7, 8].contains(month) {
                return "Heat: drink water and take breaks, especially in the garden center, the lot and the backroom."
            }
        }
        let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        return safetyTips[(day + offset) % safetyTips.count]
    }

    public static func build(tasks: [TaskSnapshot], role: UserRole?, now: Date, calendar: Calendar,
                             safetyOffset: Int = 0, shoutOuts: String = "") -> HuddleScript {
        let shareable: (TaskSnapshot) -> Bool = { $0.associateName == nil && $0.kind != .followUp }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let doneYesterday = tasks.filter { task in
            guard let done = task.completedAt, shareable(task) else { return false }
            return calendar.isDate(done, inSameDayAs: yesterday)
        }
        let top = topThree(tasks: tasks, now: now, calendar: calendar)

        let heading = "Huddle · " + RelativeDateText.mediumDate(now, calendar: calendar)
            + " · " + RetailCalendar.fiscalWeekLabel(for: now, calendar: calendar)
        var sections = [HuddleScript.Section(title: "Safety", lines: [safetyTip(now: now, calendar: calendar, offset: safetyOffset)])]
        sections.append(.init(title: "Yesterday", lines: doneYesterday.isEmpty
            ? ["Fresh start today."]
            : ["\(doneYesterday.count) thing\(doneYesterday.count == 1 ? "" : "s") done"] + doneYesterday.prefix(3).map(\.title)))
        sections.append(.init(title: "Today's top three", lines: top.isEmpty
            ? ["No priorities set yet. Pick three before the huddle."]
            : top.map { task in
                var line = task.title
                if let owner = task.delegatedTo, !owner.isEmpty { line += " (\(owner))" }
                if task.category == .safety { line += " (safety)" }
                return line
            }))
        let shouts = shoutOuts.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        sections.append(.init(title: "Shout-outs", lines: shouts.isEmpty ? ["Who went above and beyond?"] : shouts))
        sections.append(.init(title: "Questions", lines: ["Anyone need help or have a question?"]))
        return HuddleScript(heading: heading, sections: sections)
    }

    /// Open priorities for today: chosen priorities, then overdue, then Do First, then suggestions.
    public static func topThree(tasks: [TaskSnapshot], now: Date, calendar: Calendar) -> [TaskSnapshot] {
        let agenda = DayAgenda.build(tasks: tasks, day: now, now: now, calendar: calendar)
        var seen = Set<UUID>()
        return (agenda.topPriorities + agenda.overdue + agenda.urgentImportant + agenda.suggestedPriorities)
            .filter { $0.isOpen && seen.insert($0.id).inserted }
            .prefix(3)
            .map { $0 }
    }
}

// MARK: - Shift timeline

/// One block of the shift plan, placed relative to the start of the shift.
public struct PlanBlock: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var offsetMinutes: Int
    public var durationMinutes: Int

    public init(id: UUID = UUID(), title: String, offsetMinutes: Int, durationMinutes: Int) {
        self.id = id
        self.title = title
        self.offsetMinutes = offsetMinutes
        self.durationMinutes = durationMinutes
    }
}

public enum ShiftPlan {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let start: Date
        public let end: Date
        public let isTask: Bool
        public let isSafety: Bool
    }

    /// A starting plan for a typical shift; the person edits it to fit their store.
    public static func defaultBlocks(for role: UserRole?, shiftMinutes: Int = 600) -> [PlanBlock] {
        let main: String
        switch role?.primaryArea {
        case "Stocking", "Overnight": main = "Work the freight"
        case "Fresh", "Food": main = "Freight, rotation and holes"
        case "Front End": main = "Coverage and lines"
        case "Digital (OPD)": main = "Pickup and delivery flow"
        case "Fashion": main = "Freight and fitting rooms"
        case "Asset Protection": main = "Floor presence and AP follow-ups"
        case "Auto Care Center (ACC)": main = "Bays and service flow"
        default: main = role?.seesWholeStore == true ? "Walk the store with coaches" : "Main work block"
        }
        let plan: [(String, Int, Int)] = [
            ("Check Home, messages and today's plan", 0, 15),
            ("Huddle", 15, 15),
            ("Floor walk", 30, 30),
            (main, 60, 180),
            ("Lunch", 240, 60),
            ("Follow-ups and one-on-ones", 300, 90),
            ("Second floor walk", 390, 30),
            ("Projects, features and mods", 420, 150)
        ]
        let wrapStart = max(shiftMinutes - 30, 0)
        var blocks = plan.compactMap { title, offset, length -> PlanBlock? in
            guard offset < wrapStart else { return nil }
            return PlanBlock(title: title, offsetMinutes: offset, durationMinutes: min(length, wrapStart - offset))
        }
        blocks.append(PlanBlock(title: "Wrap up and End My Shift", offsetMinutes: wrapStart, durationMinutes: min(30, shiftMinutes)))
        return blocks
    }

    /// Today's timeline: plan blocks inside the shift plus open tasks with a due time during it.
    public static func entries(blocks: [PlanBlock], shiftStart: Date, shiftEnd: Date, tasks: [TaskSnapshot]) -> [Entry] {
        let blockEntries: [Entry] = blocks.compactMap { block in
            let start = shiftStart.addingTimeInterval(TimeInterval(block.offsetMinutes * 60))
            let end = min(start.addingTimeInterval(TimeInterval(max(block.durationMinutes, 5) * 60)), shiftEnd)
            guard start < shiftEnd, end > start else { return nil }
            return Entry(id: "block-\(block.id.uuidString)", title: block.title, start: start, end: end, isTask: false, isSafety: false)
        }
        let taskEntries: [Entry] = tasks.compactMap { task in
            guard task.isOpen, task.hasDueTime, let due = task.dueDate, due >= shiftStart, due < shiftEnd else { return nil }
            return Entry(id: "task-\(task.id.uuidString)", title: task.title, start: due, end: due.addingTimeInterval(15 * 60),
                         isTask: true, isSafety: task.category == .safety)
        }
        return (blockEntries + taskEntries).sorted { $0.start != $1.start ? $0.start < $1.start : (!$0.isTask && $1.isTask) }
    }

    /// The plan block happening now, if any.
    public static func current(_ entries: [Entry], now: Date) -> Entry? {
        entries.last { !$0.isTask && $0.start <= now && now < $0.end }
    }
}

// MARK: - Team lead lists

public enum TeamLists {
    /// Open tasks handed to someone (matched by name, ignoring case).
    public static func tasks(for name: String, in tasks: [TaskSnapshot]) -> [TaskSnapshot] {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return tasks.filter { $0.isOpen && ($0.delegatedTo ?? "").trimmingCharacters(in: .whitespaces).lowercased() == key }
            .sorted { ($0.category == .safety ? 0 : 1, $0.dueDate ?? .distantFuture) < ($1.category == .safety ? 0 : 1, $1.dueDate ?? .distantFuture) }
    }

    /// Everyone with open handed-off work, plus the named leads, with counts.
    public static func people(tasks: [TaskSnapshot], leads: [String]) -> [(name: String, open: Int)] {
        var names: [String: String] = [:]
        for name in leads + tasks.filter(\.isOpen).compactMap(\.delegatedTo) {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            names[trimmed.lowercased()] = names[trimmed.lowercased()] ?? trimmed
        }
        return names.values.map { ($0, self.tasks(for: $0, in: tasks).count) }
            .sorted { $0.open != $1.open ? $0.open > $1.open : $0.name < $1.name }
    }

    /// A plain list to text a team lead: titles and due times only.
    public static func text(for name: String, tasks: [TaskSnapshot], now: Date, calendar: Calendar) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        var lines = ["Hi \(first), here's your list for \(RelativeDateText.mediumDate(now, calendar: calendar)):"]
        for (index, task) in tasks.enumerated() {
            var line = "\(index + 1). \(task.title)"
            if task.category == .safety { line += " (safety)" }
            if let due = task.dueDate {
                line += " · " + RelativeDateText.dueText(due: due, hasTime: task.hasDueTime, now: now, calendar: calendar).lowercased()
            }
            lines.append(line)
        }
        if tasks.isEmpty { lines.append("Nothing on your list right now.") }
        lines.append("Thanks!")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Weekly recap

public enum WeeklyRecap {
    /// A recap to send the store manager. Associate follow-ups appear only as counts.
    public static func text(review: WeeklyReview, role: UserRole?, calendar: Calendar) -> String {
        let shareable: (TaskSnapshot) -> Bool = { $0.associateName == nil && $0.kind != .followUp }
        let done = review.completed.filter(shareable)
        let safetyDone = review.completed.filter { $0.category == .safety || $0.category == .compliance }.count
        let highlights = done.sorted { a, b in
            let aSafe = a.category == .safety || a.category == .compliance
            let bSafe = b.category == .safety || b.category == .compliance
            if aSafe != bSafe { return aSafe }
            return a.quadrant.rawValue < b.quadrant.rawValue
        }
        let overdue = review.overdue.filter(shareable)
        let end = calendar.date(byAdding: .day, value: -1, to: review.weekEnd) ?? review.weekEnd
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        let sameMonth = calendar.component(.month, from: review.weekStart) == calendar.component(.month, from: end)
        let range = formatter.string(from: review.weekStart) + "–"
            + (sameMonth ? String(calendar.component(.day, from: end)) : formatter.string(from: end))
        var lines = ["Week recap · \(RetailCalendar.fiscalWeekLabel(for: review.weekStart, calendar: calendar)) · \(range)"
                     + (role.map { " · \($0.title)" } ?? "")]
        lines.append("")
        lines.append("Done: \(review.completed.count) task\(review.completed.count == 1 ? "" : "s")"
                     + (safetyDone > 0 ? ", including \(safetyDone) safety item\(safetyDone == 1 ? "" : "s")." : "."))
        if !highlights.isEmpty {
            lines.append("Highlights:")
            lines += highlights.prefix(5).map { "• \($0.title)" }
        }
        lines.append("")
        if overdue.isEmpty {
            lines.append("Nothing overdue.")
        } else {
            lines.append("Still open (\(overdue.count) overdue):")
            lines += overdue.prefix(5).map { "• \($0.title)" }
        }
        let followUps = review.followUpsResolved.count + review.followUpsOutstanding.count
        if followUps > 0 {
            lines.append("")
            lines.append("Follow-ups: \(review.followUpsResolved.count) resolved, \(review.followUpsOutstanding.count) still open.")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - What's next

public enum NextUp {
    /// What Siri says for "What's next?": the next timed item today, the top priority, and anything overdue.
    public static func summary(tasks: [TaskSnapshot], now: Date, calendar: Calendar) -> String {
        let open = tasks.filter(\.isOpen)
        let today = calendar.startOfDay(for: now)
        let overdue = open.filter { task in
            guard let due = task.dueDate else { return false }
            return task.hasDueTime ? due < now : due < today
        }
        let nextTimed = open.filter { task in
            guard task.hasDueTime, let due = task.dueDate else { return false }
            return due >= now && calendar.isDate(due, inSameDayAs: now)
        }.min { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let top = Huddle.topThree(tasks: tasks, now: now, calendar: calendar).first { $0.id != nextTimed?.id }

        var parts: [String] = []
        if let nextTimed, let due = nextTimed.dueDate {
            parts.append("Next up at \(RelativeDateText.timeText(due, calendar: calendar)): \(nextTimed.title).")
        }
        let topIsOverdue = top.map { t in overdue.contains { $0.id == t.id } } ?? false
        if let top {
            let label = parts.isEmpty ? "Next up" : "Top priority"
            parts.append(label + (topIsOverdue ? " (overdue): " : ": ") + "\(top.title).")
        }
        let otherOverdue = overdue.filter { $0.id != top?.id }
        if let first = otherOverdue.first {
            parts.append("You also have \(otherOverdue.count) overdue: \(first.title)\(otherOverdue.count > 1 ? ", and more" : "").")
        }
        return parts.isEmpty ? "You're all caught up for today." : parts.joined(separator: " ")
    }
}
