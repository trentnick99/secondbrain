import XCTest
@testable import SecondBrainCore

/// The store processes Standards shows as step lists.
final class GuideTests: XCTestCase {
    func testEveryGuideIsACompleteProcess() {
        XCTAssertEqual(Set(CoachGuides.all.map(\.id)).count, CoachGuides.all.count, "Guide ids are unique")
        for guide in CoachGuides.all {
            XCTAssertFalse(guide.title.isEmpty, guide.id)
            XCTAssertFalse(guide.summary.isEmpty, guide.id)
            XCTAssertGreaterThanOrEqual(guide.steps.count, 3, "\(guide.id) needs real steps")
        }
    }

    func testEveryGuideCanBeReachedFromStandards() {
        XCTAssertEqual(Set(CoachGuides.all.map(\.id)), Set(Standards.processIDs),
                       "No guide is left that Standards doesn't show")
    }

    func testTheFreezerDoorProcessIsPractical() {
        let door = CoachGuides.guide(id: "freezer-door")!
        let steps = door.steps.joined(separator: " ").lowercased()
        XCTAssertTrue(steps.contains("manual"), "It explains opening the door manually")
        XCTAssertFalse(door.steps.first?.contains("911") ?? true, "It doesn't open with a 911 call")
    }

    func testWordFormsMatchShortEndingsOnly() {
        XCTAssertTrue(CoachGuides.isWordForm("spills", of: "spill"))
        XCTAssertTrue(CoachGuides.isWordForm("manual", of: "manually"))
        XCTAssertFalse(CoachGuides.isWordForm("doorbuster", of: "door"))
    }
}
