import SwiftUI

/// Coach Spark on Apple Watch: today's top three from the iPhone, mark one done, and send a
/// quick note. The iPhone app does the saving; the watch only shows and sends.
@main
struct SecondBrainWatchApp: App {
    init() {
        WatchStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}
