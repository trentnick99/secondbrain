@_exported import SecondBrainCore
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct SecondBrainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter.shared
    @State private var lock = AppLock.shared

    init() {
        AppMaintenance.configure()
        if PersistenceController.isUITesting {
            AppGroup.defaults.set(true, forKey: SettingsKey.hasCompletedOnboarding)
            AppGroup.defaults.set(false, forKey: SettingsKey.appLockEnabled)
            if ProcessInfo.processInfo.arguments.contains("-sampleData") {
                SampleData.load(into: PersistenceController.shared.mainContext)
            }
        }
        AppLock.shared.lockIfEnabled()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(lock)
                .onOpenURL { url in router.open(url: url) }
                .task {
                    // Test runs only: `-openURL secondbrain://…` opens a screen at launch (used for screenshots).
                    guard PersistenceController.isUITesting else { return }
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-openURL"), i + 1 < args.count, let url = URL(string: args[i + 1]) {
                        try? await Task.sleep(for: .seconds(2.5))
                        router.open(url: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: RouteRequest.notification)) { _ in
                    if let url = RouteRequest.take() { router.open(url: url) }
                }
        }
        .modelContainer(PersistenceController.shared)
        .onChange(of: scenePhase) { _, phase in
            handle(phase)
        }
        .backgroundTask(.appRefresh(AppMaintenance.refreshTaskIdentifier)) {
            await AppMaintenance.runBackgroundRefresh()
        }
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if let url = RouteRequest.take() { router.open(url: url) }
            CalendarService.shared.refresh()
            Task { await AppMaintenance.runForegroundUpkeep() }
        case .background:
            BackupService.writeAutomaticBackup(from: PersistenceController.shared.mainContext)
            AppLock.shared.lockIfEnabled()
            AppMaintenance.scheduleBackgroundRefresh()
        default:
            break
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The delegate must be set before launch finishes so actions tapped while the app was
        // closed (Mark Complete, Snooze) are delivered.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationService.shared.registerCategories()
        return true
    }
}
