import Foundation

/// Scores open work for a given day so the app can *suggest* (never impose) the top priorities.
public enum PriorityRanker {
    public static func score(_ task: TaskSnapshot, for day: Date, now: Date, calendar: Calendar) -> Double {
        guard task.isOpen else { return -1_000 }
        let math = DateMath(calendar: calendar)
        var score = 0.0

        switch task.quadrant {
        case .doFirst: score += 40
        case .schedule: score += 25
        case .delegate: score += 10
        case .eliminate: score += 0
        }

        if let due = task.dueDate {
            let days = math.daysBetween(day, due)
            if days < 0 {
                score += 30 + Double(min(-days * 2, 10))
            } else if days == 0 {
                score += 25
            } else if days == 1 {
                score += 10
            } else if days <= 3 {
                score += 4
            }
        }

        switch task.priority {
        case .critical: score += 25
        case .high: score += 12
        case .normal: break
        case .low: score -= 10
        }

        if task.kind == .followUp { score += 8 }
        if task.category.isSafetyCritical { score += 10 }
        if task.rescheduleCount >= 3 { score += 5 }
        if task.isAwaitingConfirmation { score -= 15 }
        if task.status == .inbox { score -= 5 }
        if task.status == .deferred { score -= 20 }
        if task.status == .inProgress { score += 3 }
        return score
    }

    public static func ranked(_ tasks: [TaskSnapshot], for day: Date, now: Date, calendar: Calendar) -> [TaskSnapshot] {
        tasks.filter { $0.isOpen }
            .map { ($0, score($0, for: day, now: now, calendar: calendar)) }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.createdAt < b.0.createdAt
            }
            .map { $0.0 }
    }

    public static func suggestions(from tasks: [TaskSnapshot], for day: Date, now: Date, calendar: Calendar, limit: Int = 3) -> [TaskSnapshot] {
        Array(ranked(tasks, for: day, now: now, calendar: calendar)
            .filter { !$0.isAwaitingConfirmation && $0.quadrant != .eliminate }
            .prefix(limit))
    }
}
