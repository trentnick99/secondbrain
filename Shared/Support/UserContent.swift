import Foundation
import SecondBrainCore

/// One saved setting in a backup file. Settings are plain values, so four cases cover them all.
enum BackupSetting: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    /// Reads a value as UserDefaults stores it. Data and other types aren't backed up.
    init?(stored value: Any) {
        if let string = value as? String {
            self = .string(string)
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
            else if CFNumberIsFloatType(number) { self = .double(number.doubleValue) }
            else { self = .int(number.intValue) }
        } else {
            return nil
        }
    }

    var storedValue: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        }
    }
}

/// Everything the person keeps in settings rather than in the database: their Standards lists,
/// schedule, role, shift plan, floor walk and preferences. Backups include it, restores merge it,
/// and "Delete all data" removes the personal parts.
enum UserContent {
    /// How a backed-up value is restored next to what's already on the phone.
    enum MergeRule {
        /// Kept as is when the phone already has a value; filled in when it doesn't.
        case fillIfMissing
        /// Standards lists: added by id; lists already on the phone win.
        case standardLists
        /// Your store's steps per process: added per process; steps already on the phone win.
        case processSteps
        /// Newline-separated sets (season items added or hidden, routines added): combined.
        case lineSet
    }

    /// Keys a backup carries, with how each is restored.
    static let backedUp: [String: MergeRule] = [
        // Your content
        SettingsKey.standardLists: .standardLists,
        SettingsKey.askStoreSteps: .processSteps,
        SettingsKey.customGuides: .fillIfMissing,
        SettingsKey.customSeasonEvents: .fillIfMissing,
        SettingsKey.userRole: .fillIfMissing,
        SettingsKey.shiftSchedule: .fillIfMissing,
        SettingsKey.shiftPlanBlocks: .fillIfMissing,
        SettingsKey.floorWalkState: .fillIfMissing,
        SettingsKey.seasonAdded: .lineSet,
        SettingsKey.seasonHidden: .lineSet,
        SettingsKey.routinesAdded: .lineSet,
        SettingsKey.storeLatitude: .fillIfMissing,
        SettingsKey.storeLongitude: .fillIfMissing,
        SettingsKey.storeLocationName: .fillIfMissing,
        // Preferences
        SettingsKey.reminderAtShiftStart: .fillIfMissing,
        SettingsKey.weekStartsOn: .fillIfMissing,
        SettingsKey.defaultReminderEnabled: .fillIfMissing,
        SettingsKey.defaultReminderMinutes: .fillIfMissing,
        SettingsKey.notifyReminders: .fillIfMissing,
        SettingsKey.notifyDeadlines: .fillIfMissing,
        SettingsKey.notifyOverdue: .fillIfMissing,
        SettingsKey.notifyBriefing: .fillIfMissing,
        SettingsKey.overdueGraceMinutes: .fillIfMissing,
        SettingsKey.hidePreviews: .fillIfMissing,
        SettingsKey.showBadge: .fillIfMissing,
        SettingsKey.smartSuggestions: .fillIfMissing,
        SettingsKey.calendarEnabled: .fillIfMissing,
        SettingsKey.autoBackup: .fillIfMissing,
        SettingsKey.appearance: .fillIfMissing,
        SettingsKey.showSeasonOnHome: .fillIfMissing,
        SettingsKey.seasonMyAreasOnly: .fillIfMissing,
        SettingsKey.weatherAlertsEnabled: .fillIfMissing,
        SettingsKey.shiftLiveActivity: .fillIfMissing,
        SettingsKey.shiftPlanNudges: .fillIfMissing
    ]

    /// Keys "Delete all data" removes: everything personal. App preferences such as notifications,
    /// appearance and App Lock stay as they are.
    static let personal: [String] = [
        SettingsKey.standardLists, SettingsKey.askStoreSteps, SettingsKey.customGuides, SettingsKey.customSeasonEvents,
        SettingsKey.userRole, SettingsKey.shiftSchedule, SettingsKey.shiftPlanBlocks, SettingsKey.floorWalkState,
        SettingsKey.seasonAdded, SettingsKey.seasonHidden, SettingsKey.routinesAdded,
        SettingsKey.storeLatitude, SettingsKey.storeLongitude, SettingsKey.storeLocationName,
        SettingsKey.weatherCache, SettingsKey.weatherNotified, SettingsKey.lastShiftEndedDay,
        SettingsKey.dismissedRolePrompt, SettingsKey.offDuty, SettingsKey.externalChangeStamp
    ]

    /// The backed-up values currently on the phone.
    static func snapshot(from defaults: UserDefaults) -> [String: BackupSetting] {
        var values: [String: BackupSetting] = [:]
        for key in backedUp.keys {
            if let stored = defaults.object(forKey: key), let value = BackupSetting(stored: stored) {
                values[key] = value
            }
        }
        return values
    }

    /// Restores backed-up values without overwriting anything already on the phone. Returns how many
    /// settings or lists changed.
    @discardableResult
    static func merge(_ values: [String: BackupSetting], into defaults: UserDefaults) -> Int {
        var changed = 0
        for (key, value) in values {
            guard let rule = backedUp[key] else { continue }   // unknown or excluded keys are ignored
            let local = defaults.object(forKey: key)
            switch rule {
            case .fillIfMissing:
                guard local == nil || (local as? String)?.isEmpty == true else { continue }
                defaults.set(value.storedValue, forKey: key)
                changed += 1
            case .standardLists:
                guard case .string(let json) = value else { continue }
                let mine = JSONStorage.decode([StandardList].self, from: defaults.string(forKey: key) ?? "") ?? []
                let theirs = JSONStorage.decode([StandardList].self, from: json) ?? []
                let kept = Set(mine.map(\.id))
                let added = theirs.filter { !kept.contains($0.id) }
                guard !added.isEmpty else { continue }
                defaults.set(JSONStorage.encode(mine + added), forKey: key)
                changed += 1
            case .processSteps:
                guard case .string(let json) = value else { continue }
                var mine = AskStepsStorage.decode(defaults.string(forKey: key) ?? "")
                let theirs = AskStepsStorage.decode(json)
                let before = mine.count
                for (id, text) in theirs where (mine[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    mine[id] = text
                }
                guard mine.count != before else { continue }
                defaults.set(JSONStorage.encode(mine), forKey: key)
                changed += 1
            case .lineSet:
                guard case .string(let raw) = value else { continue }
                let mine = SeasonPlanStore.keys(defaults.string(forKey: key) ?? "")
                let union = mine.union(SeasonPlanStore.keys(raw))
                guard union != mine else { continue }
                defaults.set(SeasonPlanStore.joined(union), forKey: key)
                changed += 1
            }
        }
        return changed
    }

    /// Removes everything personal kept in settings.
    static func deletePersonal(from defaults: UserDefaults) {
        for key in personal { defaults.removeObject(forKey: key) }
    }
}
