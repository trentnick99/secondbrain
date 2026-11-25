import AppIntents
import UserNotifications
import Foundation
import SwiftData
import SecondBrainCore

/// Completes a task. Used by the interactive widget checkboxes (runs in the widget process)
/// and available to the app.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks a Coach Spark task as complete.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Task Identifier")
    var taskID: String

    init() {
        self.taskID = ""
    }

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let context = PersistenceController.shared.mainContext
        if let task = TaskActions.task(with: id, in: context) {
            TaskActions.complete(task, in: context)
        }
        AppSettings.markExternalChange()
        // A widget runs outside the app, where reminders aren't resynced, so clear this task's
        // pending reminders here. The app reschedules everything the next time it opens.
        let kinds: [PlannedNotification.Kind] = [.reminder, .deadline, .overdue]
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: kinds.map { PlannedNotification.identifier(kind: $0, taskID: id) })
        return .result()
    }
}

/// Moves a task to your next shift. Used by the widget's arrow button (runs in the widget process).
struct MoveToNextShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "Move Task to Next Shift"
    static var description = IntentDescription("Moves a Coach Spark task to your next scheduled shift.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Task Identifier")
    var taskID: String

    init() {
        self.taskID = ""
    }

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let context = PersistenceController.shared.mainContext
        if let task = TaskActions.task(with: id, in: context) {
            TaskActions.carryForward([task], to: AppSettings.nextShiftDay(), in: context)
        }
        AppSettings.markExternalChange()
        // Its reminders were for the old time; the app schedules new ones the next time it opens.
        let kinds: [PlannedNotification.Kind] = [.reminder, .deadline, .overdue]
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: kinds.map { PlannedNotification.identifier(kind: $0, taskID: id) })
        return .result()
    }
}

/// Opens the Quick Capture sheet. Backs the Control Center / Action button control and Siri.
struct OpenQuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Capture"
    static var description = IntentDescription("Opens Coach Spark ready to capture a task, note or follow-up.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteRequest.post(DeepLink.capture)
        return .result()
    }
}

/// Opens the floor walk checklist. Backs the Control Center control.
struct OpenFloorWalkIntent: AppIntent {
    static var title: LocalizedStringResource = "Floor Walk"
    static var description = IntentDescription("Opens the floor walk checklist for your areas.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteRequest.post(DeepLink.floorWalk)
        return .result()
    }
}

/// Opens Import ready to speak walk notes. Backs the Control Center control.
struct OpenWalkNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Walk Notes"
    static var description = IntentDescription("Opens Coach Spark listening for walk notes.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteRequest.post(DeepLink.walkNotes)
        return .result()
    }
}

/// Hands a navigation request to the app, whether the request comes from an intent running in the
/// app process or from another process (stored until the app becomes active).
enum RouteRequest {
    static let key = "pendingRouteURL"
    static let notification = Notification.Name("SecondBrainRouteRequest")

    static func post(_ url: URL) {
        AppGroup.defaults.set(url.absoluteString, forKey: key)
        NotificationCenter.default.post(name: notification, object: url)
    }

    /// Returns and clears the pending route, if any.
    static func take() -> URL? {
        guard let string = AppGroup.defaults.string(forKey: key) else { return nil }
        AppGroup.defaults.removeObject(forKey: key)
        return URL(string: string)
    }
}
