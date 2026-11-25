import Foundation
import SwiftData
import SecondBrainCore

typealias StandardCheck = SchemaV2.StandardCheck

extension SchemaV2 {
    /// One check against a line in your Standards lists: "Ice cream · 5°F, outside -10°F or colder"
    /// at 2:10 PM. The list itself lives in settings, so the check keeps the names it was made with.
    @Model
    final class StandardCheck {
        var id: UUID = UUID()
        var listID: UUID = UUID()
        var itemID: UUID = UUID()
        var listTitle: String = ""
        var itemName: String = ""
        /// The standard at the time of the check, e.g. "-10°F or colder".
        var standard: String = ""
        /// What was read, e.g. "5°F". Empty for a yes/no quality check.
        var reading: String = ""
        var isWithinStandard: Bool = true
        var note: String = ""
        var checkedAt: Date = Date()

        init(listID: UUID, itemID: UUID, listTitle: String, itemName: String, standard: String,
             reading: String, isWithinStandard: Bool, note: String = "", checkedAt: Date = Date()) {
            self.id = UUID()
            self.listID = listID
            self.itemID = itemID
            self.listTitle = listTitle
            self.itemName = itemName
            self.standard = standard
            self.reading = reading
            self.isWithinStandard = isWithinStandard
            self.note = note
            self.checkedAt = checkedAt
        }
    }
}

/// Stated explicitly (SwiftData already implies it) so every file sees it, whatever order the compiler checks them in.
extension StandardCheck: Identifiable {}
