import CoreData
import SwiftData
import XCTest
@testable import SecondBrain

/// Guards the on-device database format. The entity hashes below are what builds 1–12 shipped, so a
/// model change that isn't paired with a new schema version fails here instead of on someone's phone.
@MainActor
final class SchemaTests: XCTestCase {
    /// Core Data version hashes of SchemaV1's entities, recorded from the shipped models on 2026-11-25.
    /// Never edit these to make the test pass: add a new schema version and a migration stage instead
    /// (see Docs/ARCHITECTURE.md).
    static let shippedV1: [String: String] = [
        "ActivityEvent": "fab02dfb1d110915edc874c7d36b3403aaad3a57f3e235225c7cca4272e8bbf9",
        "Associate": "46a53d51c28094fb5e7002a9e1b83322dffaa5b7f73c5b72f1996eca7766928d",
        "ChecklistItem": "f3c870856e3bdfcf83bce3019858fb349a6f9672c2c97c2f9355a2971cdbd714",
        "Note": "de813a6ea47a991fd1b11eb747345f47c1b5acef9ab658d57b869283c4771ecc",
        "RecurrenceSeries": "68a47b57da3783c757cc5870b1e3f9dd1dd2def75d130e284c0d23e25ffc2a18",
        "ShiftLog": "0a650cd1c2d44080f66a332f6c871ca03f2e3b600394d8e4333694630c4a5f3e",
        "TaskItem": "70508169bd8befdc028469f293786cd0ad3f4dd0e1c9aba6f931437734a30e87"
    ]

    static func hashes(for types: [any PersistentModel.Type]) -> [String: String] {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else { return [:] }
        return model.entityVersionHashesByName.mapValues { $0.map { String(format: "%02x", $0) }.joined() }
    }

    func testSchemaV1MatchesWhatShipped() {
        let current = Self.hashes(for: SchemaV1.models)
        let report = current.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        XCTAssertEqual(current, Self.shippedV1,
                       "SchemaV1 changed (now \(report)). Add a new schema version and a migration stage instead.")
    }

    /// A store written with SchemaV1 (what's on phones today) opens with the app's current schema and
    /// migration plan, and keeps its data.
    func testAStoreWrittenByEarlierBuildsOpensAndKeepsItsData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v1-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        do {
            let v1 = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(for: v1, configurations: [
                ModelConfiguration(schema: v1, url: url, cloudKitDatabase: .none)
            ])
            let context = ModelContext(container)
            let task = TaskItem(title: "Written by build 12")
            context.insert(task)
            context.insert(Note(title: "Weekly huddle", body: "Grocery in-stock improved", type: .operational))
            try context.save()
        }
        let current = PersistenceController.schema
        let container = try ModelContainer(for: current, migrationPlan: SecondBrainMigrationPlan.self, configurations: [
            ModelConfiguration(schema: current, url: url, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Written by build 12"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).map(\.title), ["Weekly huddle"])
    }
}
