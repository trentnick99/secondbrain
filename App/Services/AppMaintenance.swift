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
            { AppMaintenance.requestWidgetReload() },
            { ShiftActivityController.requestRefresh() },
            { WatchSyncService.shared.requestPush() }
        ]
        WatchSyncService.shared.activate()
    }

    /// Launch / foreground: create recurring occurrences, reschedule notifications, refresh widgets.
    static func runForegroundUpkeep() async {
        let context = PersistenceController.shared.mainContext
        RecurrenceService.materialize(in: context)
        await NotificationService.shared.resyncNow()
        WidgetCenter.shared.reloadAllTimelines()
        ShiftActivityController.refresh(in: context)
        WatchSyncService.shared.push()
        scheduleBackgroundRefresh()
        await ShiftPlanNotifier.reschedule()
        await WeatherAlertService.shared.refresh()
    }

    static func runBackgroundRefresh() async {
        let context = PersistenceController.shared.mainContext
        RecurrenceService.materialize(in: context)
        await NotificationService.shared.resyncNow()
        WidgetCenter.shared.reloadAllTimelines()
        BackupService.writeAutomaticBackup(from: context)
        ShiftActivityController.refresh(in: context)
        if WeatherAlertService.isEnabled { await WeatherAlertService.shared.checkAndNotify() }
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
    /// With weather alerts on, it asks for refreshes about every 30 minutes around the shift instead.
    /// iOS still decides when (and whether) they run.
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        let cal = Calendar.current
        let now = Date()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        var next = cal.date(byAdding: .hour, value: 3, to: tomorrow)
        if WeatherAlertService.isEnabled, let window = AppSettings.shiftWindow(on: now) {
            let watchStart = window.start.addingTimeInterval(-3600)
            if now < watchStart {
                next = watchStart
            } else if now < window.end {
                next = now.addingTimeInterval(30 * 60)
            }
        }
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
    }
}
