import Foundation
import SwiftData

// MARK: - Versioned schema & migrations

/// Version 1 of the on-device database, frozen: the model classes are nested in `SchemaV1` (see
/// Shared/Models) and `SchemaTests` checks their hashes against what builds 1–12 shipped. To change a
/// model, copy it into a new `SchemaV2` namespace, point the typealias at the copy, and add a migration
/// stage below. Never edit a frozen version — see Docs/ARCHITECTURE.md.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TaskItem.self, Associate.self, Note.self, ChecklistItem.self,
         RecurrenceSeries.self, ActivityEvent.self, ShiftLog.self]
    }
}

enum SecondBrainMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Container

/// Creates the SwiftData container shared by the app, its widgets and App Intents.
///
/// * The store lives in the App Group container when available so widgets read real data.
/// * iCloud (CloudKit) sync is opt-in: it is only attempted when the person enables it in Settings
///   *and* the app was signed with the iCloud capability. Otherwise the store is local-only.
/// * If the store cannot be opened, the app falls back to a temporary in-memory store and shows a
///   warning instead of crashing — it never silently replaces the person's data.
enum PersistenceController {
    enum StoreState: Equatable {
        case normal
        case localFallback(String)
        case temporary(String)
    }

    static let storeName = "SecondBrain"

    private(set) static var state: StoreState = .normal

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// The container for the current process (app or widget extension).
    static let shared: ModelContainer = {
        if isUITesting { return makeInMemory() }
        if AppGroup.isRunningInExtension { return makeExtensionContainer() }
        return makeAppContainer()
    }()

    static var schema: Schema { Schema(versionedSchema: SchemaV1.self) }

    private static var groupContainer: ModelConfiguration.GroupContainer {
        AppGroup.isAvailable ? .identifier(AppGroup.identifier) : .none
    }

    private static func makeAppContainer() -> ModelContainer {
        let wantsCloud = AppSettings.iCloudSync
        let primary = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false, allowsSave: true,
                                         groupContainer: groupContainer,
                                         cloudKitDatabase: wantsCloud ? .automatic : .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: SecondBrainMigrationPlan.self, configurations: [primary])
        } catch {
            // Most often: iCloud requested without the capability. Retry local-only.
            let local = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false, allowsSave: true,
                                           groupContainer: groupContainer, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, migrationPlan: SecondBrainMigrationPlan.self, configurations: [local]) {
                if wantsCloud { state = .localFallback("iCloud sync isn't available for this build, so data is stored on this iPhone only.") }
                return container
            }
            state = .temporary("Your saved data couldn't be opened (\(error.localizedDescription)). Changes made now are temporary. Restart the app, or restore from a backup in Settings › Data.")
            return makeInMemory()
        }
    }

    private static func makeExtensionContainer() -> ModelContainer {
        // Widgets never sync with iCloud themselves; the app owns sync.
        let config = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false, allowsSave: true,
                                        groupContainer: groupContainer, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, migrationPlan: SecondBrainMigrationPlan.self, configurations: [config]) {
            return container
        }
        state = .temporary("Store unavailable")
        return makeInMemory()
    }

    static func makeInMemory() -> ModelContainer {
        let config = ModelConfiguration("InMemory", schema: schema, isStoredInMemoryOnly: true, allowsSave: true,
                                        groupContainer: .none, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Unable to create even an in-memory store: \(error)")
        }
    }
}
