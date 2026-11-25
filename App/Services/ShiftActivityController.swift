import ActivityKit
import Foundation
import SwiftData
import SecondBrainCore

/// Starts, updates and ends the shift Live Activity. It starts when the app is opened from 30 minutes
/// before a shift until its end (iOS only allows starting one from the app), and updates as tasks change.
/// iOS ends Live Activities after about 8 hours, so a 10-hour shift's activity may end early.
@MainActor
enum ShiftActivityController {
    private static var pending: Task<Void, Never>?

    static var isEnabled: Bool {
        AppGroup.defaults.bool(forKey: SettingsKey.shiftLiveActivity, default: true)
    }

    /// Debounced refresh after data changes.
    static func requestRefresh() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            refresh(in: PersistenceController.shared.mainContext)
        }
    }

    static func refresh(in context: ModelContext, now: Date = Date()) {
        guard !PersistenceController.isUITesting else { return }
        let running = Activity<ShiftActivityAttributes>.activities
        guard isEnabled, !AppGroup.defaults.bool(forKey: SettingsKey.offDuty), ActivityAuthorizationInfo().areActivitiesEnabled,
              let window = AppSettings.shiftWindow(on: now),
              now >= window.start.addingTimeInterval(-30 * 60), now < window.end else {
            end(running)
            return
        }
        let content = ActivityContent(state: state(in: context, now: now), staleDate: window.end)
        if let current = running.first(where: { $0.attributes.end == window.end }) {
            end(running.filter { $0.id != current.id })
            Task { await current.update(content) }
        } else {
            end(running)
            let label = AppSettings.shiftSchedule.shift(on: now, calendar: .current).map { "Shift \($0.shortLabel)" } ?? "Shift"
            let attributes = ShiftActivityAttributes(shiftLabel: label, start: window.start, end: window.end)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    static func endAll() {
        end(Activity<ShiftActivityAttributes>.activities)
    }

    private static func end(_ activities: [Activity<ShiftActivityAttributes>]) {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func state(in context: ModelContext, now: Date) -> ShiftActivityAttributes.ContentState {
        let snapshots = TaskActions.allTasks(in: context).map(\.snapshot)
        let agenda = DayAgenda.build(tasks: snapshots, day: now, now: now, calendar: .current)
        let done = agenda.completedToday.count
        var seen = Set<UUID>()
        let top = (agenda.topPriorities + agenda.overdue + agenda.urgentImportant + agenda.suggestedPriorities)
            .filter { $0.isOpen && seen.insert($0.id).inserted }
            .prefix(3)
            .map(\.title)
        return .init(priorities: Array(top), done: done,
                     total: done + agenda.dueToday.count + agenda.overdue.count, overdue: agenda.overdue.count)
    }
}
