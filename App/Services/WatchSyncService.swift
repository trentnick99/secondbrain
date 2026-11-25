import Foundation
import SwiftData
import WatchConnectivity
import SecondBrainCore

/// Keeps the Apple Watch app up to date with today's top three, and handles what the watch sends:
/// marking a task done (confirmed on the watch) and quick notes (saved exactly as written).
/// Keys must match `WatchStore` in the watch app.
@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private var pending: Task<Void, Never>?

    func activate() {
        guard WCSession.isSupported(), !PersistenceController.isUITesting else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Debounced push after data changes.
    func requestPush() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            push()
        }
    }

    func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(Self.payload(in: PersistenceController.shared.mainContext))
    }

    static func payload(in context: ModelContext, now: Date = Date()) -> [String: Any] {
        let tasks = TaskActions.allTasks(in: context).map(\.snapshot)
        let top = Huddle.topThree(tasks: tasks, now: now, calendar: .current)
        let state = ShiftActivityController.state(in: context, now: now)
        let window = AppSettings.shiftWindow(on: now)
        let label = AppSettings.shiftSchedule.shift(on: now, calendar: .current).map { "Shift \($0.shortLabel)" } ?? ""
        return [
            "updated": now.timeIntervalSince1970,
            "shift": label,
            "end": window?.end.timeIntervalSince1970 ?? 0,
            "done": state.done,
            "total": state.total,
            "items": top.map { ["id": $0.id.uuidString, "title": $0.title, "safety": $0.category == .safety] as [String: Any] }
        ]
    }

    private func handle(action: String?, id: String?, text: String?) {
        let context = PersistenceController.shared.mainContext
        switch action {
        case "complete":
            if let id, let uuid = UUID(uuidString: id),
               let task = TaskActions.allTasks(in: context).first(where: { $0.id == uuid }), task.status.isOpen {
                _ = TaskActions.complete(task, in: context)
            }
        case "note":
            if let text { QuickNoteSaver.save(text, in: context) }
        default:
            break
        }
        push()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()   // switching to another paired watch
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let action = userInfo["action"] as? String
        let id = userInfo["id"] as? String
        let text = userInfo["text"] as? String
        Task { @MainActor in self.handle(action: action, id: id, text: text) }
    }
}
