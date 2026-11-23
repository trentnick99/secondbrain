import Foundation
import SecondBrainCore

/// UserDefaults keys. Views bind with `@AppStorage(key, store: AppGroup.defaults)`.
enum SettingsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let shiftStartMinutes = "shiftStartMinutes"
    static let shiftEndMinutes = "shiftEndMinutes"
    static let weekStartsOn = "weekStartsOn"
    static let defaultReminderEnabled = "defaultReminderEnabled"
    static let defaultReminderMinutes = "defaultReminderMinutes"
    static let notifyReminders = "notifyReminders"
    static let notifyDeadlines = "notifyDeadlines"
    static let notifyOverdue = "notifyOverdue"
    static let notifyBriefing = "notifyBriefing"
    static let overdueGraceMinutes = "overdueGraceMinutes"
    static let hidePreviews = "hidePreviews"
    static let showBadge = "showBadge"
    static let appLockEnabled = "appLockEnabled"
    static let smartSuggestions = "smartSuggestions"
    static let appleIntelligence = "appleIntelligence"
    static let calendarEnabled = "calendarEnabled"
    static let iCloudSync = "iCloudSync"
    static let autoBackup = "autoBackup"
    static let appearance = "appearance"
    static let lastShiftEndedDay = "lastShiftEndedDay"
    static let externalChangeStamp = "externalChangeStamp"
    static let notificationPermissionAsked = "notificationPermissionAsked"
}

/// Default values, shared by `AppSettings` and every `@AppStorage` declaration.
enum SettingsDefault {
    static let shiftStartMinutes = 7 * 60
    static let shiftEndMinutes = 16 * 60
    /// Saturday — many retail schedules run Saturday through Friday. Adjustable in Settings.
    static let weekStartsOn = 7
    static let defaultReminderEnabled = true
    static let defaultReminderMinutes = 7 * 60
    static let overdueGraceMinutes = 60
    static let appearance = AppearanceMode.dark.rawValue
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Match iPhone"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

/// Typed read access to settings for non-view code.
enum AppSettings {
    static var defaults: UserDefaults { AppGroup.defaults }

    private static func int(_ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    static var hasCompletedOnboarding: Bool { bool(SettingsKey.hasCompletedOnboarding, false) }
    static var shiftStartMinutes: Int { int(SettingsKey.shiftStartMinutes, SettingsDefault.shiftStartMinutes) }
    static var shiftEndMinutes: Int { int(SettingsKey.shiftEndMinutes, SettingsDefault.shiftEndMinutes) }
    static var weekStartsOn: Int { int(SettingsKey.weekStartsOn, SettingsDefault.weekStartsOn) }
    static var defaultReminderEnabled: Bool { bool(SettingsKey.defaultReminderEnabled, SettingsDefault.defaultReminderEnabled) }
    static var defaultReminderMinutes: Int { int(SettingsKey.defaultReminderMinutes, SettingsDefault.defaultReminderMinutes) }
    static var effectiveDefaultReminderMinutes: Int? { defaultReminderEnabled ? defaultReminderMinutes : nil }
    static var hidePreviews: Bool { bool(SettingsKey.hidePreviews, false) }
    static var showBadge: Bool { bool(SettingsKey.showBadge, true) }
    static var appLockEnabled: Bool { bool(SettingsKey.appLockEnabled, false) }
    static var smartSuggestions: Bool { bool(SettingsKey.smartSuggestions, true) }
    static var appleIntelligence: Bool { bool(SettingsKey.appleIntelligence, false) }
    static var calendarEnabled: Bool { bool(SettingsKey.calendarEnabled, false) }
    static var iCloudSync: Bool { bool(SettingsKey.iCloudSync, false) }
    static var autoBackup: Bool { bool(SettingsKey.autoBackup, true) }

    static var notificationPreferences: NotificationPreferences {
        NotificationPreferences(
            remindersEnabled: bool(SettingsKey.notifyReminders, true),
            deadlineAlertsEnabled: bool(SettingsKey.notifyDeadlines, true),
            overdueAlertsEnabled: bool(SettingsKey.notifyOverdue, true),
            dailyBriefingEnabled: bool(SettingsKey.notifyBriefing, true),
            briefingMinutes: shiftStartMinutes,
            shiftEndMinutes: shiftEndMinutes,
            overdueGraceMinutes: int(SettingsKey.overdueGraceMinutes, SettingsDefault.overdueGraceMinutes),
            hidePreviews: hidePreviews,
            maxPending: 60,
            briefingDaysAhead: 7
        )
    }

    static func captureContext(knownAssociates: [String], now: Date = Date()) -> CaptureContext {
        CaptureContext(
            now: now,
            calendar: Calendar.current,
            knownAssociates: knownAssociates,
            defaultReminderMinutes: effectiveDefaultReminderMinutes,
            shiftStartMinutes: shiftStartMinutes,
            shiftEndMinutes: shiftEndMinutes,
            weekStartsOn: weekStartsOn
        )
    }

    /// Records that another process (widget / intent) changed the store.
    static func markExternalChange() {
        defaults.set(Date().timeIntervalSince1970, forKey: SettingsKey.externalChangeStamp)
    }
}
