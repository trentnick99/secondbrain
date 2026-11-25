import Foundation
import SwiftData
import SecondBrainCore

typealias ChecklistItem = SchemaV1.ChecklistItem

extension SchemaV1 {
    /// A checklist line belonging to a task (subtask) or a note. Can be converted into a task.
    @Model
    final class ChecklistItem {
        var id: UUID = UUID()
        var text: String = ""
        var isDone: Bool = false
        var sortIndex: Int = 0
        var createdAt: Date = Date()
        var convertedTaskID: UUID? = nil

        var task: TaskItem?
        var note: Note?

        init(text: String, sortIndex: Int = 0) {
            self.id = UUID()
            self.text = text
            self.sortIndex = sortIndex
            self.createdAt = Date()
        }
    }
}

typealias RecurrenceSeries = SchemaV1.RecurrenceSeries

extension SchemaV1 {
    /// The definition of a recurring responsibility. Occurrences are materialized as `TaskItem`s
    /// (with `seriesID` + `occurrenceKey`) a week ahead so they appear in planners and get reminders.
    @Model
    final class RecurrenceSeries {
        var id: UUID = UUID()
        var title: String = ""
        var details: String = ""
        var kindRaw: String = TaskKind.task.rawValue
        var categoryRaw: String = TaskCategory.general.rawValue
        var priorityRaw: String = TaskPriority.normal.rawValue
        var isUrgent: Bool = false
        var isImportant: Bool = true
        var classificationIsManual: Bool = false
        var department: String = ""
        /// JSON-encoded `RecurrenceRule`.
        var ruleJSON: String = ""
        /// First eligible day of the series.
        var anchorDate: Date = Date()
        var hasTime: Bool = false
        var timeMinutes: Int = 9 * 60
        var remind: Bool = true
        var isPaused: Bool = false
        var isDiscontinued: Bool = false
        /// Occurrence keys (yyyy-MM-dd) the person skipped or deleted, so they are not recreated.
        var skippedKeys: String = ""
        var lastGeneratedKey: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        var associate: Associate?

        init(title: String, rule: RecurrenceRule, anchorDate: Date) {
            self.id = UUID()
            self.title = title
            self.anchorDate = anchorDate
            self.createdAt = Date()
            self.updatedAt = Date()
            self.ruleJSON = RecurrenceSeries.encode(rule)
        }

        static func encode(_ rule: RecurrenceRule) -> String {
            guard let data = try? JSONEncoder().encode(rule) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }

        var rule: RecurrenceRule? {
            get {
                guard let data = ruleJSON.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
            }
            set {
                guard let newValue else { ruleJSON = ""; return }
                ruleJSON = RecurrenceSeries.encode(newValue)
            }
        }

        var kind: TaskKind {
            get { TaskKind(rawValue: kindRaw) ?? .task }
            set { kindRaw = newValue.rawValue }
        }

        var category: TaskCategory {
            get { TaskCategory(rawValue: categoryRaw) ?? .general }
            set { categoryRaw = newValue.rawValue }
        }

        var priority: TaskPriority {
            get { TaskPriority(rawValue: priorityRaw) ?? .normal }
            set { priorityRaw = newValue.rawValue }
        }

        var quadrant: Quadrant {
            get { Quadrant(urgent: isUrgent, important: isImportant) }
            set { isUrgent = newValue.isUrgent; isImportant = newValue.isImportant }
        }

        var isActive: Bool { !isPaused && !isDiscontinued }

        var skippedKeySet: Set<String> {
            Set(skippedKeys.split(separator: ",").map { String($0) })
        }

        func addSkippedKey(_ key: String) {
            var set = skippedKeySet
            set.insert(key)
            skippedKeys = set.sorted().joined(separator: ",")
        }

        func summary(calendar: Calendar = .current) -> String {
            guard let rule else { return "Repeats" }
            var text = rule.summary(calendar: calendar)
            if hasTime { text += " at " + RelativeDateText.minutesText(timeMinutes, calendar: calendar) }
            return text
        }
    }
}

typealias ActivityEvent = SchemaV1.ActivityEvent

extension SchemaV1 {
    /// Task history and associate interaction history.
    @Model
    final class ActivityEvent {
        var id: UUID = UUID()
        var date: Date = Date()
        /// An `ActivityKind` raw value (task history) or `InteractionKind` raw value (interactions).
        var kindRaw: String = ""
        var isInteraction: Bool = false
        var summary: String = ""

        var task: TaskItem?
        var associate: Associate?

        init(kind: ActivityKind, summary: String, date: Date = Date()) {
            self.id = UUID()
            self.kindRaw = kind.rawValue
            self.summary = summary
            self.date = date
            self.isInteraction = false
        }

        init(interaction: InteractionKind, summary: String, date: Date = Date()) {
            self.id = UUID()
            self.kindRaw = interaction.rawValue
            self.summary = summary
            self.date = date
            self.isInteraction = true
        }

        var title: String {
            if isInteraction { return InteractionKind(rawValue: kindRaw)?.title ?? "Interaction" }
            return ActivityKind(rawValue: kindRaw)?.title ?? "Activity"
        }

        var systemImage: String {
            if isInteraction { return InteractionKind(rawValue: kindRaw)?.systemImage ?? "bubble.left" }
            return ActivityKind(rawValue: kindRaw)?.systemImage ?? "clock"
        }
    }
}

typealias ShiftLog = SchemaV1.ShiftLog

extension SchemaV1 {
    /// A record of each End My Shift review.
    @Model
    final class ShiftLog {
        var id: UUID = UUID()
        var day: Date = Date()
        var endedAt: Date = Date()
        var completedCount: Int = 0
        var carriedForwardCount: Int = 0
        var openCommitments: Int = 0
        var reflection: String = ""

        init(day: Date) {
            self.id = UUID()
            self.day = day
            self.endedAt = Date()
        }
    }
}
