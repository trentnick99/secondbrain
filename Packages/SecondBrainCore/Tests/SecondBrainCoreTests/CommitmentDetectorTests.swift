import XCTest
@testable import SecondBrainCore

final class CommitmentDetectorTests: XCTestCase {
    func testFindsCommitmentsInMeetingNotes() {
        let notes = """
        Weekly huddle
        - Sales were up in grocery
        - I'll get back to Maria about her PTO request Friday
        - [ ] order more pallet jacks
        Action item: check cooler temps tomorrow
        The new endcap looks great.
        """
        let found = CommitmentDetector.detect(in: notes, context: Fixtures.context())
        let titles = found.map(\.parsed.title)
        XCTAssertEqual(found.count, 3, "Found: \(titles)")
        XCTAssertTrue(found.contains { $0.parsed.associateName == "Maria" && Fixtures.day($0.parsed.dueDate) == "2026-11-27" })
        XCTAssertTrue(titles.contains("Order more pallet jacks"))
        XCTAssertTrue(found.contains { Fixtures.day($0.parsed.dueDate) == "2026-11-24" })
        XCTAssertFalse(titles.contains { $0.contains("endcap") })
    }

    func testPlainProseYieldsNothing() {
        let found = CommitmentDetector.detect(in: "Great energy on the floor today. Produce looked fresh.", context: Fixtures.context())
        XCTAssertTrue(found.isEmpty)
    }
}
