import Foundation

/// Everything the dashboard, daily planner, widgets and Siri need to describe a day.
public struct DayAgenda: Sendable {
    public var day: Date
    public var topPriorities: [TaskSnapshot]
    public var overdue: [TaskSnapshot]
    public var dueToday: [TaskSnapshot]
    public var followUpsDue: [TaskSnapshot]
    public var urgentImportant: [TaskSnapshot]
    public var scheduledImportant: [TaskSnapshot]
    public var upcomingReminders: [TaskSnapshot]
    public var tomorrow: [TaskSnapshot]
    public var restOfWeek: [TaskSnapshot]
    public var recurring: [TaskSnapshot]
    public var completedToday: [TaskSnapshot]
    public var inbox: [TaskSnapshot]
    public var waiting: [TaskSnapshot]
    public var openCount: Int
    public var suggestedPriorities: [TaskSnapshot]

    /// Count shown on badges / lock screen: overdue + Q1 + due-today critical items.
    public var priorityCount: Int {
        Set((overdue + urgentImportant).map(\.id)).count
    }

    /// The single most important open item for the day.
    public var primaryTask: TaskSnapshot? {
        topPriorities.first ?? suggestedPriorities.first
    }

    public var nextReminder: TaskSnapshot? { upcomingReminders.first }

    public static func build(tasks: [TaskSnapshot], day: Date, now: Date, calendar: Calendar) -> DayAgenda {
        let math = DateMath(calendar: calendar)
        let dayStart = math.startOfDay(day)
        let dayEnd = math.startOfNextDay(day)
        let tomorrowStart = dayEnd
        let tomorrowEnd = math.addingDays(1, to: tomorrowStart)
        let weekEnd = math.addingDays(7, to: dayStart)

        let open = tasks.filter { $0.isOpen }
        let active = open.filter { $0.status != .deferred || $0.dueDate != nil }

        func dueDay(_ t: TaskSnapshot) -> Date? { t.dueDate.map { math.startOfDay($0) } }

        let overdue = active.filter { t in
            guard let d = dueDay(t) else { return false }
            if math.isSameDay(dayStart, now), t.hasDueTime, let due = t.dueDate { return due < now && d <= dayStart }
            return d < dayStart
        }.sortedByDue()
        let overdueIDs = Set(overdue.map(\.id))

        let dueToday = active.filter { t in
            guard let due = t.dueDate, !overdueIDs.contains(t.id) else { return false }
            return due >= dayStart && due < dayEnd
        }.sortedForDisplay()

        let followUpsDue = active.filter { t in
            guard t.kind == .followUp, let due = t.dueDate else { return false }
            return due < dayEnd
        }.sortedByDue()

        let urgentImportant = active.filter { t in
            guard t.quadrant == .doFirst else { return false }
            guard let due = t.dueDate else { return true }
            return due < dayEnd || math.daysBetween(dayStart, due) <= 1
        }.sortedForDisplay()

        let scheduledImportant = active.filter { $0.quadrant == .schedule }
            .sortedByDue()

        let horizon = now.addingTimeInterval(24 * 3600)
        let upcomingReminders = open.filter { t in
            guard let r = t.reminderDate else { return false }
            return r >= now && r <= max(horizon, dayEnd)
        }.sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }

        let tomorrow = active.filter { t in
            guard let due = t.dueDate else { return false }
            return due >= tomorrowStart && due < tomorrowEnd
        }.sortedForDisplay()

        let restOfWeek = active.filter { t in
            guard let due = t.dueDate else { return false }
            return due >= tomorrowEnd && due < weekEnd
        }.sortedByDue()

        let recurring = active.filter { t in
            guard t.isRecurring, let due = t.dueDate else { return false }
            return due < weekEnd
        }.sortedByDue()

        let completedToday = tasks.filter { t in
            guard t.status == .completed, let done = t.completedAt else { return false }
            return done >= dayStart && done < dayEnd
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        let topPriorities = open.filter { t in
            guard let f = t.focusDate else { return false }
            return math.isSameDay(f, dayStart)
        }.sortedForDisplay()

        let inbox = open.filter { $0.status == .inbox }.sorted { $0.createdAt > $1.createdAt }
        let waiting = open.filter { $0.isAwaitingConfirmation }.sortedByDue()

        let suggestions = PriorityRanker.suggestions(from: open, for: dayStart, now: now, calendar: calendar, limit: 3)

        return DayAgenda(
            day: dayStart,
            topPriorities: topPriorities,
            overdue: overdue,
            dueToday: dueToday,
            followUpsDue: followUpsDue,
            urgentImportant: urgentImportant,
            scheduledImportant: scheduledImportant,
            upcomingReminders: upcomingReminders,
            tomorrow: tomorrow,
            restOfWeek: restOfWeek,
            recurring: recurring,
            completedToday: completedToday,
            inbox: inbox,
            waiting: waiting,
            openCount: open.count,
            suggestedPriorities: suggestions
        )
    }
}
