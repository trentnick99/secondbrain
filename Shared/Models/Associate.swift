import Foundation
import SwiftData
import SecondBrainCore

/// A person you support or work with. This is a personal organizer, not an HR record:
/// the app reminds you not to store medical, disciplinary or confidential personnel details.
@Model
final class Associate {
    var id: UUID = UUID()
    var name: String = ""
    var department: String = ""
    var role: String = ""
    /// Short, non-sensitive context ("prefers mornings", "learning the backroom").
    var profileNote: String = ""
    var isArchived: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastInteractionAt: Date? = nil

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.associate)
    var tasks: [TaskItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \Note.associate)
    var notes: [Note]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurrenceSeries.associate)
    var series: [RecurrenceSeries]? = []

    @Relationship(deleteRule: .cascade, inverse: \ActivityEvent.associate)
    var activity: [ActivityEvent]? = []

    init(name: String, department: String = "", role: String = "") {
        self.id = UUID()
        self.name = name
        self.department = department
        self.role = role
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var allTasks: [TaskItem] { tasks ?? [] }

    var openFollowUps: [TaskItem] {
        allTasks.filter { $0.kind == .followUp && $0.isOpen }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var resolvedFollowUps: [TaskItem] {
        allTasks.filter { $0.kind == .followUp && $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var otherOpenTasks: [TaskItem] {
        allTasks.filter { $0.kind != .followUp && $0.isOpen }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var history: [ActivityEvent] {
        (activity ?? []).sorted { $0.date > $1.date }
    }

    var sortedNotes: [Note] {
        (notes ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    var hasOverdueFollowUp: Bool {
        openFollowUps.contains { $0.isOverdue() }
    }
}
