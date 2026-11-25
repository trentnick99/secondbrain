import Foundation
import SwiftData
import SecondBrainCore

typealias TaskItem = SchemaV1.TaskItem

extension SchemaV1 {
    /// A task, associate follow-up, reminder or operational issue.
    ///
    /// Follow-ups are tasks with `kind == .followUp` plus request / commitment details, so every
    /// commitment flows through the same dashboard, Eisenhower Matrix, notifications and End My Shift.
    ///
    /// CloudKit-ready: every attribute has a default, relationships are optional, nothing is unique.
    @Model
    final class TaskItem {
        var id: UUID = UUID()
        var title: String = ""
        var details: String = ""
        var kindRaw: String = TaskKind.task.rawValue
        var statusRaw: String = TaskStatus.notStarted.rawValue
        var priorityRaw: String = TaskPriority.normal.rawValue
        var categoryRaw: String = TaskCategory.general.rawValue

        // Eisenhower — urgency and importance are stored independently.
        var isUrgent: Bool = false
        var isImportant: Bool = true
        var classificationIsManual: Bool = false
        var classificationReasons: String = ""

        var department: String = ""
        var dueDate: Date? = nil
        var hasDueTime: Bool = false
        var reminderDate: Date? = nil

        /// Set when chosen as one of the day's three main priorities (start of that day).
        var focusDate: Date? = nil
        var focusRank: Int = 0
        var rescheduleCount: Int = 0

        // Delegation / waiting — never assumed accepted.
        var delegatedTo: String = ""
        var delegationConfirmed: Bool = false
        var waitingOn: String = ""

        // Associate follow-up details.
        var request: String = ""
        var commitment: String = ""
        var conversationDate: Date? = nil

        // Recurring occurrence bookkeeping.
        var seriesID: UUID? = nil
        var occurrenceKey: String = ""

        // Links.
        var linkedFollowUpID: UUID? = nil
        var calendarEventID: String = ""
        var captureText: String = ""

        var completionNotes: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var completedAt: Date? = nil
        var archivedAt: Date? = nil
        var sortOrder: Double = 0

        var associate: Associate?

        @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.task)
        var subtasks: [ChecklistItem]? = []

        @Relationship(deleteRule: .nullify, inverse: \Note.linkedTasks)
        var notes: [Note]? = []

        @Relationship(deleteRule: .nullify, inverse: \ActivityEvent.task)
        var activity: [ActivityEvent]? = []

        init(title: String, kind: TaskKind = .task, status: TaskStatus = .notStarted) {
            self.id = UUID()
            self.title = title
            self.kindRaw = kind.rawValue
            self.statusRaw = status.rawValue
            let now = Date()
            self.createdAt = now
            self.updatedAt = now
            self.sortOrder = now.timeIntervalSince1970
        }

        // MARK: Typed accessors

        var kind: TaskKind {
            get { TaskKind(rawValue: kindRaw) ?? .task }
            set { kindRaw = newValue.rawValue }
        }

        var status: TaskStatus {
            get { TaskStatus(rawValue: statusRaw) ?? .notStarted }
            set { statusRaw = newValue.rawValue }
        }

        var priority: TaskPriority {
            get { TaskPriority(rawValue: priorityRaw) ?? .normal }
            set { priorityRaw = newValue.rawValue }
        }

        var category: TaskCategory {
            get { TaskCategory(rawValue: categoryRaw) ?? .general }
            set { categoryRaw = newValue.rawValue }
        }

        var quadrant: Quadrant {
            get { Quadrant(urgent: isUrgent, important: isImportant) }
            set {
                isUrgent = newValue.isUrgent
                isImportant = newValue.isImportant
            }
        }

        var reasons: [String] {
            classificationReasons.split(separator: "\n").map(String.init)
        }

        var isOpen: Bool { status.isOpen }
        var isCompleted: Bool { status == .completed }
        var isRecurring: Bool { seriesID != nil }

        var sortedSubtasks: [ChecklistItem] {
            (subtasks ?? []).sorted { $0.sortIndex == $1.sortIndex ? $0.createdAt < $1.createdAt : $0.sortIndex < $1.sortIndex }
        }

        var sortedActivity: [ActivityEvent] {
            (activity ?? []).sorted { $0.date > $1.date }
        }

        var displayTitle: String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Untitled" : trimmed
        }

        func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
            snapshot.isOverdue(now: now, calendar: calendar)
        }

        var isAwaitingConfirmation: Bool { snapshot.isAwaitingConfirmation }

        /// Persistence-independent copy used by the planning engine, notifications, widgets and Siri.
        var snapshot: TaskSnapshot {
            TaskSnapshot(
                id: id,
                title: displayTitle,
                kind: kind,
                status: status,
                priority: priority,
                quadrant: quadrant,
                category: category,
                dueDate: dueDate,
                hasDueTime: hasDueTime,
                reminderDate: reminderDate,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                associateName: associate?.name,
                department: department.isEmpty ? nil : department,
                focusDate: focusDate,
                rescheduleCount: rescheduleCount,
                isRecurring: seriesID != nil,
                delegatedTo: delegatedTo.isEmpty ? nil : delegatedTo,
                delegationConfirmed: delegationConfirmed
            )
        }
    }
}

/// Stated explicitly (SwiftData already implies it) so every file sees it, whatever order the compiler checks them in.
extension TaskItem: Identifiable {}
