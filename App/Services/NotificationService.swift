import Foundation
import SwiftData
import UserNotifications
import SecondBrainCore

/// Identifiers for notification categories and actions.
enum NotificationIDs {
    static let taskCategory = "TASK_ACTIONS"
    static let briefingCategory = "BRIEFING"
    static let complete = "COMPLETE"
    static let snooze15 = "SNOOZE_15"
    static let snooze60 = "SNOOZE_60"
    static let snoozeTomorrow = "SNOOZE_TOMORROW"
    static let open = "OPEN"
    static let managedPrefixes = ["task.", "briefing."]
}

/// Schedules local notifications from the planner's output.
///
/// Reminders do not depend on a network connection or on background execution: everything is scheduled
/// ahead of time with calendar triggers, and the full plan is recomputed (debounced) whenever tasks
/// change, the app becomes active, a notification action runs, or a background refresh occurs.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var pendingResync: Task<Void, Never>?
    private(set) var lastPlanCount = 0

    // MARK: Setup

    func registerCategories() {
        let complete = UNNotificationAction(identifier: NotificationIDs.complete, title: "Mark Complete", options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let snooze15 = UNNotificationAction(identifier: NotificationIDs.snooze15, title: "Snooze 15 Minutes", options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "clock"))
        let snooze60 = UNNotificationAction(identifier: NotificationIDs.snooze60, title: "Snooze 1 Hour", options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
        let tomorrow = UNNotificationAction(identifier: NotificationIDs.snoozeTomorrow, title: "Tomorrow Morning", options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "sunrise"))
        let open = UNNotificationAction(identifier: NotificationIDs.open, title: "Open Task", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "arrow.up.forward.app"))
        let taskCategory = UNNotificationCategory(identifier: NotificationIDs.taskCategory,
                                                  actions: [complete, snooze15, snooze60, tomorrow, open],
                                                  intentIdentifiers: [],
                                                  hiddenPreviewsBodyPlaceholder: "Coach Spark reminder",
                                                  options: [])
        let briefingCategory = UNNotificationCategory(identifier: NotificationIDs.briefingCategory, actions: [],
                                                      intentIdentifiers: [],
                                                      hiddenPreviewsBodyPlaceholder: "Daily briefing",
                                                      options: [])
        center.setNotificationCategories([taskCategory, briefingCategory])
    }

    // MARK: Permission (asked once, from onboarding or Settings — never repeatedly)

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Requests permission only if iOS hasn't asked yet. Returns whether notifications are allowed.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .notDetermined:
            AppGroup.defaults.set(true, forKey: SettingsKey.notificationPermissionAsked)
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { await resyncNow() }
            return granted
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: Scheduling

    /// Coalesces bursts of edits into one reschedule.
    func requestResync() {
        pendingResync?.cancel()
        pendingResync = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.resyncNow()
        }
    }

    func resyncNow(now: Date = Date()) async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let context = PersistenceController.shared.mainContext
        let snapshots = TaskActions.openTasks(in: context).map(\.snapshot)
        let plan = NotificationPlanner.plan(tasks: snapshots, preferences: AppSettings.notificationPreferences,
                                            now: now, calendar: .current)
        let desired = Set(plan.map(\.id))

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { id in
            NotificationIDs.managedPrefixes.contains { id.hasPrefix($0) } && !desired.contains(id)
        }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        for item in plan {
            // Adding a request with an existing identifier replaces it, so edits take effect.
            let request = makeRequest(item)
            try? await center.add(request)
        }
        lastPlanCount = plan.count

        // Badge = items needing attention today (overdue + Q1), when enabled.
        let badge: Int
        if AppSettings.showBadge {
            badge = DayAgenda.build(tasks: snapshots, day: now, now: now, calendar: .current).priorityCount
        } else {
            badge = 0
        }
        try? await center.setBadgeCount(badge)
    }

    private func makeRequest(_ item: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.threadIdentifier = item.threadID
        content.categoryIdentifier = item.hasTaskActions ? NotificationIDs.taskCategory : NotificationIDs.briefingCategory
        var info: [String: String] = ["kind": item.kind.rawValue]
        if let id = item.taskID { info["taskID"] = id.uuidString }
        content.userInfo = info
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    /// Sends a test notification in 5 seconds so the person can confirm alerts work.
    func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "Coach Spark"
        content.body = "Notifications are working. Reminders will arrive like this."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "test.\(UUID().uuidString)", content: content, trigger: trigger))
    }
}

/// Receives notification taps and actions. Kept separate from the app delegate so its callbacks are
/// not main-actor isolated; work hops to the main actor explicitly.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            await NotificationActionHandler.handle(action: action, identifier: identifier)
            completionHandler()
        }
    }
}

/// Applies notification actions to the data.
@MainActor
enum NotificationActionHandler {
    static func handle(action: String, identifier: String) async {
        if identifier.hasPrefix("briefing.") {
            AppRouter.shared.open(.tab(.home))
            return
        }
        guard let taskID = PlannedNotification.taskID(fromIdentifier: identifier) else { return }
        let context = PersistenceController.shared.mainContext
        guard let task = TaskActions.task(with: taskID, in: context) else { return }

        switch action {
        case NotificationIDs.complete:
            TaskActions.complete(task, in: context)
        case NotificationIDs.snooze15:
            TaskActions.snooze(task, option: .fifteenMinutes, in: context)
        case NotificationIDs.snooze60:
            TaskActions.snooze(task, option: .oneHour, in: context)
        case NotificationIDs.snoozeTomorrow:
            TaskActions.snooze(task, option: .tomorrowMorning, in: context)
        case NotificationIDs.open, UNNotificationDefaultActionIdentifier:
            AppRouter.shared.open(.task(taskID))
        default:
            break
        }
        await NotificationService.shared.resyncNow()
    }
}
