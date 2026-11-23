import AppIntents
import Foundation
import SwiftData
import SecondBrainCore

/// Completes a task. Used by the interactive widget checkboxes (runs in the widget process)
/// and available to the app.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks a Second Brain task as complete.")
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
        return .result()
    }
}

/// Opens the Quick Capture sheet. Backs the Control Center / Action button control and Siri.
struct OpenQuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Capture"
    static var description = IntentDescription("Opens Second Brain ready to capture a task, note or follow-up.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteRequest.post(DeepLink.capture)
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
