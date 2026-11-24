import XCTest
@testable import SecondBrainCore

final class RecognizedTextTests: XCTestCase {
    func testLinesAreInReadingOrder() {
        // Vision's origin is bottom-left, so higher y is nearer the top of the page.
        let boxes = [
            TextBox(text: "by Friday", x: 0.55, y: 0.70, width: 0.3, height: 0.04),
            TextBox(text: "Food", x: 0.10, y: 0.80, width: 0.2, height: 0.05),
            TextBox(text: "• Fill dairy holes", x: 0.10, y: 0.705, width: 0.4, height: 0.04),
            TextBox(text: "o Rotate bread", x: 0.10, y: 0.60, width: 0.4, height: 0.04),
            TextBox(text: "   ", x: 0.10, y: 0.50, width: 0.1, height: 0.04)
        ]
        XCTAssertEqual(RecognizedText.lines(from: boxes), ["Food", "• Fill dairy holes by Friday", "o Rotate bread"])
        XCTAssertEqual(RecognizedText.text(from: boxes), "Food\n- Fill dairy holes by Friday\n- Rotate bread")
    }

    func testBulletMarksBecomeDashes() {
        XCTAssertEqual(RecognizedText.normalizeBullet("☐ Check the wet wall"), "- Check the wet wall")
        XCTAssertEqual(RecognizedText.normalizeBullet("— Zone aisle 9"), "- Zone aisle 9")
        XCTAssertEqual(RecognizedText.normalizeBullet("Order more pallet wrap"), "Order more pallet wrap")
        XCTAssertEqual(RecognizedText.normalizeBullet("one more thing"), "one more thing", "Only a lone o/e before a capital is a bullet")
    }

    func testScannedNotesFlowIntoImport() {
        let text = RecognizedText.text(from: [
            TextBox(text: "Total store:", x: 0.1, y: 0.9, width: 0.3, height: 0.04),
            TextBox(text: "• Clear all fire exits by Friday", x: 0.1, y: 0.85, width: 0.6, height: 0.04),
            TextBox(text: "Fresh:", x: 0.1, y: 0.78, width: 0.2, height: 0.04),
            TextBox(text: "• Cull the wet wall", x: 0.1, y: 0.73, width: 0.5, height: 0.04)
        ])
        let result = NoteImporter.parse(text, role: UserRole(role: .coach, areas: ["Food"]), context: Fixtures.context())
        XCTAssertEqual(result.items(.totalStore).count, 1)
        XCTAssertEqual(result.items(.other).count, 1, "Fresh is someone else's area for a Food coach")
    }

    func testWalkNotesBecomeOneItemPerSentence() {
        let spoken = "Okay so aisle 12 has holes in canned veggies. Um the dairy cooler door is leaking water; next item pallet left in action alley. ok"
        XCTAssertEqual(RecognizedText.walkNoteItems(from: spoken), [
            "Aisle 12 has holes in canned veggies",
            "The dairy cooler door is leaking water",
            "Pallet left in action alley"
        ])
        XCTAssertTrue(RecognizedText.walkNoteItems(from: "um. ok.").isEmpty)
    }

    func testWalkNotesAreAllKeptAndSortedByArea() {
        let items = RecognizedText.walkNoteItems(from: "Aisle 12 has holes. The dairy cooler door is leaking water. Pallet left in action alley.")
        let text = RecognizedText.bulleted(items)
        let result = NoteImporter.parse(text, role: nil, context: Fixtures.context())
        XCTAssertEqual(result.items.count, 3, "Bullets keep observations that aren't phrased as actions")
        XCTAssertTrue(result.items.contains { $0.parsed.classification.isSafetyLocked },
                      "A leak or a pallet in Action Alley is a safety item")
    }
}
