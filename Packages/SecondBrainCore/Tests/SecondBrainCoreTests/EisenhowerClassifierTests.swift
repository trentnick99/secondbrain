import XCTest
@testable import SecondBrainCore

final class EisenhowerClassifierTests: XCTestCase {
    private func classify(_ text: String, category: TaskCategory = .general, kind: TaskKind = .task,
                          priority: TaskPriority = .normal, due: Date? = nil, hasTime: Bool = false) -> EisenhowerClassification {
        EisenhowerClassifier.classify(ClassificationInput(text: text, category: category, kind: kind, priority: priority,
                                                          dueDate: due, hasDueTime: hasTime, now: Fixtures.now,
                                                          calendar: Fixtures.calendar))
    }

    func testImmediateHazardIsDoFirst() {
        let c = classify("Wet floor spill by the registers", category: .safety)
        XCTAssertEqual(c.quadrant, .doFirst)
        XCTAssertTrue(c.isSafetyLocked)
        XCTAssertEqual(c.confidence, .high)
    }

    func testDeadlineAloneDoesNotMakeSomethingImportant() {
        let c = classify("Reprint shelf labels", due: Fixtures.date(2026, 11, 23))
        XCTAssertTrue(c.isUrgent, "Due today is urgent")
        XCTAssertFalse(c.isImportant, "…but an approaching deadline is not automatically important")
        XCTAssertEqual(c.quadrant, .delegate)
        XCTAssertTrue(c.suggestsDelegation)
    }

    func testSafetyWithDistantDeadlineStaysImportant() {
        let c = classify("Annual fire extinguisher inspection", category: .compliance, due: Fixtures.date(2027, 2, 1))
        XCTAssertFalse(c.isUrgent)
        XCTAssertTrue(c.isImportant, "Safety & compliance are never unimportant because the deadline is far away")
        XCTAssertEqual(c.quadrant, .schedule)
    }

    func testSafetyIsImportantEvenWhenMarkedLowPriority() {
        let c = classify("Check eyewash station", category: .safety, priority: .low)
        XCTAssertTrue(c.isImportant)
    }

    func testAssociateDevelopmentIsScheduled() {
        let c = classify("Build a development plan for Maria", category: .development)
        XCTAssertEqual(c.quadrant, .schedule)
    }

    func testMarketVisitPrepIsImportant() {
        let c = classify("Prep for the market visit", category: .meeting, due: Fixtures.date(2026, 12, 3))
        XCTAssertEqual(c.quadrant, .schedule)
    }

    func testFollowUpCommitmentIsImportant() {
        let c = classify("Get back to Sarah about her availability", category: .people, kind: .followUp)
        XCTAssertTrue(c.isImportant)
    }

    func testLowValueWorkIsEliminateCandidate() {
        let c = classify("Maybe reorganize the old binder someday")
        XCTAssertEqual(c.quadrant, .eliminate)
    }

    func testUrgentWordsRaiseUrgency() {
        let c = classify("Call maintenance ASAP about the baler", category: .safety)
        XCTAssertEqual(c.quadrant, .doFirst)
    }

    func testReasonsExplainTheSuggestion() {
        let c = classify("Fix the blocked exit", category: .safety, due: Fixtures.date(2026, 11, 23))
        XCTAssertFalse(c.reasons.isEmpty)
        XCTAssertTrue(c.reasons.contains { $0.lowercased().contains("safety") })
    }

    func testManualClassification() {
        let m = EisenhowerClassification.manual(.delegate)
        XCTAssertTrue(m.isUrgent)
        XCTAssertFalse(m.isImportant)
        XCTAssertEqual(m.reasons, ["Set manually"])
    }

    func testUrgencyEscalationIsOnlyASuggestion() {
        let tomorrow = Fixtures.date(2026, 11, 24)
        XCTAssertEqual(EisenhowerClassifier.urgencyEscalation(current: .schedule, dueDate: tomorrow, hasDueTime: false,
                                                              isSafetyCritical: false, now: Fixtures.now,
                                                              calendar: Fixtures.calendar), .doFirst)
        XCTAssertNil(EisenhowerClassifier.urgencyEscalation(current: .schedule, dueDate: Fixtures.date(2026, 12, 10),
                                                            hasDueTime: false, isSafetyCritical: false,
                                                            now: Fixtures.now, calendar: Fixtures.calendar))
        XCTAssertEqual(EisenhowerClassifier.urgencyEscalation(current: .eliminate, dueDate: tomorrow, hasDueTime: false,
                                                              isSafetyCritical: true, now: Fixtures.now,
                                                              calendar: Fixtures.calendar), .doFirst)
    }

    func testQuadrantFlags() {
        for q in Quadrant.allCases {
            XCTAssertEqual(Quadrant(urgent: q.isUrgent, important: q.isImportant), q)
        }
    }
}
