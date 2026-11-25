import Foundation
import Observation
import WatchConnectivity

struct WatchItem: Identifiable, Hashable {
    let id: String
    let title: String
    let safety: Bool
}

/// Talks to the iPhone app. Keys must match `WatchSyncService` in the iPhone app.
@MainActor
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()

    private(set) var items: [WatchItem] = []
    private(set) var shiftLabel = ""
    private(set) var shiftEnd: Date?
    private(set) var done = 0
    private(set) var total = 0
    private(set) var updated: Date?

    private var waiting: [[String: Any]] = []
    private static let savedKey = "lastContext"

    override init() {
        super.init()
        apply(UserDefaults.standard.dictionary(forKey: Self.savedKey) ?? [:], save: false)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Marks an item done (after the person confirmed on the watch); the iPhone completes the task.
    func complete(_ item: WatchItem) {
        items.removeAll { $0.id == item.id }
        done += 1
        send(["action": "complete", "id": item.id])
    }

    /// Sends a note to be saved in Notes on the iPhone, exactly as written.
    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(["action": "note", "text": trimmed])
    }

    private func send(_ info: [String: Any]) {
        guard WCSession.isSupported() else { return }
        if WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(info)   // queued and delivered even if the iPhone is away
        } else {
            waiting.append(info)
        }
    }

    private func apply(_ context: [String: Any], save: Bool = true) {
        guard !context.isEmpty else { return }
        if save { UserDefaults.standard.set(context, forKey: Self.savedKey) }
        shiftLabel = context["shift"] as? String ?? ""
        let end = context["end"] as? Double ?? 0
        shiftEnd = end > 0 ? Date(timeIntervalSince1970: end) : nil
        done = context["done"] as? Int ?? 0
        total = context["total"] as? Int ?? 0
        let stamp = context["updated"] as? Double ?? 0
        updated = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        items = (context["items"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let id = raw["id"] as? String, let title = raw["title"] as? String else { return nil }
            return WatchItem(id: id, title: title, safety: raw["safety"] as? Bool ?? false)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.apply(context)
            if activationState == .activated {
                for info in self.waiting { session.transferUserInfo(info) }
                self.waiting.removeAll()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}
