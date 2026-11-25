import Foundation
import SwiftData
import SecondBrainCore

/// Fetches shared by screens and tests, so a screen and its performance test ask the store the same thing.
enum TaskQueries {
    /// What Home needs: every open task, plus anything finished or archived since the start of
    /// yesterday (for "completed today", with a day's slack across midnight). A year of finished work
    /// stays in the store and never has to be loaded to draw Home.
    static func homePredicate(now: Date = Date(), calendar: Calendar = .current) -> Predicate<TaskItem> {
        let cutoff = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let completed = TaskStatus.completed.rawValue
        let archived = TaskStatus.archived.rawValue
        let never = Date.distantPast
        return #Predicate<TaskItem> { task in
            (task.statusRaw != completed && task.statusRaw != archived) || (task.completedAt ?? never) >= cutoff
        }
    }

    static func home(now: Date = Date(), calendar: Calendar = .current) -> FetchDescriptor<TaskItem> {
        FetchDescriptor(predicate: homePredicate(now: now, calendar: calendar),
                        sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }
}
