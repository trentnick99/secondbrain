import XCTest
@testable import SecondBrainCore

final class FloorWalkTests: XCTestCase {
    func testSectionsFollowTheRoleWithSafetyFirst() {
        let sections = FloorWalkChecklist.sections(for: UserRole(role: .coach, areas: ["Stocking", "Overnight"]))
        XCTAssertEqual(sections.map(\.area), ["Stocking", "Overnight"])
        for section in sections {
            let firstNonSafety = section.checks.firstIndex { !$0.isSafety } ?? section.checks.count
            XCTAssertTrue(section.checks[..<firstNonSafety].allSatisfy(\.isSafety))
            XCTAssertTrue(section.checks[firstNonSafety...].allSatisfy { !$0.isSafety }, "Safety checks come first")
        }
        XCTAssertTrue(sections[0].checks.contains { $0.id == "stock-top" })
        XCTAssertEqual(FloorWalkChecklist.sections(for: nil).map(\.area), [FloorWalkChecklist.genericArea])
        XCTAssertEqual(FloorWalkChecklist.sections(for: UserRole(role: .storeManager, areas: [])).map(\.area), [FloorWalkChecklist.wholeStore])
        for area in StoreAreas.all {
            XCTAssertFalse(FloorWalkChecklist.sections(for: UserRole(role: .coach, areas: [area]))[0].checks.isEmpty, area)
        }
    }

    func testFindingsBecomeTaskTitles() throws {
        let sections = FloorWalkChecklist.sections(for: UserRole(role: .coach, areas: ["Food"]))
        let checks = sections[0].checks
        let exits = try XCTUnwrap(checks.first { $0.id == "exits" })
        let holes = try XCTUnwrap(checks.first { $0.id == "holes" })
        let zoned = try XCTUnwrap(checks.first { $0.id == "zoned" })
        var state = FloorWalkState(startedAt: Fixtures.now)
        state.set(.needsWork, "Food", holes)
        state.notes[FloorWalkState.key("Food", holes)] = "Fill canned veg holes in aisle 12"
        state.set(.needsWork, "Food", exits)
        state.set(.ok, "Food", zoned)
        let findings = FloorWalkChecklist.findings(state, sections)
        XCTAssertEqual(findings.map(\.title), ["Clear the exits and fire equipment (Food)", "Fill canned veg holes in aisle 12"],
                       "Safety first; a note becomes the title")
        XCTAssertEqual(FloorWalkChecklist.markedCount(state, sections), 3)

        state.set(.ok, "Food", holes)
        XCTAssertNil(state.notes[FloorWalkState.key("Food", holes)], "Marking OK clears the note")
        let summary = FloorWalkChecklist.summary(state, sections)
        XCTAssertTrue(summary.contains("2 OK · 1 need work"), summary)
        XCTAssertTrue(summary.contains("(safety)"))
    }

    func testWalkStateRoundTrips() throws {
        var state = FloorWalkState(startedAt: Fixtures.now)
        state.set(.ok, "Food", FloorWalkChecklist.common[0])
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(FloorWalkState.self, from: data), state)
    }
}

final class ShiftHandoffTests: XCTestCase {
    func testHandoffListsOpenWorkSafetyFirstAndLeavesOutAssociates() {
        let now = Fixtures.now
        let tasks = [
            Fixtures.task("Rotate the bread aisle", quadrant: .schedule, due: now),
            Fixtures.task("Wet floor by dairy, confirm cleanup", quadrant: .schedule, category: .safety, due: now),
            Fixtures.task("Submit the cooler repair request", quadrant: .doFirst, due: Fixtures.date(2026, 11, 22, 9)),
            Fixtures.task("Help Jordan with his schedule", kind: .followUp, due: now, associate: "Jordan Ellis"),
            Fixtures.task("Zone aisle 9", status: .completed, completedAt: now)
        ]
        let review = ShiftReview.build(tasks: tasks, now: now, calendar: Fixtures.calendar)
        let text = ShiftHandoff.text(review: review, role: UserRole(role: .coach, areas: ["Food"]), note: "Truck is late.",
                                     now: now, calendar: Fixtures.calendar)
        let lines = text.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasPrefix("Shift handoff · "))
        XCTAssertTrue(lines[0].hasSuffix("Food Coach"), lines[0])
        let open = lines.filter { $0.hasPrefix("• ") }
        XCTAssertTrue(open[0].contains("Wet floor by dairy"), "Safety first: \(open)")
        XCTAssertTrue(open[1].contains("Submit the cooler repair request"), "Then Do First")
        XCTAssertFalse(text.contains("Jordan"), "Associate follow-ups are left out by default")
        XCTAssertTrue(text.contains("(1 associate follow-up not included.)"))
        XCTAssertTrue(text.contains("Done today (1):\n• Zone aisle 9"))
        XCTAssertTrue(text.contains("Notes: Truck is late."))

        let withAssociates = ShiftHandoff.text(review: review, role: nil, includeAssociateItems: true, now: now, calendar: Fixtures.calendar)
        XCTAssertTrue(withAssociates.contains("Jordan"))
        XCTAssertFalse(withAssociates.contains("not included"))
    }
}
