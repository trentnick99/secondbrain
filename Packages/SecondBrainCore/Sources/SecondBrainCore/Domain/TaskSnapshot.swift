import Foundation

/// A lightweight, persistence-independent view of a task.
///
/// The app converts its SwiftData models into snapshots so the planning engine,
/// notification planner, widgets and Siri responses all share one tested code path.
public struct TaskSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: TaskKind
    public var status: TaskStatus
    public var priority: TaskPriority
    public var quadrant: Quadrant
    public var category: TaskCategory
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var reminderDate: Date?
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var associateName: String?
    public var department: String?
    /// The day this task was chosen as one of the "Top 3" priorities.
    public var focusDate: Date?
    public var rescheduleCount: Int
    public var isRecurring: Bool
    public var delegatedTo: String?
    public var delegationConfirmed: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        kind: TaskKind = .task,
        status: TaskStatus = .notStarted,
        priority: TaskPriority = .normal,
        quadrant: Quadrant = .schedule,
        category: TaskCategory = .general,
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        reminderDate: Date? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        associateName: String? = nil,
        department: String? = nil,
        focusDate: Date? = nil,
        rescheduleCount: Int = 0,
        isRecurring: Bool = false,
        delegatedTo: String? = nil,
        delegationConfirmed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.priority = priority
        self.quadrant = quadrant
        self.category = category
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.reminderDate = reminderDate
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.associateName = associateName
        self.department = department
        self.focusDate = focusDate
        self.rescheduleCount = rescheduleCount
        self.isRecurring = isRecurring
        self.delegatedTo = delegatedTo
        self.delegationConfirmed = delegationConfirmed
    }

    public var isOpen: Bool { status.isOpen }

    /// Waiting on someone else, or delegated without confirmation that the person accepted.
    public var isAwaitingConfirmation: Bool {
        guard isOpen else { return false }
        if status == .waiting { return true }
        if let delegate = delegatedTo, !delegate.trimmingCharacters(in: .whitespaces).isEmpty, !delegationConfirmed { return true }
        return false
    }

    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard isOpen, let due = dueDate else { return false }
        if hasDueTime { return due < now }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    public func isDue(on day: Date, calendar: Calendar) -> Bool {
        guard let due = dueDate else { return false }
        return calendar.isDate(due, inSameDayAs: day)
    }
}

extension Array where Element == TaskSnapshot {
    /// Standard ordering: quadrant, priority, due date, then creation.
    public func sortedForDisplay() -> [TaskSnapshot] {
        sorted { a, b in
            if a.quadrant.sortIndex != b.quadrant.sortIndex { return a.quadrant.sortIndex < b.quadrant.sortIndex }
            if a.priority.rank != b.priority.rank { return a.priority.rank < b.priority.rank }
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    public func sortedByDue() -> [TaskSnapshot] {
        sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.priority.rank != b.priority.rank { return a.priority.rank < b.priority.rank }
                return a.createdAt < b.createdAt
            }
        }
    }
}
