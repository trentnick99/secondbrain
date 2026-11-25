import Foundation

/// Preferences that shape which local notifications are scheduled.
public struct NotificationPreferences: Equatable, Sendable {
    public var remindersEnabled: Bool
    public var deadlineAlertsEnabled: Bool
    public var overdueAlertsEnabled: Bool
    public var dailyBriefingEnabled: Bool
    /// Minutes after midnight for the daily briefing (usually shift start).
    public var briefingMinutes: Int
    /// Minutes after midnight when the shift ends; date-only items still open then get an overdue nudge.
    public var shiftEndMinutes: Int
    /// How long after a timed deadline the "still open" alert fires.
    public var overdueGraceMinutes: Int
    /// Hide task titles on the lock screen.
    public var hidePreviews: Bool
    /// iOS keeps at most 64 pending local notifications per app; stay safely below that.
    public var maxPending: Int
    /// How many days of daily briefings to schedule ahead.
    public var briefingDaysAhead: Int
    /// When set, briefings go out only on workdays at that day's shift start, and "still open"
    /// nudges for date-only items fire at that day's shift end.
    public var schedule: ShiftSchedule?

    public init(remindersEnabled: Bool = true,
                deadlineAlertsEnabled: Bool = true,
                overdueAlertsEnabled: Bool = true,
                dailyBriefingEnabled: Bool = true,
                briefingMinutes: Int = 7 * 60,
                shiftEndMinutes: Int = 16 * 60,
                overdueGraceMinutes: Int = 60,
                hidePreviews: Bool = false,
                maxPending: Int = 60,
                briefingDaysAhead: Int = 7,
                schedule: ShiftSchedule? = nil) {
        self.remindersEnabled = remindersEnabled
        self.deadlineAlertsEnabled = deadlineAlertsEnabled
        self.overdueAlertsEnabled = overdueAlertsEnabled
        self.dailyBriefingEnabled = dailyBriefingEnabled
        self.briefingMinutes = briefingMinutes
        self.shiftEndMinutes = shiftEndMinutes
        self.overdueGraceMinutes = overdueGraceMinutes
        self.hidePreviews = hidePreviews
        self.maxPending = max(1, min(64, maxPending))
        self.briefingDaysAhead = max(0, min(14, briefingDaysAhead))
        self.schedule = schedule
    }
}

/// A local notification the app intends to have pending. The app diffs this plan against
/// what iOS has pending, so the plan is the single source of truth.
public struct PlannedNotification: Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case reminder, deadline, overdue, briefing
    }

    public var id: String
    public var kind: Kind
    public var taskID: UUID?
    public var fireDate: Date
    public var title: String
    public var body: String
    /// Groups notifications in Notification Center.
    public var threadID: String
    /// Reminders and deadlines carry task actions (Complete / Snooze / Open).
    public var hasTaskActions: Bool

    public init(id: String, kind: Kind, taskID: UUID?, fireDate: Date, title: String, body: String,
                threadID: String, hasTaskActions: Bool) {
        self.id = id
        self.kind = kind
        self.taskID = taskID
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.threadID = threadID
        self.hasTaskActions = hasTaskActions
    }

    public static func identifier(kind: Kind, taskID: UUID) -> String { "task.\(taskID.uuidString).\(kind.rawValue)" }

    /// Parses "task.<uuid>.<kind>" identifiers back into a task id.
    public static func taskID(fromIdentifier identifier: String) -> UUID? {
        let parts = identifier.split(separator: ".")
        guard parts.count == 3, parts[0] == "task" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
}

/// Decides which local notifications should be pending right now.
///
/// iOS does not guarantee arbitrary background execution, so the app schedules everything ahead of
/// time with calendar triggers and recomputes this plan whenever data changes, the app becomes
/// active, a notification action runs, or an opportunistic background refresh happens.
public enum NotificationPlanner {
    public static func plan(tasks: [TaskSnapshot], preferences: NotificationPreferences,
                            now: Date, calendar: Calendar) -> [PlannedNotification] {
        let math = DateMath(calendar: calendar)
        var planned: [PlannedNotification] = []

        for task in tasks where task.isOpen {
            let displayTitle = task.title.isEmpty ? "Untitled task" : task.title

            // 1. Explicit reminders.
            if preferences.remindersEnabled, let reminder = task.reminderDate, reminder > now {
                planned.append(PlannedNotification(
                    id: PlannedNotification.identifier(kind: .reminder, taskID: task.id),
                    kind: .reminder,
                    taskID: task.id,
                    fireDate: reminder,
                    title: preferences.hidePreviews ? "Coach Spark reminder" : reminderTitle(for: task, displayTitle: displayTitle),
                    body: preferences.hidePreviews ? "Open Coach Spark to see what's due." : reminderBody(for: task, now: now, calendar: calendar),
                    threadID: task.kind == .followUp ? "followups" : "reminders",
                    hasTaskActions: true
                ))
            }

            guard let due = task.dueDate else { continue }

            // 2. Deadline alert at a timed due date (skipped when a reminder already fires then).
            if preferences.deadlineAlertsEnabled, task.hasDueTime, due > now {
                let reminderCoversDeadline = task.reminderDate.map { abs($0.timeIntervalSince(due)) < 60 } ?? false
                if !reminderCoversDeadline || !preferences.remindersEnabled {
                    planned.append(PlannedNotification(
                        id: PlannedNotification.identifier(kind: .deadline, taskID: task.id),
                        kind: .deadline,
                        taskID: task.id,
                        fireDate: due,
                        title: preferences.hidePreviews ? "Something is due" : "Due now",
                        body: preferences.hidePreviews ? "Open Coach Spark to see what's due." : displayTitle,
                        threadID: "deadlines",
                        hasTaskActions: true
                    ))
                }
            }

            // 3. "Still open" nudge after the deadline passes.
            if preferences.overdueAlertsEnabled {
                let fire: Date
                if task.hasDueTime {
                    fire = math.addingMinutes(preferences.overdueGraceMinutes, to: due)
                } else {
                    let end = preferences.schedule?.endMinutes(on: due, calendar: calendar, fallback: preferences.shiftEndMinutes)
                        ?? preferences.shiftEndMinutes
                    fire = math.date(on: due, minutes: end)
                }
                if fire > now {
                    let whenText = task.hasDueTime
                        ? "Was due \(RelativeDateText.timeText(due, calendar: calendar))"
                        : "Due today and still open at end of shift"
                    planned.append(PlannedNotification(
                        id: PlannedNotification.identifier(kind: .overdue, taskID: task.id),
                        kind: .overdue,
                        taskID: task.id,
                        fireDate: fire,
                        title: preferences.hidePreviews ? "An item is still open" : "Still open: \(displayTitle)",
                        body: preferences.hidePreviews ? "Open Coach Spark to review." : whenText,
                        threadID: "overdue",
                        hasTaskActions: true
                    ))
                }
            }
        }

        // 4. Daily briefings, with counts as currently known (recomputed on every change).
        if preferences.dailyBriefingEnabled {
            let today = math.startOfDay(now)
            for offset in 0..<max(preferences.briefingDaysAhead, 0) {
                let day = math.addingDays(offset, to: today)
                var startMinutes = preferences.briefingMinutes
                if let schedule = preferences.schedule {
                    guard let shift = schedule.shift(on: day, calendar: calendar) else { continue }   // day off
                    startMinutes = shift.startMinutes
                }
                let fire = math.date(on: day, minutes: startMinutes)
                guard fire > now else { continue }
                let agenda = DayAgenda.build(tasks: tasks, day: day, now: fire, calendar: calendar)
                let counts = BriefingBuilder.countsLine(agenda)
                let body: String
                if preferences.hidePreviews {
                    body = "Tap to review today's priorities."
                } else if let primary = agenda.primaryTask {
                    body = "\(counts). First up: \(primary.title)"
                } else {
                    body = "\(counts). Tap to plan your shift."
                }
                planned.append(PlannedNotification(
                    id: "briefing.\(dayKey(day, calendar: calendar))",
                    kind: .briefing,
                    taskID: nil,
                    fireDate: fire,
                    title: "\(BriefingBuilder.greeting(now: fire, calendar: calendar)) — your daily briefing",
                    body: body,
                    threadID: "briefing",
                    hasTaskActions: false
                ))
            }
        }

        // Earliest first; task notifications win ties over briefings.
        let sorted = planned.sorted { a, b in
            if a.fireDate != b.fireDate { return a.fireDate < b.fireDate }
            if (a.kind == .briefing) != (b.kind == .briefing) { return a.kind != .briefing }
            return a.id < b.id
        }
        return Array(sorted.prefix(preferences.maxPending))
    }

    static func reminderTitle(for task: TaskSnapshot, displayTitle: String) -> String {
        switch task.kind {
        case .followUp:
            if let name = task.associateName, !name.isEmpty { return "Follow up with \(name)" }
            return "Follow-up"
        case .issue: return "Operational issue"
        case .reminder, .task: return displayTitle
        }
    }

    static func reminderBody(for task: TaskSnapshot, now: Date, calendar: Calendar) -> String {
        var parts: [String] = []
        if task.kind == .followUp || task.kind == .issue { parts.append(task.title) }
        if let due = task.dueDate {
            parts.append(RelativeDateText.dueText(due: due, hasTime: task.hasDueTime, now: now, calendar: calendar))
        }
        if task.quadrant == .doFirst { parts.append("Q1 · Do First") }
        if parts.isEmpty { return "Tap to open, or swipe for quick actions." }
        return parts.joined(separator: " · ")
    }

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
