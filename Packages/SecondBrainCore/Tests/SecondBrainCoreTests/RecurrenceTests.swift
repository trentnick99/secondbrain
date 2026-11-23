import XCTest
@testable import SecondBrainCore

final class RecurrenceTests: XCTestCase {
    let cal = Fixtures.calendar
    let anchor = Fixtures.date(2026, 11, 23) // Monday

    private func days(_ rule: RecurrenceRule, from: Date, to: Date) -> [String] {
        rule.occurrences(from: from, to: to, anchor: anchor, calendar: cal).compactMap { Fixtures.day($0) }
    }

    func testDaily() {
        XCTAssertEqual(days(.daily, from: anchor, to: Fixtures.date(2026, 11, 26)),
                       ["2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26"])
    }

    func testEveryThreeDays() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3)
        XCTAssertEqual(days(rule, from: anchor, to: Fixtures.date(2026, 12, 1)), ["2026-11-23", "2026-11-26", "2026-11-29"])
    }

    func testWeekdaysOnlySkipsWeekend() {
        XCTAssertEqual(days(.weekdaysOnly, from: Fixtures.date(2026, 11, 27), to: Fixtures.date(2026, 11, 30)),
                       ["2026-11-27", "2026-11-30"])
    }

    func testSpecificWeekdays() {
        let rule = RecurrenceRule.weekly(on: [2, 5]) // Mon, Thu
        XCTAssertEqual(days(rule, from: anchor, to: Fixtures.date(2026, 12, 3)),
                       ["2026-11-23", "2026-11-26", "2026-11-30", "2026-12-03"])
    }

    func testEveryOtherWeek() {
        let rule = RecurrenceRule.weekly(on: [2], interval: 2)
        XCTAssertEqual(days(rule, from: anchor, to: Fixtures.date(2026, 12, 21)),
                       ["2026-11-23", "2026-12-07", "2026-12-21"])
    }

    func testMonthlyClampsToShortMonths() {
        let rule = RecurrenceRule.monthly(day: 31)
        let start = Fixtures.date(2027, 1, 1)
        let result = rule.occurrences(from: start, to: Fixtures.date(2027, 4, 30), anchor: start, calendar: cal)
            .compactMap { Fixtures.day($0) }
        XCTAssertEqual(result, ["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30"])
    }

    func testEndDateStopsSeries() {
        let rule = RecurrenceRule(frequency: .daily, endDate: Fixtures.date(2026, 11, 24))
        XCTAssertEqual(days(rule, from: anchor, to: Fixtures.date(2026, 11, 30)), ["2026-11-23", "2026-11-24"])
        XCTAssertNil(rule.nextOccurrence(after: Fixtures.date(2026, 11, 24), anchor: anchor, calendar: cal))
    }

    func testNextOccurrence() {
        let rule = RecurrenceRule.weekly(on: [2])
        XCTAssertEqual(Fixtures.day(rule.nextOccurrence(after: anchor, anchor: anchor, calendar: cal)), "2026-11-30")
        XCTAssertEqual(Fixtures.day(rule.firstOccurrence(onOrAfter: anchor, anchor: anchor, calendar: cal)), "2026-11-23")
    }

    func testNoOccurrenceBeforeAnchor() {
        XCTAssertFalse(RecurrenceRule.daily.isOccurrence(Fixtures.date(2026, 11, 22), anchor: anchor, calendar: cal))
    }

    func testCodableRoundTrip() throws {
        let rule = RecurrenceRule.weekly(on: [2, 4, 6], interval: 2)
        let data = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(RecurrenceRule.self, from: data), rule)
    }

    func testSummaries() {
        XCTAssertEqual(RecurrenceRule.daily.summary(calendar: cal), "Every day")
        XCTAssertEqual(RecurrenceRule.weekdaysOnly.summary(calendar: cal), "Every weekday")
        XCTAssertEqual(RecurrenceRule.weekly(on: [2]).summary(calendar: cal), "Every Monday")
        XCTAssertEqual(RecurrenceRule.weekly(on: [5, 2]).summary(calendar: cal), "Every Mon, Thu")
        XCTAssertEqual(RecurrenceRule.monthly(day: 1).summary(calendar: cal), "Monthly on the 1st")
        XCTAssertEqual(RecurrenceRule(frequency: .daily, interval: 3).summary(calendar: cal), "Every 3 days")
    }

    func testOccurrenceKeysAreStable() {
        XCTAssertEqual(NotificationPlanner.dayKey(Fixtures.date(2026, 1, 5, 23, 59), calendar: cal), "2026-01-05")
    }
}
