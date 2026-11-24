import Foundation
import SecondBrainCore

/// UserDefaults keys. Views bind with `@AppStorage(key, store: AppGroup.defaults)`.
enum SettingsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let shiftSchedule = "shiftSchedule"
    static let reminderAtShiftStart = "reminderAtShiftStart"
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
    static let showSeasonOnHome = "showSeasonOnHome"
    /// Newline-separated keys of season prep steps already added as tasks.
    static let seasonAdded = "seasonAdded"
    /// Newline-separated keys of season items the person hid.
    static let seasonHidden = "seasonHidden"
}

/// Default values, shared by `AppSettings` and every `@AppStorage` declaration.
enum SettingsDefault {
    /// Used only when no schedule entry applies.
    static let shiftStartMinutes = 7 * 60
    static let shiftEndMinutes = 17 * 60
    static let reminderAtShiftStart = true
    /// Saturday — many retail schedules run Saturday through Friday. Adjustable in Settings.
    static let weekStartsOn = 7
    static let defaultReminderEnabled = true
    static let defaultReminderMinutes = 7 * 60
    static let overdueGraceMinutes = 60
    static let appearance = AppearanceMode.dark.rawValue
    static let showSeasonOnHome = true
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
    /// The weekly shift pattern (7–5, 10–8, 12–10 or off for each weekday).
    static var shiftSchedule: ShiftSchedule {
        ScheduleStorage.decode(defaults.string(forKey: SettingsKey.shiftSchedule) ?? "")
    }

    static var reminderAtShiftStart: Bool { bool(SettingsKey.reminderAtShiftStart, SettingsDefault.reminderAtShiftStart) }

    /// Today's shift, or the next scheduled one if today is a day off.
    static func referenceShift(now: Date = Date()) -> ShiftTime? {
        let schedule = shiftSchedule
        let day = schedule.currentOrNextWorkday(now, calendar: .current)
        return schedule.shift(on: day, calendar: .current)
    }

    static var shiftStartMinutes: Int { referenceShift()?.startMinutes ?? SettingsDefault.shiftStartMinutes }
    static var shiftEndMinutes: Int { referenceShift()?.endMinutes ?? SettingsDefault.shiftEndMinutes }

    static func shiftStartMinutes(on date: Date) -> Int {
        shiftSchedule.startMinutes(on: date, calendar: .current, fallback: SettingsDefault.shiftStartMinutes)
    }

    /// End My Shift carries unfinished work to the next scheduled shift.
    static func nextShiftDay(after date: Date = Date()) -> Date {
        Rescheduler.carryForwardDay(now: date, calendar: .current, schedule: shiftSchedule)
    }

    /// "Thu", "Tomorrow" — for button labels.
    static func nextShiftLabel(after date: Date = Date()) -> String {
        RelativeDateText.dayLabel(for: nextShiftDay(after: date), now: date, calendar: .current)
    }
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
            briefingDaysAhead: 7,
            schedule: shiftSchedule
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
            weekStartsOn: weekStartsOn,
            schedule: shiftSchedule,
            defaultReminderAtShiftStart: reminderAtShiftStart
        )
    }

    /// Records that another process (widget / intent) changed the store.
    static func markExternalChange() {
        defaults.set(Date().timeIntervalSince1970, forKey: SettingsKey.externalChangeStamp)
    }
}

/// Stores the weekly schedule as JSON in shared defaults (readable by the widget too).
enum ScheduleStorage {
    static func decode(_ json: String) -> ShiftSchedule {
        guard let data = json.data(using: .utf8), !json.isEmpty,
              let schedule = try? JSONDecoder().decode(ShiftSchedule.self, from: data) else { return .unset }
        return schedule
    }

    static func encode(_ schedule: ShiftSchedule) -> String {
        guard let data = try? JSONEncoder().encode(schedule) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
