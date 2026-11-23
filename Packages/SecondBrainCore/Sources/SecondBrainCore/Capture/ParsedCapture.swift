import Foundation

/// Everything the parser needs to know about the person's world, injected for determinism.
public struct CaptureContext: Sendable {
    public var now: Date
    public var calendar: Calendar
    /// Names already in the Associates list (full names). Matching is case-insensitive.
    public var knownAssociates: [String]
    /// Minutes after midnight for the default reminder on date-only items; nil disables default reminders.
    public var defaultReminderMinutes: Int?
    public var shiftStartMinutes: Int
    public var shiftEndMinutes: Int
    /// 1 = Sunday … 7 = Saturday.
    public var weekStartsOn: Int

    public init(now: Date = Date(),
                calendar: Calendar = .current,
                knownAssociates: [String] = [],
                defaultReminderMinutes: Int? = 7 * 60,
                shiftStartMinutes: Int = 7 * 60,
                shiftEndMinutes: Int = 16 * 60,
                weekStartsOn: Int? = nil) {
        self.now = now
        self.calendar = calendar
        self.knownAssociates = knownAssociates
        self.defaultReminderMinutes = defaultReminderMinutes
        self.shiftStartMinutes = shiftStartMinutes
        self.shiftEndMinutes = shiftEndMinutes
        self.weekStartsOn = weekStartsOn ?? calendar.firstWeekday
    }
}

public enum ReminderSource: String, Codable, Sendable {
    case none
    case explicitTime
    case relative
    case defaultTime
}

/// Something the parser could not determine with certainty. Any ambiguity means the
/// interpretation is shown for confirmation before saving.
public struct CaptureAmbiguity: Hashable, Sendable, Identifiable {
    public enum Field: String, Sendable {
        case date, time, person, recurrence, kind
    }

    public var field: Field
    public var message: String
    public var id: String { field.rawValue + ":" + message }

    public init(field: Field, message: String) {
        self.field = field
        self.message = message
    }
}

/// The interpretation of a Quick Capture entry. Nothing here is saved until the person confirms
/// (or taps Save when there is nothing ambiguous).
public struct ParsedCapture: Equatable, Sendable {
    public var rawText: String
    public var title: String
    public var details: String
    public var kind: CaptureKind
    public var associateName: String?
    public var associateIsKnown: Bool
    public var associateIsRole: Bool
    public var department: String?
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var reminderDate: Date?
    public var reminderSource: ReminderSource
    public var category: TaskCategory
    public var priority: TaskPriority
    public var classification: EisenhowerClassification
    public var recurrence: RecurrenceRule?
    /// Minutes after midnight for recurring items with a time of day.
    public var recurrenceTimeMinutes: Int?
    public var ambiguities: [CaptureAmbiguity]
    /// Short, readable explanations such as "before Friday → due Thu".
    public var notes: [String]
    /// The exact phrases that were interpreted (dates, times, recurrence) for highlighting.
    public var matchedPhrases: [String]

    /// For follow-ups: what was asked, and what I committed to.
    public var request: String?
    public var commitment: String?

    public var needsReview: Bool { !ambiguities.isEmpty }
    public var isEmpty: Bool { rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var hasSchedule: Bool { dueDate != nil || recurrence != nil }
}
