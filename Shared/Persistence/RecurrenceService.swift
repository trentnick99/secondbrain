import Foundation
import SwiftData
import SecondBrainCore

/// Turns recurring definitions into concrete task occurrences.
///
/// * Occurrences are materialized one week ahead (plus the next one for long intervals) so they show
///   up in planners and their reminders can be scheduled in advance.
/// * Each occurrence carries `seriesID` + `occurrenceKey` (yyyy-MM-dd); an occurrence is never created
///   twice, and skipped / deleted occurrences are remembered so they are not recreated.
/// * Missed days are not back-filled; the latest unfinished occurrence simply stays overdue.
@MainActor
enum RecurrenceService {
    static let horizonDays = 7

    static func series(with id: UUID, in context: ModelContext) -> RecurrenceSeries? {
        let target = id
        var descriptor = FetchDescriptor<RecurrenceSeries>(predicate: #Predicate<RecurrenceSeries> { $0.id == target })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func allSeries(in context: ModelContext) -> [RecurrenceSeries] {
        (try? context.fetch(FetchDescriptor<RecurrenceSeries>(sortBy: [SortDescriptor(\RecurrenceSeries.title)]))) ?? []
    }

    static func occurrences(of series: RecurrenceSeries, in context: ModelContext) -> [TaskItem] {
        let target: UUID? = series.id
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.seriesID == target })
        return ((try? context.fetch(descriptor)) ?? []).sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    /// Creates any missing occurrences up to the horizon. Safe to call often (launch, foreground,
    /// background refresh, after edits).
    @discardableResult
    static func materialize(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current, saving: Bool = true) -> Int {
        let math = DateMath(calendar: calendar)
        let today = math.startOfDay(now)
        let horizon = math.addingDays(horizonDays, to: today)
        let allTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []

        var keysBySeries: [UUID: Set<String>] = [:]
        var openBySeries: [UUID: Int] = [:]
        for task in allTasks {
            guard let sid = task.seriesID else { continue }
            keysBySeries[sid, default: []].insert(task.occurrenceKey)
            if task.isOpen, let due = task.dueDate, due >= today { openBySeries[sid, default: 0] += 1 }
        }

        var created = 0
        for series in allSeries(in: context) where series.isActive {
            guard let rule = series.rule else { continue }
            let anchor = math.startOfDay(series.anchorDate)
            let from = max(anchor, today)
            var dates = rule.occurrences(from: from, to: horizon, anchor: anchor, calendar: calendar)
            // Long intervals (e.g. monthly): always keep the next occurrence visible.
            if dates.isEmpty && (openBySeries[series.id] ?? 0) == 0,
               let next = rule.firstOccurrence(onOrAfter: from, anchor: anchor, calendar: calendar) {
                dates = [next]
            }
            let skipped = series.skippedKeySet
            for day in dates {
                let key = NotificationPlanner.dayKey(day, calendar: calendar)
                if keysBySeries[series.id]?.contains(key) == true || skipped.contains(key) { continue }
                makeOccurrence(of: series, on: day, key: key, now: now, calendar: calendar, in: context)
                keysBySeries[series.id, default: []].insert(key)
                series.lastGeneratedKey = key
                created += 1
            }
        }
        let removed = removeDuplicateOccurrences(in: context)
        if saving && (created > 0 || removed > 0) {
            TaskActions.save(context)
        }
        return created
    }

    private static func makeOccurrence(of series: RecurrenceSeries, on day: Date, key: String, now: Date,
                                       calendar: Calendar, in context: ModelContext) {
        let math = DateMath(calendar: calendar)
        let task = TaskItem(title: series.title, kind: series.kind)
        task.details = series.details
        task.category = series.category
        task.priority = series.priority
        task.department = series.department
        task.seriesID = series.id
        task.occurrenceKey = key
        if series.hasTime {
            task.dueDate = math.date(on: day, minutes: series.timeMinutes)
            task.hasDueTime = true
        } else {
            task.dueDate = day
            task.hasDueTime = false
        }
        if series.remind {
            let minutes = series.hasTime ? series.timeMinutes : AppSettings.effectiveDefaultReminderMinutes
            if let minutes {
                let reminder = math.date(on: day, minutes: minutes)
                if reminder > now { task.reminderDate = reminder }
            }
        }
        context.insert(task)
        task.associate = series.associate
        if series.classificationIsManual {
            task.isUrgent = series.isUrgent
            task.isImportant = series.isImportant
            task.classificationIsManual = true
            task.classificationReasons = "Set on the recurring series"
        } else {
            TaskActions.apply(TaskActions.classification(for: task, now: now), to: task)
        }
        TaskActions.log(.created, "Recurring occurrence — \(series.summary(calendar: calendar))", task: task, in: context, date: now)
    }

    /// Duplicate (seriesID, occurrenceKey) pairs can appear after an iCloud merge from two devices.
    /// Keeps the completed or oldest copy and removes untouched extras only.
    @discardableResult
    static func removeDuplicateOccurrences(in context: ModelContext) -> Int {
        let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { $0.seriesID != nil && !$0.occurrenceKey.isEmpty }
        var groups: [String: [TaskItem]] = [:]
        for t in tasks { groups["\(t.seriesID!.uuidString)|\(t.occurrenceKey)", default: []].append(t) }
        var removed = 0
        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { a, b in
                if a.isCompleted != b.isCompleted { return a.isCompleted }
                return a.createdAt < b.createdAt
            }
            for extra in sorted.dropFirst() where extra.status == .notStarted && extra.updatedAt.timeIntervalSince(extra.createdAt) < 2 {
                context.delete(extra)
                removed += 1
            }
        }
        return removed
    }

    // MARK: Series management

    static func pause(_ series: RecurrenceSeries, in context: ModelContext) {
        series.isPaused = true
        series.updatedAt = Date()
        removeFutureUntouchedOccurrences(of: series, in: context)
        TaskActions.save(context)
    }

    static func resume(_ series: RecurrenceSeries, in context: ModelContext) {
        series.isPaused = false
        series.updatedAt = Date()
        materialize(in: context, saving: false)
        TaskActions.save(context)
    }

    /// Stops the series. Past and current occurrences (and their history) are kept.
    static func discontinue(_ series: RecurrenceSeries, in context: ModelContext) {
        series.isDiscontinued = true
        series.updatedAt = Date()
        removeFutureUntouchedOccurrences(of: series, in: context)
        TaskActions.save(context)
    }

    /// Applies template edits to upcoming open occurrences.
    static func applyEdits(_ series: RecurrenceSeries, in context: ModelContext) {
        series.updatedAt = Date()
        let today = Calendar.current.startOfDay(for: Date())
        for task in occurrences(of: series, in: context) where task.isOpen && (task.dueDate ?? .distantPast) >= today {
            task.title = series.title
            task.details = series.details
            task.category = series.category
            task.priority = series.priority
            task.associate = series.associate
            task.updatedAt = Date()
        }
        // Rebuild future untouched occurrences so time / rule changes take effect.
        removeFutureUntouchedOccurrences(of: series, in: context)
        materialize(in: context, saving: false)
        TaskActions.save(context)
    }

    private static func removeFutureUntouchedOccurrences(of series: RecurrenceSeries, in context: ModelContext) {
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        for task in occurrences(of: series, in: context) {
            guard task.status == .notStarted, let due = task.dueDate, due >= endOfToday else { continue }
            guard task.updatedAt.timeIntervalSince(task.createdAt) < 2 else { continue }
            context.delete(task)
        }
    }

    /// Creates a series from a confirmed capture and materializes its first occurrences.
    @discardableResult
    static func createSeries(title: String, details: String, rule: RecurrenceRule, anchor: Date, timeMinutes: Int?,
                             kind: TaskKind, category: TaskCategory, priority: TaskPriority, quadrant: Quadrant?,
                             associate: Associate?, department: String, in context: ModelContext) -> RecurrenceSeries {
        let series = RecurrenceSeries(title: title, rule: rule, anchorDate: Calendar.current.startOfDay(for: anchor))
        series.details = details
        series.kind = kind
        series.category = category
        series.priority = priority
        series.department = department
        if let minutes = timeMinutes {
            series.hasTime = true
            series.timeMinutes = minutes
        }
        if let quadrant {
            series.quadrant = quadrant
            series.classificationIsManual = true
        }
        context.insert(series)
        series.associate = associate
        materialize(in: context, saving: false)
        TaskActions.save(context)
        return series
    }
}
