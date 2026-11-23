import Foundation

/// The "End My Shift" review. It only *describes* — carrying forward or rescheduling
/// always requires an explicit action, and nothing unfinished is ever discarded.
public struct ShiftReview: Sendable {
    public var date: Date
    public var completedToday: [TaskSnapshot]
    public var unfinishedToday: [TaskSnapshot]
    public var overdue: [TaskSnapshot]
    public var outstandingCommitments: [TaskSnapshot]
    public var awaitingConfirmation: [TaskSnapshot]
    public var upcomingDeadlines: [TaskSnapshot]
    public var importantQ2: [TaskSnapshot]
    public var suggestedTomorrow: [TaskSnapshot]

    /// Unfinished + overdue items, de-duplicated — the ones you might carry into tomorrow.
    public var carryForwardCandidates: [TaskSnapshot] {
        var seen = Set<UUID>()
        return (overdue + unfinishedToday).filter { seen.insert($0.id).inserted }
    }

    public var totalOpenForToday: Int { carryForwardCandidates.count }

    public static func build(tasks: [TaskSnapshot], now: Date, calendar: Calendar) -> ShiftReview {
        let math = DateMath(calendar: calendar)
        let today = math.startOfDay(now)
        let tomorrow = math.addingDays(1, to: today)
        let open = tasks.filter { $0.isOpen }

        let completedToday = tasks.filter { t in
            guard t.status == .completed, let done = t.completedAt else { return false }
            return math.isSameDay(done, now)
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        let overdue = open.filter { t in
            guard let due = t.dueDate else { return false }
            return math.startOfDay(due) < today
        }.sortedByDue()
        let overdueIDs = Set(overdue.map(\.id))

        let unfinishedToday = open.filter { t in
            if overdueIDs.contains(t.id) { return false }
            if let due = t.dueDate, math.isSameDay(due, today) { return true }
            if let focus = t.focusDate, math.isSameDay(focus, today) { return true }
            return false
        }.sortedForDisplay()

        let outstandingCommitments = open.filter { $0.kind == .followUp }.sortedByDue()
        let awaitingConfirmation = open.filter { $0.isAwaitingConfirmation }.sortedByDue()

        let horizon = math.addingDays(4, to: today)
        let upcomingDeadlines = open.filter { t in
            guard let due = t.dueDate else { return false }
            return due >= tomorrow && due < horizon
        }.sortedByDue()

        let importantQ2 = Array(open.filter { $0.quadrant == .schedule }.sortedByDue().prefix(5))
        let suggestedTomorrow = PriorityRanker.suggestions(from: open, for: tomorrow, now: now, calendar: calendar, limit: 3)

        return ShiftReview(
            date: today,
            completedToday: completedToday,
            unfinishedToday: unfinishedToday,
            overdue: overdue,
            outstandingCommitments: outstandingCommitments,
            awaitingConfirmation: awaitingConfirmation,
            upcomingDeadlines: upcomingDeadlines,
            importantQ2: importantQ2,
            suggestedTomorrow: suggestedTomorrow
        )
    }
}
