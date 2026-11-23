import Foundation
import SwiftData
import SecondBrainCore

/// Lets the app react to data changes (reschedule notifications, refresh widgets) without the
/// shared persistence code knowing about app-only services.
@MainActor
enum DataChange {
    static var handlers: [() -> Void] = []

    static func notify() {
        for handler in handlers { handler() }
        if AppGroup.isRunningInExtension { AppSettings.markExternalChange() }
    }
}

/// The business rules for changing tasks. Every screen, notification action, widget button and
/// Siri intent goes through these functions so behaviour (history, recurrence, reminders) is consistent.
///
/// Rules: nothing unfinished is discarded automatically, delegation is never assumed accepted,
/// and quadrant changes are recorded in the task's history.
@MainActor
enum TaskActions {
    // MARK: Lookup

    static func task(with id: UUID, in context: ModelContext) -> TaskItem? {
        let target = id
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.id == target })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func allTasks(in context: ModelContext) -> [TaskItem] {
        (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
    }

    static func openTasks(in context: ModelContext) -> [TaskItem] {
        allTasks(in: context).filter { $0.isOpen }
    }

    static func associates(in context: ModelContext) -> [Associate] {
        (try? context.fetch(FetchDescriptor<Associate>(sortBy: [SortDescriptor(\Associate.name)]))) ?? []
    }

    /// Finds an associate by name (case-insensitive), optionally creating one.
    static func associate(named rawName: String, department: String = "", createIfMissing: Bool,
                          in context: ModelContext) -> Associate? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let lower = name.lowercased()
        if let match = associates(in: context).first(where: { $0.name.lowercased() == lower }) {
            if match.isArchived { match.isArchived = false }
            return match
        }
        guard createIfMissing else { return nil }
        let person = Associate(name: name, department: department)
        context.insert(person)
        return person
    }

    // MARK: History

    static func log(_ kind: ActivityKind, _ summary: String, task: TaskItem, in context: ModelContext, date: Date = Date()) {
        let event = ActivityEvent(kind: kind, summary: summary, date: date)
        context.insert(event)
        event.task = task
    }

    static func logInteraction(_ kind: InteractionKind, _ summary: String, associate: Associate,
                               task: TaskItem? = nil, in context: ModelContext, date: Date = Date()) {
        let event = ActivityEvent(interaction: kind, summary: summary, date: date)
        context.insert(event)
        event.associate = associate
        event.task = task
        associate.lastInteractionAt = date
        associate.updatedAt = date
    }

    // MARK: Saving

    static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Second Brain save failed: \(error)")
        }
        DataChange.notify()
    }

    static func touch(_ task: TaskItem, in context: ModelContext) {
        task.updatedAt = Date()
        save(context)
    }

    // MARK: Completion

    @discardableResult
    static func complete(_ task: TaskItem, notes: String? = nil, in context: ModelContext, now: Date = Date()) -> Bool {
        guard task.status != .completed else { return false }
        task.status = .completed
        task.completedAt = now
        task.updatedAt = now
        if let notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty { task.completionNotes = notes }
        log(.completed, notes?.isEmpty == false ? "Completed — \(notes!)" : "Completed", task: task, in: context, date: now)
        if task.kind == .followUp, let person = task.associate {
            logInteraction(.resolved, "Resolved: \(task.displayTitle)", associate: person, task: task, in: context, date: now)
        }
        if task.seriesID != nil {
            RecurrenceService.materialize(in: context, now: now, saving: false)
        }
        save(context)
        return true
    }

    static func reopen(_ task: TaskItem, in context: ModelContext) {
        guard task.status == .completed || task.status == .archived else { return }
        task.status = .notStarted
        task.completedAt = nil
        task.archivedAt = nil
        task.updatedAt = Date()
        log(.reopened, "Reopened", task: task, in: context)
        save(context)
    }

    static func setStatus(_ task: TaskItem, _ status: TaskStatus, in context: ModelContext) {
        guard task.status != status else { return }
        if status == .completed { complete(task, in: context); return }
        let old = task.status
        task.status = status
        if status == .archived { task.archivedAt = Date() }
        if old == .completed { task.completedAt = nil }
        task.updatedAt = Date()
        log(.statusChanged, "\(old.title) → \(status.title)", task: task, in: context)
        save(context)
    }

    // MARK: Scheduling

    static func reschedule(_ task: TaskItem, to day: Date, in context: ModelContext, reason: ActivityKind = .rescheduled, now: Date = Date()) {
        let result = Rescheduler.move(dueDate: task.dueDate, hasDueTime: task.hasDueTime, reminderDate: task.reminderDate,
                                      to: day, now: now, defaultReminderMinutes: AppSettings.effectiveDefaultReminderMinutes,
                                      calendar: .current)
        task.dueDate = result.dueDate
        task.hasDueTime = result.hasDueTime
        task.reminderDate = result.reminderDate
        if result.isPostponement { task.rescheduleCount += 1 }
        if task.status == .inbox { task.status = .notStarted }
        if task.status == .deferred { task.status = .notStarted }
        task.updatedAt = now
        let label = RelativeDateText.dayLabel(for: result.dueDate, now: now, calendar: .current)
        log(reason, reason == .carriedForward ? "Carried forward to \(label)" : "Moved to \(label)", task: task, in: context, date: now)
        reclassifyIfAutomatic(task, now: now)
        save(context)
    }

    /// Sets an exact due date from an editor (no postponement counting here; see `noteDueChange`).
    static func setDue(_ task: TaskItem, date: Date?, hasTime: Bool, in context: ModelContext) {
        task.dueDate = date
        task.hasDueTime = date != nil && hasTime
        task.updatedAt = Date()
        reclassifyIfAutomatic(task)
        save(context)
    }

    /// Called when an editor closes: records a postponement if the due date moved later.
    static func noteDueChange(_ task: TaskItem, from original: Date?, in context: ModelContext) {
        guard let original, let new = task.dueDate else { return }
        let cal = Calendar.current
        if cal.startOfDay(for: new) > cal.startOfDay(for: original) {
            task.rescheduleCount += 1
            log(.rescheduled, "Moved to \(RelativeDateText.dayLabel(for: new, now: Date(), calendar: cal))", task: task, in: context)
        }
    }

    static func snooze(_ task: TaskItem, option: SnoozeOption, in context: ModelContext, now: Date = Date()) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let date = option.date(from: now, morningMinutes: AppSettings.shiftStartMinutes(on: tomorrow), calendar: .current)
        snooze(task, until: date, label: option.title, in: context)
    }

    static func snooze(_ task: TaskItem, until date: Date, label: String? = nil, in context: ModelContext) {
        task.reminderDate = date
        task.updatedAt = Date()
        log(.snoozed, "Reminder snoozed \(label ?? RelativeDateText.dueText(due: date, hasTime: true, now: Date(), calendar: .current))", task: task, in: context)
        save(context)
    }

    static func carryForward(_ tasks: [TaskItem], to day: Date, in context: ModelContext) {
        let now = Date()
        for task in tasks where task.isOpen {
            let result = Rescheduler.move(dueDate: task.dueDate, hasDueTime: task.hasDueTime, reminderDate: task.reminderDate,
                                          to: day, now: now, defaultReminderMinutes: AppSettings.effectiveDefaultReminderMinutes,
                                          calendar: .current)
            task.dueDate = result.dueDate
            task.hasDueTime = result.hasDueTime
            task.reminderDate = result.reminderDate
            if result.isPostponement { task.rescheduleCount += 1 }
            if task.status == .inbox || task.status == .deferred { task.status = .notStarted }
            task.updatedAt = now
            log(.carriedForward, "Carried forward from End My Shift", task: task, in: context, date: now)
            reclassifyIfAutomatic(task, now: now)
        }
        save(context)
    }

    // MARK: Eisenhower

    static func setQuadrant(_ task: TaskItem, _ quadrant: Quadrant, in context: ModelContext) {
        let old = task.quadrant
        task.quadrant = quadrant
        task.classificationIsManual = true
        task.classificationReasons = "Set manually"
        if task.status == .inbox { task.status = .notStarted }
        task.updatedAt = Date()
        if old != quadrant {
            log(.quadrantChanged, "\(old.code) \(old.title) → \(quadrant.code) \(quadrant.title)", task: task, in: context)
        }
        save(context)
    }

    static func classification(for task: TaskItem, now: Date = Date()) -> EisenhowerClassification {
        EisenhowerClassifier.classify(ClassificationInput(
            text: [task.title, task.details, task.request, task.commitment].joined(separator: " "),
            category: task.category, kind: task.kind, priority: task.priority,
            dueDate: task.dueDate, hasDueTime: task.hasDueTime, now: now, calendar: .current))
    }

    static func apply(_ classification: EisenhowerClassification, to task: TaskItem) {
        task.isUrgent = classification.isUrgent
        task.isImportant = classification.isImportant
        task.classificationReasons = classification.reasons.joined(separator: "\n")
    }

    /// Re-runs the suggestion for tasks the person hasn't classified manually.
    static func reclassifyIfAutomatic(_ task: TaskItem, now: Date = Date()) {
        guard !task.classificationIsManual else { return }
        apply(classification(for: task, now: now), to: task)
    }

    /// Returns to automatic classification.
    static func useSuggestedQuadrant(_ task: TaskItem, in context: ModelContext) {
        let old = task.quadrant
        task.classificationIsManual = false
        apply(classification(for: task), to: task)
        if old != task.quadrant {
            log(.quadrantChanged, "Suggested: \(old.code) → \(task.quadrant.code)", task: task, in: context)
        }
        touch(task, in: context)
    }

    // MARK: Focus (Top 3)

    static func focusedTasks(on day: Date, in context: ModelContext) -> [TaskItem] {
        let cal = Calendar.current
        return openTasks(in: context)
            .filter { $0.focusDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { $0.focusRank < $1.focusRank }
    }

    /// Adds or removes a task from the day's three main priorities. Returns false when three are already chosen.
    @discardableResult
    static func toggleFocus(_ task: TaskItem, on day: Date = Date(), in context: ModelContext) -> Bool {
        let cal = Calendar.current
        if let f = task.focusDate, cal.isDate(f, inSameDayAs: day) {
            task.focusDate = nil
            task.focusRank = 0
            save(context)
            return true
        }
        let current = focusedTasks(on: day, in: context)
        guard current.count < 3 else { return false }
        task.focusDate = cal.startOfDay(for: day)
        task.focusRank = (current.map(\.focusRank).max() ?? 0) + 1
        save(context)
        return true
    }

    static func setFocus(_ tasks: [TaskItem], on day: Date, in context: ModelContext) {
        let cal = Calendar.current
        for t in focusedTasks(on: day, in: context) { t.focusDate = nil; t.focusRank = 0 }
        for (index, t) in tasks.prefix(3).enumerated() {
            t.focusDate = cal.startOfDay(for: day)
            t.focusRank = index + 1
        }
        save(context)
    }

    // MARK: Delegation

    static func delegate(_ task: TaskItem, to person: String, in context: ModelContext) {
        let name = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        task.delegatedTo = name
        task.delegationConfirmed = false
        task.status = .waiting
        task.waitingOn = name
        task.updatedAt = Date()
        log(.delegated, "Handed to \(name) — awaiting confirmation", task: task, in: context)
        save(context)
    }

    static func confirmDelegation(_ task: TaskItem, in context: ModelContext) {
        task.delegationConfirmed = true
        task.updatedAt = Date()
        log(.delegationConfirmed, "\(task.delegatedTo.isEmpty ? "Hand-off" : task.delegatedTo) confirmed", task: task, in: context)
        save(context)
    }

    // MARK: Lifecycle

    static func archive(_ task: TaskItem, in context: ModelContext) {
        setStatus(task, .archived, in: context)
    }

    @discardableResult
    static func duplicate(_ task: TaskItem, in context: ModelContext) -> TaskItem {
        let copy = TaskItem(title: task.title, kind: task.kind, status: task.status == .completed ? .notStarted : task.status)
        if copy.status == .archived { copy.status = .notStarted }
        copy.details = task.details
        copy.priority = task.priority
        copy.category = task.category
        copy.isUrgent = task.isUrgent
        copy.isImportant = task.isImportant
        copy.classificationIsManual = task.classificationIsManual
        copy.classificationReasons = task.classificationReasons
        copy.department = task.department
        copy.dueDate = task.dueDate
        copy.hasDueTime = task.hasDueTime
        copy.request = task.request
        copy.commitment = task.commitment
        context.insert(copy)
        copy.associate = task.associate
        for item in task.sortedSubtasks {
            let sub = ChecklistItem(text: item.text, sortIndex: item.sortIndex)
            context.insert(sub)
            sub.task = copy
        }
        log(.created, "Duplicated from “\(task.displayTitle)”", task: copy, in: context)
        save(context)
        return copy
    }

    /// Permanent deletion — only ever called after explicit confirmation in the UI.
    static func delete(_ task: TaskItem, in context: ModelContext) {
        if let seriesID = task.seriesID, !task.occurrenceKey.isEmpty,
           let series = RecurrenceService.series(with: seriesID, in: context) {
            series.addSkippedKey(task.occurrenceKey)
        }
        context.delete(task)
        save(context)
    }

    // MARK: Creation helpers

    @discardableResult
    static func createTask(title: String, kind: TaskKind = .task, due: Date? = nil, hasTime: Bool = false,
                           reminder: Date? = nil, associate: Associate? = nil, linkedFollowUpID: UUID? = nil,
                           in context: ModelContext) -> TaskItem {
        let task = TaskItem(title: title, kind: kind)
        task.dueDate = due
        task.hasDueTime = due != nil && hasTime
        task.reminderDate = reminder
        task.linkedFollowUpID = linkedFollowUpID
        context.insert(task)
        task.associate = associate
        if let associate { task.department = associate.department }
        apply(classification(for: task), to: task)
        log(.created, "Created", task: task, in: context)
        save(context)
        return task
    }

    @discardableResult
    static func convert(_ item: ChecklistItem, in context: ModelContext) -> TaskItem {
        let task = TaskItem(title: item.text)
        context.insert(task)
        if let parentTask = item.task {
            task.associate = parentTask.associate
            task.department = parentTask.department
            task.category = parentTask.category
            task.linkedFollowUpID = parentTask.kind == .followUp ? parentTask.id : parentTask.linkedFollowUpID
        }
        if let note = item.note {
            task.associate = note.associate
            task.department = note.department
            var links = note.linkedTasks ?? []
            links.append(task)
            note.linkedTasks = links
        }
        apply(classification(for: task), to: task)
        item.convertedTaskID = task.id
        log(.created, "Created from checklist item", task: task, in: context)
        save(context)
        return task
    }
}
