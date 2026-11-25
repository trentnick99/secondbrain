import CoreData
import SwiftData
import XCTest
@testable import SecondBrain

/// Guards the on-device database format. The entity hashes below are what builds 1–12 shipped, so a
/// model change that isn't paired with a new schema version fails here instead of on someone's phone.
@MainActor
final class SchemaTests: XCTestCase {
    /// Core Data version hashes of SchemaV1's entities, as shipped. Never edit these to make the test pass:
    /// add `SchemaV2` and a migration stage instead (see Docs/ARCHITECTURE.md).
    static let shippedV1: [String: String] = [:]

    static func hashes(for types: [any PersistentModel.Type]) -> [String: String] {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else { return [:] }
        return model.entityVersionHashesByName.mapValues { $0.map { String(format: "%02x", $0) }.joined() }
    }

    func testSchemaV1MatchesWhatShipped() {
        let current = Self.hashes(for: SchemaV1.models)
        XCTAssertEqual(current.count, 7, "SchemaV1 has seven entities")
        for (name, hash) in current.sorted(by: { $0.key < $1.key }) {
            print("SCHEMA_HASH \(name) \(hash)")
        }
        if Self.shippedV1.isEmpty {
            let report = current.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            XCTFail("SCHEMA_HASHES \(report)")
        } else {
            XCTAssertEqual(current, Self.shippedV1, "SchemaV1 changed. Add SchemaV2 and a migration stage instead.")
        }
    }
}
