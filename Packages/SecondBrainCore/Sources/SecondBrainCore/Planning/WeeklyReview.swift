import Foundation

/// Weekly review: what got done, what keeps slipping, and what may no longer be needed.
public struct WeeklyReview: Sendable {
    public var weekStart: Date
    public var weekEnd: Date
    public var completed: [TaskSnapshot]
    public var overdue: [TaskSnapshot]
    public var repeatedlyPostponed: [TaskSnapshot]
    public var staleInbox: [TaskSnapshot]
    public var longWaiting: [TaskSnapshot]
    public var eliminationCandidates: [TaskSnapshot]
    public var followUpsOutstanding: [TaskSnapshot]
    public var followUpsResolved: [TaskSnapshot]
    public var quadrantCounts: [Quadrant: Int]
    public var dueThisWeek: Int

    /// Completed ÷ (completed + still-open items that were due this week). Nil when nothing was due.
    public var completionRate: Double? {
        let denominator = completed.count + overdue.filter { $0.dueDate.map { $0 >= weekStart } ?? false }.count
        guard denominator > 0 else { return nil }
        return Double(completed.count) / Double(denominator)
    }

    public static let postponedThreshold = 3

    public static func build(tasks: [TaskSnapshot], now: Date, calendar: Calendar, weekStartsOn: Int) -> WeeklyReview {
        let math = DateMath(calendar: calendar)
        let weekStart = math.startOfWeek(containing: now, firstWeekday: weekStartsOn)
        let weekEnd = math.addingDays(7, to: weekStart)
        let today = math.startOfDay(now)
        let open = tasks.filter { $0.isOpen }

        let completed = tasks.filter { t in
            guard t.status == .completed, let done = t.completedAt else { return false }
            return done >= weekStart && done < weekEnd
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        let overdue = open.filter { t in
            guard let due = t.dueDate else { return false }
            return math.startOfDay(due) < today
        }.sortedByDue()

        let postponed = open.filter { $0.rescheduleCount >= postponedThreshold }
            .sorted { $0.rescheduleCount > $1.rescheduleCount }

        let staleInbox = open.filter { $0.status == .inbox && math.daysBetween($0.createdAt, now) >= 3 }
            .sorted { $0.createdAt < $1.createdAt }

        let longWaiting = open.filter { $0.isAwaitingConfirmation && math.daysBetween($0.updatedAt, now) >= 5 }
            .sorted { $0.updatedAt < $1.updatedAt }

        let elimination = open.filter { t in
            if t.category.isSafetyCritical { return false }
            if t.status == .inbox { return false }   // unsorted captures are triaged, not eliminated
            if t.quadrant == .eliminate { return true }
            return t.dueDate == nil && math.daysBetween(t.updatedAt, now) >= 21 && t.priority != .critical
        }.sorted { $0.updatedAt < $1.updatedAt }

        let followUpsOutstanding = open.filter { $0.kind == .followUp }.sortedByDue()
        let followUpsResolved = completed.filter { $0.kind == .followUp }

        var counts: [Quadrant: Int] = [:]
        for q in Quadrant.allCases { counts[q] = open.filter { $0.quadrant == q }.count }

        let dueThisWeek = tasks.filter { t in
            guard let due = t.dueDate, t.status != .archived else { return false }
            return due >= weekStart && due < weekEnd
        }.count

        return WeeklyReview(
            weekStart: weekStart,
            weekEnd: weekEnd,
            completed: completed,
            overdue: overdue,
            repeatedlyPostponed: postponed,
            staleInbox: staleInbox,
            longWaiting: longWaiting,
            eliminationCandidates: elimination,
            followUpsOutstanding: followUpsOutstanding,
            followUpsResolved: followUpsResolved,
            quadrantCounts: counts,
            dueThisWeek: dueThisWeek
        )
    }
}
