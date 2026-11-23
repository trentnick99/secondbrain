import Foundation

/// Deterministic, offline text summaries. The optional AI assistant can rephrase these,
/// but the app never depends on it.
public enum BriefingBuilder {
    public static func greeting(now: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 4..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private static func plural(_ n: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (pluralForm ?? singular + "s"))"
    }

    /// One-line summary used in notifications and widgets, e.g. "3 due today · 2 overdue · 1 follow-up".
    public static func countsLine(_ agenda: DayAgenda) -> String {
        var parts: [String] = []
        if !agenda.dueToday.isEmpty { parts.append("\(agenda.dueToday.count) due today") }
        if !agenda.overdue.isEmpty { parts.append("\(agenda.overdue.count) overdue") }
        if !agenda.followUpsDue.isEmpty { parts.append(plural(agenda.followUpsDue.count, "follow-up")) }
        if parts.isEmpty { return agenda.openCount == 0 ? "All clear" : "Nothing due today" }
        return parts.joined(separator: " · ")
    }

    /// Multi-sentence daily briefing.
    public static func dailyBriefing(_ agenda: DayAgenda, now: Date, calendar: Calendar) -> String {
        var lines: [String] = []
        let dueCount = agenda.dueToday.count
        let overdueCount = agenda.overdue.count
        var opening = "\(greeting(now: now, calendar: calendar))."
        if dueCount == 0 && overdueCount == 0 {
            opening += " Nothing is due today."
        } else {
            var parts: [String] = []
            if dueCount > 0 { parts.append(plural(dueCount, "task") + " due today") }
            if overdueCount > 0 { parts.append(plural(overdueCount, "overdue item")) }
            opening += " You have " + parts.joined(separator: " and ") + "."
        }
        lines.append(opening)

        let focus = agenda.topPriorities.isEmpty ? agenda.suggestedPriorities : agenda.topPriorities
        if !focus.isEmpty {
            let label = agenda.topPriorities.isEmpty ? "Suggested focus" : "Your top priorities"
            let list = focus.prefix(3).enumerated().map { "\($0.offset + 1)) \($0.element.title)" }.joined(separator: "  ")
            lines.append("\(label): \(list)")
        }
        if !agenda.followUpsDue.isEmpty {
            let names = agenda.followUpsDue.compactMap(\.associateName)
            let uniqueNames = Array(NSOrderedSet(array: names)).compactMap { $0 as? String }.prefix(3)
            var line = "\(plural(agenda.followUpsDue.count, "follow-up")) due"
            if !uniqueNames.isEmpty { line += " (" + uniqueNames.joined(separator: ", ") + ")" }
            lines.append(line + ".")
        }
        if let next = agenda.nextReminder, let at = next.reminderDate {
            lines.append("Next reminder \(RelativeDateText.timeText(at, calendar: calendar)): \(next.title).")
        }
        if let q2 = agenda.scheduledImportant.first {
            lines.append("Don't lose sight of Q2: \(q2.title).")
        }
        if !agenda.waiting.isEmpty {
            lines.append("\(plural(agenda.waiting.count, "item")) waiting on someone else.")
        }
        return lines.joined(separator: "\n")
    }

    public static func shiftSummary(_ review: ShiftReview) -> String {
        var parts = ["Completed \(review.completedToday.count)"]
        if !review.carryForwardCandidates.isEmpty { parts.append("\(review.carryForwardCandidates.count) unfinished") }
        if !review.outstandingCommitments.isEmpty { parts.append(plural(review.outstandingCommitments.count, "open commitment")) }
        return parts.joined(separator: " · ")
    }

    public static func weeklySummary(_ review: WeeklyReview) -> String {
        var lines: [String] = []
        lines.append("Completed \(plural(review.completed.count, "item")) this week.")
        if let rate = review.completionRate {
            lines.append("Completion rate: \(Int((rate * 100).rounded()))%.")
        }
        if !review.overdue.isEmpty { lines.append("\(plural(review.overdue.count, "item")) overdue.") }
        if !review.repeatedlyPostponed.isEmpty {
            lines.append("\(plural(review.repeatedlyPostponed.count, "task")) postponed \(WeeklyReview.postponedThreshold)+ times — decide, delegate or drop.")
        }
        if !review.followUpsOutstanding.isEmpty {
            lines.append("\(plural(review.followUpsOutstanding.count, "associate follow-up")) still open.")
        }
        if !review.eliminationCandidates.isEmpty {
            lines.append("\(plural(review.eliminationCandidates.count, "item")) may no longer be needed.")
        }
        return lines.joined(separator: "\n")
    }
}
