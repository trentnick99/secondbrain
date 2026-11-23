import Foundation

/// The four quadrants of the Eisenhower Matrix.
///
/// Urgency and importance are tracked independently: a deadline makes something *urgent*,
/// never automatically *important*.
public enum Quadrant: String, Codable, CaseIterable, Identifiable, Sendable {
    case doFirst = "q1"
    case schedule = "q2"
    case delegate = "q3"
    case eliminate = "q4"

    public var id: String { rawValue }

    public init(urgent: Bool, important: Bool) {
        switch (urgent, important) {
        case (true, true): self = .doFirst
        case (false, true): self = .schedule
        case (true, false): self = .delegate
        case (false, false): self = .eliminate
        }
    }

    public var isUrgent: Bool { self == .doFirst || self == .delegate }
    public var isImportant: Bool { self == .doFirst || self == .schedule }

    public var code: String {
        switch self {
        case .doFirst: return "Q1"
        case .schedule: return "Q2"
        case .delegate: return "Q3"
        case .eliminate: return "Q4"
        }
    }

    public var title: String {
        switch self {
        case .doFirst: return "Do First"
        case .schedule: return "Schedule"
        case .delegate: return "Delegate"
        case .eliminate: return "Eliminate"
        }
    }

    public var subtitle: String {
        switch self {
        case .doFirst: return "Urgent + Important"
        case .schedule: return "Important + Not Urgent"
        case .delegate: return "Urgent + Not Important"
        case .eliminate: return "Not Urgent + Not Important"
        }
    }

    public var guidance: String {
        switch self {
        case .doFirst: return "Handle these now — safety hazards, critical operational problems, urgent staffing."
        case .schedule: return "Protect time for these — associate development, market-visit prep, reviews, improvement plans."
        case .delegate: return "Hand these off where appropriate, then confirm the hand-off was accepted."
        case .eliminate: return "Question these — outdated, duplicate or unnecessary. Archive deliberately; nothing is deleted automatically."
        }
    }

    public var systemImage: String {
        switch self {
        case .doFirst: return "flame.fill"
        case .schedule: return "calendar.badge.clock"
        case .delegate: return "person.2.fill"
        case .eliminate: return "archivebox"
        }
    }

    public var sortIndex: Int {
        switch self {
        case .doFirst: return 0
        case .schedule: return 1
        case .delegate: return 2
        case .eliminate: return 3
        }
    }
}
