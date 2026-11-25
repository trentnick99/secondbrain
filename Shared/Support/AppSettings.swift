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
    /// The person's role and areas (JSON of `UserRole`); empty until chosen.
    static let userRole = "userRole"
    /// Newline-separated ids of suggested routines already added.
    static let routinesAdded = "routinesAdded"
    /// Season Planner and Coming up show only the person's areas plus store-wide items.
    static let seasonMyAreasOnly = "seasonMyAreasOnly"
    static let dismissedRolePrompt = "dismissedRolePrompt"
    /// The person's own store steps for each process in Standards (JSON of [guide id: text]).
    static let askStoreSteps = "askStoreSteps"
    /// The person's own Standards lists: temperatures, quality standards, processes (JSON of [StandardList]).
    static let standardLists = "standardLists"
    /// A floor walk in progress (JSON of `FloorWalkState`).
    static let floorWalkState = "floorWalkState"
    /// Severe weather alerts from the National Weather Service for the store's location.
    static let weatherAlertsEnabled = "weatherAlertsEnabled"
    static let storeLatitude = "storeLatitude"
    static let storeLongitude = "storeLongitude"
    static let storeLocationName = "storeLocationName"
    static let weatherCache = "weatherCache"
    static let weatherNotified = "weatherNotified"
    /// Show today's shift as a Live Activity on the Lock Screen when the app opens during a shift.
    static let shiftLiveActivity = "shiftLiveActivity"
    /// The shift plan's blocks (JSON of [PlanBlock]) and whether to nudge when each starts.
    static let shiftPlanBlocks = "shiftPlanBlocks"
    static let shiftPlanNudges = "shiftPlanNudges"
    /// Guides written in an earlier version (JSON of [CustomGuide]). Standards moves them into lists.
    static let customGuides = "customGuides"
    /// Set by the Focus filter: when off duty, widgets and Home stay quiet.
    static let offDuty = "offDuty"
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
    static let seasonMyAreasOnly = true
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

    /// Today's shift as clock times, if there's a shift on that day.
    static func shiftWindow(on date: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard let shift = shiftSchedule.shift(on: date, calendar: calendar) else { return nil }
        let day = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .minute, value: shift.startMinutes, to: day),
              let end = calendar.date(byAdding: .minute, value: shift.endMinutes, to: day) else { return nil }
        return (start, end)
    }
    /// The person's role, once chosen in onboarding or Settings.
    static var userRole: UserRole? { RoleStorage.decode(defaults.string(forKey: SettingsKey.userRole) ?? "") }
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
/// Stores the person's role as JSON in shared defaults.
enum RoleStorage {
    static func decode(_ json: String) -> UserRole? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(UserRole.self, from: data)
    }

    static func encode(_ role: UserRole?) -> String {
        guard let role, let data = try? JSONEncoder().encode(role) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// JSON helpers for small Codable values kept in the App Group.
enum JSONStorage {
    static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

/// The person's own steps for each store process in Standards, kept on the phone.
enum AskStepsStorage {
    static func decode(_ json: String) -> [String: String] {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func setting(_ id: String, to text: String, in json: String) -> String {
        var all = decode(json)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        all[id] = trimmed.isEmpty ? nil : text
        guard let data = try? JSONEncoder().encode(all) else { return json }
        return String(decoding: data, as: UTF8.self)
    }
}

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

extension UserDefaults {
    /// A stored Bool, or `fallback` when the key has never been set.
    func bool(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }
}
