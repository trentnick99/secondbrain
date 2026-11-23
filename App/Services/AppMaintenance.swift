import BackgroundTasks
import Foundation
import SwiftData
import WidgetKit

/// Routine upkeep run at launch, on returning to the foreground, after data changes, and during
/// opportunistic background refreshes. iOS decides if and when background refresh runs, so nothing
/// essential depends on it — reminders are always scheduled ahead of time.
@MainActor
enum AppMaintenance {
    static var refreshTaskIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.example.secondbrain") + ".refresh"
    }

    private static var widgetReload: Task<Void, Never>?

    static func configure() {
        DataChange.handlers = [
            { NotificationService.shared.requestResync() },
            { AppMaintenance.requestWidgetReload() }
        ]
    }

    /// Launch / foreground: create recurring occurrences, reschedule notifications, refresh widgets.
    static func runForegroundUpkeep() async {
        let context = PersistenceController.shared.mainContext
        RecurrenceService.materialize(in: context)
        await NotificationService.shared.resyncNow()
        WidgetCenter.shared.reloadAllTimelines()
        scheduleBackgroundRefresh()
    }

    static func runBackgroundRefresh() async {
        let context = PersistenceController.shared.mainContext
        RecurrenceService.materialize(in: context)
        await NotificationService.shared.resyncNow()
        WidgetCenter.shared.reloadAllTimelines()
        BackupService.writeAutomaticBackup(from: context)
        scheduleBackgroundRefresh()
    }

    static func requestWidgetReload() {
        widgetReload?.cancel()
        widgetReload = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Asks iOS for a refresh early tomorrow so the next week of recurring tasks and reminders stays scheduled.
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        request.earliestBeginDate = cal.date(byAdding: .hour, value: 3, to: tomorrow)
        try? BGTaskScheduler.shared.submit(request)
    }
}
