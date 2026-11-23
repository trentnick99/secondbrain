import Foundation

public enum TaskPriority: String, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case critical, high, normal, low

    public var id: String { rawValue }

    /// Lower rank = more pressing.
    public var rank: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .normal: return 2
        case .low: return 3
        }
    }

    public var title: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        }
    }

    public var systemImage: String {
        switch self {
        case .critical: return "exclamationmark.3"
        case .high: return "exclamationmark.2"
        case .normal: return "minus"
        case .low: return "arrow.down"
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rank > rhs.rank }
}

public enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inbox
    case notStarted
    case inProgress
    case waiting
    case completed
    case deferred
    case archived

    public var id: String { rawValue }

    /// Open = still needs attention. Unfinished work never disappears on its own.
    public var isOpen: Bool { self != .completed && self != .archived }

    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .waiting: return "Waiting on Someone"
        case .completed: return "Completed"
        case .deferred: return "Deferred"
        case .archived: return "Archived"
        }
    }

    public var shortTitle: String {
        switch self {
        case .waiting: return "Waiting"
        default: return title
        }
    }

    public var systemImage: String {
        switch self {
        case .inbox: return "tray"
        case .notStarted: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .waiting: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .deferred: return "clock.arrow.circlepath"
        case .archived: return "archivebox"
        }
    }

    public static var openStatuses: [TaskStatus] { allCases.filter { $0.isOpen } }
}

public enum TaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case task
    case followUp
    case reminder
    case issue

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .task: return "Task"
        case .followUp: return "Follow-up"
        case .reminder: return "Reminder"
        case .issue: return "Operational Issue"
        }
    }

    public var shortTitle: String {
        switch self {
        case .issue: return "Issue"
        default: return title
        }
    }

    public var systemImage: String {
        switch self {
        case .task: return "checklist"
        case .followUp: return "person.crop.circle.badge.clock"
        case .reminder: return "bell"
        case .issue: return "exclamationmark.triangle"
        }
    }
}

public enum TaskCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case general
    case safety
    case compliance
    case people
    case development
    case freight
    case merchandising
    case operations
    case customer
    case admin
    case meeting

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .safety: return "Safety"
        case .compliance: return "Compliance"
        case .people: return "People"
        case .development: return "Development"
        case .freight: return "Freight & Stocking"
        case .merchandising: return "Merchandising"
        case .operations: return "Operations"
        case .customer: return "Customer"
        case .admin: return "Admin & Results"
        case .meeting: return "Meetings"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "square.grid.2x2"
        case .safety: return "cross.case"
        case .compliance: return "checkmark.shield"
        case .people: return "person.2"
        case .development: return "graduationcap"
        case .freight: return "shippingbox"
        case .merchandising: return "tag"
        case .operations: return "gearshape.2"
        case .customer: return "person.wave.2"
        case .admin: return "chart.bar.doc.horizontal"
        case .meeting: return "person.3"
        }
    }

    /// Safety and compliance are never treated as unimportant, regardless of deadline.
    public var isSafetyCritical: Bool { self == .safety || self == .compliance }
}

/// What the person is capturing in Quick Capture.
public enum CaptureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case task
    case followUp
    case reminder
    case issue
    case note
    case meetingNote
    case idea

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .task: return "Task"
        case .followUp: return "Follow-up"
        case .reminder: return "Reminder"
        case .issue: return "Issue"
        case .note: return "Note"
        case .meetingNote: return "Meeting"
        case .idea: return "Idea"
        }
    }

    public var systemImage: String {
        switch self {
        case .task: return "checklist"
        case .followUp: return "person.crop.circle.badge.clock"
        case .reminder: return "bell"
        case .issue: return "exclamationmark.triangle"
        case .note: return "note.text"
        case .meetingNote: return "person.3"
        case .idea: return "lightbulb"
        }
    }

    /// The task kind created for this capture, or nil when it becomes a note.
    public var taskKind: TaskKind? {
        switch self {
        case .task: return .task
        case .followUp: return .followUp
        case .reminder: return .reminder
        case .issue: return .issue
        case .note, .meetingNote, .idea: return nil
        }
    }

    public var noteType: NoteType? {
        switch self {
        case .note: return .general
        case .meetingNote: return .meeting
        case .idea: return .idea
        default: return nil
        }
    }
}

public enum NoteType: String, Codable, CaseIterable, Identifiable, Sendable {
    case general
    case associate
    case meeting
    case department
    case operational
    case safety
    case idea

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .associate: return "Associate"
        case .meeting: return "Meeting"
        case .department: return "Department"
        case .operational: return "Operational"
        case .safety: return "Safety"
        case .idea: return "Idea"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "note.text"
        case .associate: return "person.text.rectangle"
        case .meeting: return "person.3"
        case .department: return "building.2"
        case .operational: return "gearshape.2"
        case .safety: return "cross.case"
        case .idea: return "lightbulb"
        }
    }
}

public enum InteractionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case conversation
    case request
    case followUp
    case resolved
    case note

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .conversation: return "Conversation"
        case .request: return "Request"
        case .followUp: return "Follow-up"
        case .resolved: return "Resolved"
        case .note: return "Note"
        }
    }

    public var systemImage: String {
        switch self {
        case .conversation: return "bubble.left.and.bubble.right"
        case .request: return "hand.raised"
        case .followUp: return "arrow.uturn.forward.circle"
        case .resolved: return "checkmark.seal"
        case .note: return "note.text"
        }
    }
}

public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case created
    case edited
    case completed
    case reopened
    case rescheduled
    case snoozed
    case quadrantChanged
    case statusChanged
    case priorityChanged
    case carriedForward
    case delegated
    case delegationConfirmed
    case archived
    case restored
    case skipped
    case missed

    public var title: String {
        switch self {
        case .created: return "Created"
        case .edited: return "Edited"
        case .completed: return "Completed"
        case .reopened: return "Reopened"
        case .rescheduled: return "Rescheduled"
        case .snoozed: return "Snoozed"
        case .quadrantChanged: return "Quadrant changed"
        case .statusChanged: return "Status changed"
        case .priorityChanged: return "Priority changed"
        case .carriedForward: return "Carried forward"
        case .delegated: return "Delegated"
        case .delegationConfirmed: return "Hand-off confirmed"
        case .archived: return "Archived"
        case .restored: return "Restored"
        case .skipped: return "Occurrence skipped"
        case .missed: return "Occurrence missed"
        }
    }

    public var systemImage: String {
        switch self {
        case .created: return "plus.circle"
        case .edited: return "pencil"
        case .completed: return "checkmark.circle"
        case .reopened: return "arrow.uturn.backward.circle"
        case .rescheduled: return "calendar"
        case .snoozed: return "zzz"
        case .quadrantChanged: return "square.grid.2x2"
        case .statusChanged: return "arrow.triangle.2.circlepath"
        case .priorityChanged: return "flag"
        case .carriedForward: return "arrow.right.circle"
        case .delegated: return "person.badge.plus"
        case .delegationConfirmed: return "person.fill.checkmark"
        case .archived: return "archivebox"
        case .restored: return "tray.and.arrow.up"
        case .skipped: return "forward"
        case .missed: return "exclamationmark.circle"
        }
    }
}
