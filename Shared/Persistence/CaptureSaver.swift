import Foundation
import SwiftData
import SecondBrainCore

/// An editable version of the parser's interpretation. The person can adjust any field before saving;
/// adjusted fields are "locked" so further typing doesn't overwrite them.
struct CaptureDraft: Equatable {
    enum Field: Hashable {
        case kind, title, associate, department, due, reminder, recurrence, quadrant, category, priority
    }

    var rawText: String = ""
    var title: String = ""
    var details: String = ""
    var kind: CaptureKind = .task
    var associateName: String = ""
    var associateIsKnown: Bool = false
    var department: String = ""
    var dueDate: Date? = nil
    var hasDueTime: Bool = false
    var reminderDate: Date? = nil
    var reminderIsDefault: Bool = false
    var category: TaskCategory = .general
    var priority: TaskPriority = .normal
    var quadrant: Quadrant = .schedule
    var classificationReasons: [String] = []
    var isSafetyLocked: Bool = false
    var recurrence: RecurrenceRule? = nil
    var recurrenceTimeMinutes: Int? = nil
    var request: String = ""
    var commitment: String = ""
    var ambiguities: [CaptureAmbiguity] = []
    var notes: [String] = []
    var locked: Set<Field> = []

    init() {}

    init(parsed: ParsedCapture) {
        rawText = parsed.rawText
        title = parsed.title
        details = parsed.details
        kind = parsed.kind
        associateName = parsed.associateName ?? ""
        associateIsKnown = parsed.associateIsKnown
        department = parsed.department ?? ""
        dueDate = parsed.dueDate
        hasDueTime = parsed.hasDueTime
        reminderDate = parsed.reminderDate
        reminderIsDefault = parsed.reminderSource == .defaultTime
        category = parsed.category
        priority = parsed.priority
        quadrant = parsed.classification.quadrant
        classificationReasons = parsed.classification.reasons
        isSafetyLocked = parsed.classification.isSafetyLocked
        recurrence = parsed.recurrence
        recurrenceTimeMinutes = parsed.recurrenceTimeMinutes
        request = parsed.request ?? ""
        commitment = parsed.commitment ?? ""
        ambiguities = parsed.ambiguities
        notes = parsed.notes
    }

    /// Applies a fresh parse while keeping every field the person adjusted.
    func merging(_ parsed: ParsedCapture) -> CaptureDraft {
        var next = CaptureDraft(parsed: parsed)
        next.locked = locked
        if locked.contains(.kind) { next.kind = kind }
        if locked.contains(.title) { next.title = title; next.details = details }
        if locked.contains(.associate) { next.associateName = associateName; next.associateIsKnown = associateIsKnown }
        if locked.contains(.department) { next.department = department }
        if locked.contains(.due) { next.dueDate = dueDate; next.hasDueTime = hasDueTime }
        if locked.contains(.reminder) { next.reminderDate = reminderDate; next.reminderIsDefault = false }
        if locked.contains(.recurrence) { next.recurrence = recurrence; next.recurrenceTimeMinutes = recurrenceTimeMinutes }
        if locked.contains(.quadrant) { next.quadrant = quadrant; next.classificationReasons = ["Set manually"] }
        if locked.contains(.category) { next.category = category }
        if locked.contains(.priority) { next.priority = priority }
        // Ambiguities about fields the person already settled no longer apply.
        next.ambiguities = next.ambiguities.filter { a in
            switch a.field {
            case .date: return !locked.contains(.due)
            case .time: return !(locked.contains(.due) || locked.contains(.reminder))
            case .person: return !locked.contains(.associate)
            case .recurrence: return !locked.contains(.recurrence)
            case .kind: return !locked.contains(.title)
            }
        }
        return next
    }

    var needsReview: Bool { !ambiguities.isEmpty }
    var isEmpty: Bool { rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var createsNote: Bool { kind.taskKind == nil }
}

enum CaptureResult {
    case task(TaskItem)
    case note(Note)
    case series(RecurrenceSeries)

    var confirmation: String {
        switch self {
        case .task(let t):
            var text = t.kind == .followUp ? "Follow-up saved" : (t.status == .inbox ? "Saved to Inbox" : "\(t.kind.shortTitle) saved")
            if let due = t.dueDate {
                text += " · " + RelativeDateText.dueText(due: due, hasTime: t.hasDueTime, now: Date(), calendar: .current)
            }
            return text
        case .note: return "Note saved"
        case .series(let s): return "Recurring · \(s.summary())"
        }
    }
}

/// Persists a confirmed capture. Nothing is created that the person didn't see in the preview.
@MainActor
enum CaptureSaver {
    /// Saves the raw text to the Inbox without applying any interpreted dates or people.
    @discardableResult
    static func saveToInbox(_ rawText: String, in context: ModelContext) -> TaskItem? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let task = TaskItem(title: text, kind: .task, status: .inbox)
        task.captureText = text
        context.insert(task)
        TaskActions.apply(TaskActions.classification(for: task), to: task)
        TaskActions.log(.created, "Captured to Inbox", task: task, in: context)
        TaskActions.save(context)
        return task
    }

    @discardableResult
    static func save(_ draft: CaptureDraft, in context: ModelContext) -> CaptureResult? {
        guard !draft.isEmpty else { return nil }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? draft.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            : draft.title
        let person = TaskActions.associate(named: draft.associateName, department: draft.department,
                                           createIfMissing: true, in: context)
        if let person, !draft.department.isEmpty, person.department.isEmpty {
            person.department = draft.department
        }

        // Notes, meeting notes and ideas.
        if let noteType = draft.kind.noteType {
            let note = Note(title: title, body: draft.details.isEmpty ? draft.rawText : draft.details, type: noteType)
            note.department = draft.department
            context.insert(note)
            note.associate = person
            if person != nil && noteType == .general { note.type = .associate }
            if let person { TaskActions.logInteraction(.note, "Note: \(note.displayTitle)", associate: person, in: context) }
            TaskActions.save(context)
            return .note(note)
        }

        let taskKind = draft.kind.taskKind ?? .task

        // Recurring responsibilities.
        if let rule = draft.recurrence {
            let anchor = draft.dueDate ?? Date()
            let series = RecurrenceService.createSeries(
                title: title, details: draft.details, rule: rule, anchor: anchor,
                timeMinutes: draft.recurrenceTimeMinutes ?? (draft.hasDueTime ? draft.dueDate.map { DateMath(calendar: .current).minutesSinceMidnight($0) } : nil),
                kind: taskKind, category: draft.category, priority: draft.priority,
                quadrant: draft.locked.contains(.quadrant) ? draft.quadrant : nil,
                associate: person, department: draft.department, in: context)
            return .series(series)
        }

        let task = TaskItem(title: title, kind: taskKind)
        task.details = draft.details
        task.captureText = draft.rawText
        task.category = draft.category
        task.priority = draft.priority
        task.department = draft.department
        task.dueDate = draft.dueDate
        task.hasDueTime = draft.dueDate != nil && draft.hasDueTime
        task.reminderDate = draft.reminderDate
        task.quadrant = draft.quadrant
        task.classificationIsManual = draft.locked.contains(.quadrant)
        task.classificationReasons = draft.classificationReasons.joined(separator: "\n")
        if taskKind == .followUp {
            task.request = draft.request.isEmpty ? title : draft.request
            task.commitment = draft.commitment
            task.conversationDate = Date()
        }
        context.insert(task)
        task.associate = person
        TaskActions.log(.created, "Captured", task: task, in: context)
        if let person {
            let kind: InteractionKind = taskKind == .followUp ? .request : .conversation
            TaskActions.logInteraction(kind, title, associate: person, task: task, in: context)
        }
        TaskActions.save(context)
        return .task(task)
    }

    /// Re-interprets an Inbox item so it can be sorted with one tap.
    static func suggestion(for task: TaskItem, knownAssociates: [String]) -> CaptureDraft {
        let text = task.captureText.isEmpty ? task.title : task.captureText
        let parsed = NaturalLanguageParser().parse(text, context: AppSettings.captureContext(knownAssociates: knownAssociates))
        return CaptureDraft(parsed: parsed)
    }

    /// Applies a confirmed suggestion to an existing Inbox item.
    static func apply(_ draft: CaptureDraft, to task: TaskItem, in context: ModelContext) {
        task.title = draft.title.isEmpty ? task.title : draft.title
        if !draft.details.isEmpty { task.details = draft.details }
        task.kind = draft.kind.taskKind ?? .task
        task.category = draft.category
        task.priority = draft.priority
        task.department = draft.department
        task.dueDate = draft.dueDate
        task.hasDueTime = draft.dueDate != nil && draft.hasDueTime
        task.reminderDate = draft.reminderDate
        task.quadrant = draft.quadrant
        task.classificationReasons = draft.classificationReasons.joined(separator: "\n")
        if task.kind == .followUp {
            task.request = draft.request.isEmpty ? task.title : draft.request
            task.commitment = draft.commitment
        }
        task.associate = TaskActions.associate(named: draft.associateName, department: draft.department, createIfMissing: true, in: context)
        task.status = .notStarted
        task.updatedAt = Date()
        TaskActions.log(.edited, "Sorted from Inbox", task: task, in: context)
        TaskActions.save(context)
    }
}
