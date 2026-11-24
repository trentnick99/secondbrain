import Foundation

/// A short, shareable handoff for the next coach or the overnight team: what got done, what's still
/// open (safety and Do First first), and what's due next. Work tied to a specific associate is left
/// out unless the person chooses to include it, since a handoff may be read by others.
public enum ShiftHandoff {
    public static func text(review: ShiftReview, role: UserRole?, includeAssociateItems: Bool = false,
                            note: String = "", now: Date, calendar: Calendar) -> String {
        let shareable: (TaskSnapshot) -> Bool = { task in
            includeAssociateItems || (task.associateName == nil && task.kind != .followUp)
        }
        let done = review.completedToday.filter(shareable)
        let open = review.carryForwardCandidates.filter(shareable).sorted(by: order)
        var seen = Set(open.map(\.id))
        let upcoming = review.upcomingDeadlines.filter { shareable($0) && seen.insert($0.id).inserted }
        let hidden = (review.completedToday + review.carryForwardCandidates).filter { !shareable($0) }.count

        let day = RelativeDateText.mediumDate(now, calendar: calendar)
        var lines = ["Shift handoff · \(day)" + (role.map { " · \($0.title)" } ?? "")]

        lines.append("")
        lines.append(open.isEmpty ? "Still open: nothing." : "Still open (\(open.count)):")
        lines += open.prefix(12).map { "• " + label($0, now: now, calendar: calendar) }
        if open.count > 12 { lines.append("• …and \(open.count - 12) more") }

        if !upcoming.isEmpty {
            lines.append("")
            lines.append("Coming up:")
            lines += upcoming.prefix(5).map { "• " + label($0, now: now, calendar: calendar) }
        }

        lines.append("")
        lines.append(done.isEmpty ? "Done today: nothing marked done." : "Done today (\(done.count)):")
        lines += done.prefix(10).map { "• \($0.title)" }
        if done.count > 10 { lines.append("• …and \(done.count - 10) more") }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            lines.append("")
            lines.append("Notes: \(trimmedNote)")
        }
        if hidden > 0 && !includeAssociateItems {
            lines.append("")
            lines.append("(\(hidden) associate follow-up\(hidden == 1 ? "" : "s") not included.)")
        }
        return lines.joined(separator: "\n")
    }

    /// Safety first, then Do First, then by due date.
    static func order(_ a: TaskSnapshot, _ b: TaskSnapshot) -> Bool {
        let aSafety = a.category == .safety || a.category == .compliance
        let bSafety = b.category == .safety || b.category == .compliance
        if aSafety != bSafety { return aSafety }
        if a.quadrant != b.quadrant { return a.quadrant.rawValue < b.quadrant.rawValue }
        return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
    }

    static func label(_ task: TaskSnapshot, now: Date, calendar: Calendar) -> String {
        var parts = [task.title]
        if task.category == .safety { parts.append("(safety)") }
        if let area = task.department, !area.isEmpty { parts.append("· \(StoreAreas.shortName(area))") }
        if let due = task.dueDate {
            parts.append("· due " + RelativeDateText.dayLabel(for: due, now: now, calendar: calendar).lowercased())
        }
        return parts.joined(separator: " ")
    }
}
