import AppIntents
import Foundation
import SwiftData
import SecondBrainCore

/// "Add a task to Second Brain" — Siri asks what to add, interprets it on-device and saves it.
/// Anything ambiguous is saved to the Inbox exactly as spoken, so nothing is invented.
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Second Brain"
    static var description = IntentDescription("Captures a task, follow-up or reminder in Second Brain.")

    @Parameter(title: "What should I add?", requestValueDialog: IntentDialog("What should I add?"))
    var text: String

    init() {}

    init(text: String) { self.text = text }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = IntentCapture.capture(text)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// "Remind me in Second Brain" — e.g. "check the backroom tomorrow".
struct AddReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Remind Me"
    static var description = IntentDescription("Creates a reminder in Second Brain, e.g. “check the backroom tomorrow”.")

    @Parameter(title: "Remind you to…", requestValueDialog: IntentDialog("What should I remind you about, and when?"))
    var text: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = IntentCapture.capture("Remind me to " + text)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// "Look up a store term in Second Brain" — Siri asks which term and reads the meaning.
struct LookUpStoreTermIntent: AppIntent {
    static var title: LocalizedStringResource = "Look Up a Store Term"
    static var description = IntentDescription("Explains a store acronym or term, like FTPR, WOSH or remix. Works offline.")

    @Parameter(title: "Term", requestValueDialog: IntentDialog("Which term?"))
    var term: String

    init() {}

    init(term: String) { self.term = term }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: StoreTermAnswer.answer(for: term)))
    }
}

/// "Import notes into Second Brain" — opens the import screen with text from Shortcuts or the clipboard.
struct ImportNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Notes"
    static var description = IntentDescription("Opens Second Brain's import screen with notes to sort into tasks. Nothing is added until you review it.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Notes", description: "The email or notes to import. Leave empty to paste in the app.")
    var text: String?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        var components = URLComponents()
        components.scheme = DeepLink.scheme
        components.host = "import"
        if let text, !text.isEmpty { components.queryItems = [URLQueryItem(name: "text", value: text)] }
        RouteRequest.post(components.url ?? DeepLink.capture)
        return .result()
    }
}

/// Builds the spoken answer for a term lookup.
enum StoreTermAnswer {
    static func answer(for spoken: String) -> String {
        let word = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return "Which term should I look up?" }
        var matches = StoreGlossary.lookup(word)
        if matches.isEmpty {
            // Siri may hear "F T P R" or "ftp r" — try without spaces and dots, then a search.
            let squeezed = word.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
            matches = StoreGlossary.lookup(squeezed)
            if matches.isEmpty, let best = StoreGlossary.search(word).first { matches = [best] }
        }
        guard let first = matches.first else { return "I don't have “\(word)” in Store Terms yet." }
        if matches.count == 1 {
            let note = first.usage.label.map { " (\($0.lowercased()))" } ?? ""
            return "\(first.displayTerm): \(first.meaning)\(note)."
        }
        let meanings = matches.prefix(3).map { "\($0.meaning) — \($0.category.title)" }.joined(separator: "; or ")
        return "\(first.term) can mean \(meanings)."
    }
}

@MainActor
enum IntentCapture {
    static func capture(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "I didn't catch anything to add." }
        let context = PersistenceController.shared.mainContext
        let known = TaskActions.associates(in: context).filter { !$0.isArchived }.map(\.name)
        let parsed = NaturalLanguageParser().parse(trimmed, context: AppSettings.captureContext(knownAssociates: known))
        let draft = CaptureDraft(parsed: parsed)
        if draft.needsReview {
            CaptureSaver.saveToInbox(trimmed, in: context)
            let reason = draft.ambiguities.first?.message ?? "a detail needs checking"
            return "Saved to your Inbox so you can confirm it — \(reason)"
        }
        guard let result = CaptureSaver.save(draft, in: context) else { return "I couldn't save that." }
        switch result {
        case .task(let task):
            var reply = "Added “\(task.displayTitle)”"
            if let due = task.dueDate {
                reply += " for " + RelativeDateText.dueText(due: due, hasTime: task.hasDueTime, now: Date(), calendar: .current).lowercased()
            }
            if task.reminderDate != nil { reply += ", with a reminder" }
            return reply + "."
        case .note(let note):
            return "Saved the note “\(note.displayTitle)”."
        case .series(let series):
            return "Added “\(series.title)” — \(series.summary().lowercased())."
        }
    }
}

/// "What are my priorities today?"
struct TodayPrioritiesIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Priorities"
    static var description = IntentDescription("Hear your top priorities, overdue items and follow-ups for today.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.mainContext
        let snapshots = TaskActions.allTasks(in: context).map(\.snapshot)
        let agenda = DayAgenda.build(tasks: snapshots, day: Date(), now: Date(), calendar: .current)
        let focus = agenda.topPriorities.isEmpty ? agenda.suggestedPriorities : agenda.topPriorities
        var parts: [String] = []
        if focus.isEmpty {
            parts.append("You have no open priorities for today.")
        } else {
            let list = focus.prefix(3).enumerated().map { "\($0.offset + 1), \($0.element.title)" }.joined(separator: ". ")
            parts.append("Your top priorities: \(list).")
        }
        parts.append(BriefingBuilder.countsLine(agenda) + ".")
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: " ")))
    }
}

/// "Show my overdue tasks."
struct OverdueTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Overdue Tasks"
    static var description = IntentDescription("Lists overdue tasks and opens them in Second Brain.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.mainContext
        let overdue = TaskActions.openTasks(in: context).filter { $0.isOverdue() }
        RouteRequest.post(DeepLink.overdue)
        if overdue.isEmpty { return .result(dialog: "Nothing is overdue. Nice work.") }
        let names = overdue.prefix(5).map(\.displayTitle).joined(separator: ", ")
        return .result(dialog: IntentDialog(stringLiteral: "\(overdue.count) overdue: \(names)."))
    }
}

/// "Show my associate follow-ups."
struct FollowUpsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Associate Follow-ups"
    static var description = IntentDescription("Opens your outstanding associate follow-ups.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.mainContext
        let open = TaskActions.openTasks(in: context).filter { $0.kind == .followUp }
        RouteRequest.post(DeepLink.associates)
        let overdue = open.filter { $0.isOverdue() }.count
        var text = "\(open.count) open follow-up\(open.count == 1 ? "" : "s")"
        if overdue > 0 { text += ", \(overdue) overdue" }
        return .result(dialog: IntentDialog(stringLiteral: text + "."))
    }
}

/// "End my shift in Second Brain."
struct EndShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "End My Shift"
    static var description = IntentDescription("Opens the End My Shift review.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteRequest.post(DeepLink.shift)
        return .result()
    }
}

struct SecondBrainShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(), phrases: [
            "Add a task to \(.applicationName)",
            "Add to \(.applicationName)",
            "Capture in \(.applicationName)"
        ], shortTitle: "Add Task", systemImageName: "plus.circle")
        AppShortcut(intent: AddReminderIntent(), phrases: [
            "Remind me in \(.applicationName)",
            "Set a reminder in \(.applicationName)"
        ], shortTitle: "Remind Me", systemImageName: "bell")
        AppShortcut(intent: TodayPrioritiesIntent(), phrases: [
            "What are my priorities in \(.applicationName)",
            "What are my priorities today in \(.applicationName)",
            "Brief me with \(.applicationName)"
        ], shortTitle: "Today's Priorities", systemImageName: "star")
        AppShortcut(intent: OverdueTasksIntent(), phrases: [
            "Show my overdue tasks in \(.applicationName)",
            "What's overdue in \(.applicationName)"
        ], shortTitle: "Overdue", systemImageName: "exclamationmark.circle")
        AppShortcut(intent: FollowUpsIntent(), phrases: [
            "Show my associate follow-ups in \(.applicationName)",
            "Show my follow-ups in \(.applicationName)"
        ], shortTitle: "Follow-ups", systemImageName: "person.2")
        AppShortcut(intent: EndShiftIntent(), phrases: [
            "End my shift in \(.applicationName)"
        ], shortTitle: "End My Shift", systemImageName: "moon.stars")
        AppShortcut(intent: LookUpStoreTermIntent(), phrases: [
            "Look up a store term in \(.applicationName)",
            "What does a term mean in \(.applicationName)"
        ], shortTitle: "Store Terms", systemImageName: "character.book.closed")
        AppShortcut(intent: ImportNotesIntent(), phrases: [
            "Import notes into \(.applicationName)",
            "Import market notes in \(.applicationName)"
        ], shortTitle: "Import Notes", systemImageName: "square.and.arrow.down")
        AppShortcut(intent: OpenQuickCaptureIntent(), phrases: [
            "Quick capture in \(.applicationName)",
            "Open \(.applicationName) capture"
        ], shortTitle: "Quick Capture", systemImageName: "bolt")
    }
}
