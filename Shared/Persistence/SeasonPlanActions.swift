import Foundation
import SwiftData
import SecondBrainCore

/// Remembers which season items were hidden and which prep steps were already added as tasks.
enum SeasonPlanStore {
    static func keys(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map(String.init))
    }

    static func joined(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: "\n")
    }

    static var addedKeys: Set<String> { keys(AppGroup.defaults.string(forKey: SettingsKey.seasonAdded) ?? "") }
    static var hiddenKeys: Set<String> { keys(AppGroup.defaults.string(forKey: SettingsKey.seasonHidden) ?? "") }

    static func markAdded(_ key: String) {
        var all = addedKeys
        all.insert(key)
        AppGroup.defaults.set(joined(all), forKey: SettingsKey.seasonAdded)
    }

    static func setHidden(_ key: String, _ hidden: Bool) {
        var all = hiddenKeys
        if hidden { all.insert(key) } else { all.remove(key) }
        AppGroup.defaults.set(joined(all), forKey: SettingsKey.seasonHidden)
    }
}

/// Turns a season prep step into a task — only when the person taps Add.
@MainActor
enum SeasonPlanActions {
    @discardableResult
    static func addTask(for step: PrepStep, in moment: RetailMoment, context: ModelContext, now: Date = Date()) -> TaskItem? {
        let calendar = Calendar.current
        let due = step.suggestedDue(for: moment, now: now, schedule: AppSettings.shiftSchedule, calendar: calendar)
        var draft = CaptureDraft()
        draft.rawText = step.title
        draft.title = step.title
        draft.kind = .task
        draft.details = details(for: moment, calendar: calendar)
        draft.department = step.department ?? ""
        draft.dueDate = due
        draft.hasDueTime = false
        draft.category = step.category
        if AppSettings.defaultReminderEnabled {
            let minutes = AppSettings.reminderAtShiftStart ? AppSettings.shiftStartMinutes(on: due) : AppSettings.defaultReminderMinutes
            let reminder = DateMath(calendar: calendar).addingMinutes(minutes, to: due)
            if reminder > now {
                draft.reminderDate = reminder
                draft.reminderIsDefault = true
            }
        }
        let classification = EisenhowerClassifier.classify(ClassificationInput(
            text: step.title + " " + moment.title, category: step.category, kind: .task, priority: .normal,
            dueDate: due, hasDueTime: false, now: now, calendar: calendar))
        draft.quadrant = classification.quadrant
        draft.classificationReasons = classification.reasons
        draft.isSafetyLocked = classification.isSafetyLocked
        guard case .task(let task)? = CaptureSaver.save(draft, in: context) else { return nil }
        SeasonPlanStore.markAdded(step.key)
        return task
    }

    static func details(for moment: RetailMoment, calendar: Calendar) -> String {
        var when = RelativeDateText.mediumDate(moment.start, calendar: calendar)
        if let end = moment.end { when += " – " + RelativeDateText.mediumDate(end, calendar: calendar) }
        return "From the Season Planner: \(moment.title), \(when). \(moment.certainty.label). \(moment.note)"
    }
}
