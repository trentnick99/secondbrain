import XCTest
@testable import SecondBrainCore

/// The six Quick Capture examples from the product brief, plus ambiguity and edge cases.
final class CaptureParserTests: XCTestCase {

    // MARK: - Brief examples

    func testCheckWithJohnTomorrow() {
        let p = Fixtures.parse("Check with John tomorrow about his schedule.")
        XCTAssertEqual(p.kind, .followUp)
        XCTAssertEqual(p.associateName, "John")
        XCTAssertFalse(p.associateIsKnown)
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-24")
        XCTAssertFalse(p.hasDueTime)
        XCTAssertEqual(p.title, "Check with John about his schedule")
        XCTAssertEqual(p.category, .people)
        // Unknown person → must be confirmed, never silently invented.
        XCTAssertTrue(p.ambiguities.contains { $0.field == .person })
        XCTAssertTrue(p.needsReview)
        // Default reminder (7:00 AM) on the due date, flagged as the default.
        XCTAssertEqual(Fixtures.time(p.reminderDate), "07:00")
        XCTAssertEqual(p.reminderSource, .defaultTime)
    }

    func testKnownAssociateIsNotFlagged() {
        let p = Fixtures.parse("Check with John tomorrow about his schedule.", known: ["John Rivera", "Sarah Kim"])
        XCTAssertEqual(p.associateName, "John Rivera")
        XCTAssertTrue(p.associateIsKnown)
        XCTAssertFalse(p.ambiguities.contains { $0.field == .person })
        XCTAssertFalse(p.needsReview, "A clear capture about a known associate saves without confirmation")
    }

    func testDairyBeforeFriday() {
        let p = Fixtures.parse("Make sure dairy is cleaned up before Friday.")
        XCTAssertEqual(p.department, "Dairy")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-26", "“before Friday” means due Thursday")
        XCTAssertTrue(p.notes.contains { $0.contains("before Friday") })
        XCTAssertNil(p.associateName)
        XCTAssertEqual(p.kind, .task)
        XCTAssertTrue(p.classification.isImportant)
        XCTAssertFalse(p.classification.isUrgent, "Three days out is not urgent")
        XCTAssertEqual(p.classification.quadrant, .schedule)
    }

    func testFollowUpWithSarahNextWeek() {
        let p = Fixtures.parse("Follow up with Sarah about her availability next week.")
        XCTAssertEqual(p.kind, .followUp)
        XCTAssertEqual(p.associateName, "Sarah")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-30", "Next week → Monday of next week")
        XCTAssertTrue(p.ambiguities.contains { $0.field == .date }, "“next week” has no day — must be confirmed")
        XCTAssertEqual(p.title, "Follow up with Sarah about her availability")
        XCTAssertEqual(p.category, .people)
    }

    func testCheckResultsThursday() {
        let p = Fixtures.parse("Check VizPick results Thursday.")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-26")
        XCTAssertNil(p.associateName, "Tool names are not people")
        XCTAssertEqual(p.title, "Check VizPick results")
        XCTAssertEqual(p.category, .admin)
        XCTAssertTrue(p.classification.isImportant, "Performance results are important")
    }

    func testRemindEveryMondaySafety() {
        let p = Fixtures.parse("Remind me every Monday to review safety observations.")
        XCTAssertEqual(p.kind, .reminder)
        XCTAssertEqual(p.recurrence, RecurrenceRule.weekly(on: [2]))
        XCTAssertEqual(p.category, .safety)
        XCTAssertTrue(p.classification.isImportant)
        XCTAssertTrue(p.classification.isSafetyLocked)
        XCTAssertEqual(p.title, "Review safety observations")
        XCTAssertEqual(p.recurrence?.summary(calendar: Fixtures.calendar), "Every Monday")
    }

    func testTalkToOvernightCoach() {
        let p = Fixtures.parse("Talk to the overnight Coach about the freight backlog.")
        XCTAssertEqual(p.associateName, "Overnight Coach")
        XCTAssertTrue(p.associateIsRole)
        XCTAssertEqual(p.kind, .followUp)
        XCTAssertEqual(p.category, .freight)
        XCTAssertNil(p.dueDate, "No date was mentioned — none is invented")
        XCTAssertNil(p.reminderDate)
    }

    func testSarahNeedsHelpTalkTomorrow() {
        let p = Fixtures.parse("Sarah needs help understanding her schedule. Talk to her tomorrow.")
        XCTAssertEqual(p.kind, .followUp)
        XCTAssertEqual(p.associateName, "Sarah")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-24")
        XCTAssertEqual(p.title, "Sarah needs help understanding her schedule")
        XCTAssertEqual(p.details, "Talk to her.")
        XCTAssertEqual(p.request, "Sarah needs help understanding her schedule")
    }

    // MARK: - Never invent dates or people

    func testNoDateMeansNoDate() {
        let p = Fixtures.parse("Order more pallet jacks")
        XCTAssertNil(p.dueDate)
        XCTAssertNil(p.reminderDate)
        XCTAssertNil(p.recurrence)
        XCTAssertNil(p.associateName)
        XCTAssertEqual(p.title, "Order more pallet jacks")
    }

    func testReminderWithoutTimeAsksForOne() {
        let p = Fixtures.parse("Remind me to call the vendor")
        XCTAssertEqual(p.kind, .reminder)
        XCTAssertNil(p.dueDate)
        XCTAssertTrue(p.ambiguities.contains { $0.field == .time })
    }

    func testCommonWordsAreNotNames() {
        let p = Fixtures.parse("Check the Backroom for Christmas freight Monday")
        XCTAssertNil(p.associateName)
    }

    // MARK: - Times

    func testExplicitTime() {
        let p = Fixtures.parse("Call the electrician tomorrow at 2:30pm")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-24")
        XCTAssertEqual(Fixtures.time(p.dueDate), "14:30")
        XCTAssertTrue(p.hasDueTime)
        XCTAssertEqual(Fixtures.time(p.reminderDate), "14:30")
        XCTAssertEqual(p.reminderSource, .explicitTime)
    }

    func testRelativeMinutes() {
        let p = Fixtures.parse("Check the spill in aisle 5 in 15 minutes")
        XCTAssertEqual(Fixtures.time(p.dueDate), "10:15")
        XCTAssertEqual(p.reminderSource, .relative)
        XCTAssertEqual(p.classification.quadrant, .doFirst, "Active hazard → Do First")
    }

    func testTimeWithoutMeridiemIsFlagged() {
        let p = Fixtures.parse("Meet with the vendor at 3")
        XCTAssertEqual(Fixtures.time(p.dueDate), "15:00", "3 o'clock inside a 7–4 shift is 3 PM")
        XCTAssertTrue(p.ambiguities.contains { $0.field == .time })
    }

    func testPassedTimeRollsToTomorrowWithWarning() {
        let p = Fixtures.parse("Count the safe at 8am")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-24")
        XCTAssertTrue(p.ambiguities.contains { $0.field == .time })
    }

    func testEndOfShift() {
        let p = Fixtures.parse("Send the freight recap by end of shift")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-23")
        XCTAssertEqual(Fixtures.time(p.dueDate), "16:00")
    }

    // MARK: - Dates

    func testSameWeekdayIsFlagged() {
        let p = Fixtures.parse("Walk the store Monday")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-23")
        XCTAssertTrue(p.ambiguities.contains { $0.field == .date })
    }

    func testExplicitCalendarDate() {
        let p = Fixtures.parse("Submit inventory adjustments Dec 4")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-12-04")
        let q = Fixtures.parse("Submit inventory adjustments 12/4")
        XCTAssertEqual(Fixtures.day(q.dueDate), "2026-12-04")
    }

    func testPastCalendarDateRollsToNextYearWithWarning() {
        let p = Fixtures.parse("Review the plan on March 3")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2027-03-03")
        XCTAssertTrue(p.ambiguities.contains { $0.field == .date })
    }

    func testInThreeDays() {
        let p = Fixtures.parse("Recheck the cooler in 3 days")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-26")
    }

    // MARK: - Recurrence

    func testRecurrenceVariants() {
        XCTAssertEqual(Fixtures.parse("Walk the sales floor every day").recurrence, .daily)
        XCTAssertEqual(Fixtures.parse("Check cooler temps every weekday").recurrence, .weekdaysOnly)
        XCTAssertEqual(Fixtures.parse("Review schedules every Mon and Thu").recurrence, .weekly(on: [2, 5]))
        XCTAssertEqual(Fixtures.parse("Department review every 2 weeks on Tuesday").recurrence, .weekly(on: [3], interval: 2))
        XCTAssertEqual(Fixtures.parse("Submit the report on the 1st of every month").recurrence, .monthly(day: 1))
    }

    func testRecurringWithTimeSchedulesNextFutureOccurrence() {
        // Monday 10:00 now; "every Monday at 7am" already passed today → next Monday.
        let p = Fixtures.parse("Every Monday at 7am review safety observations")
        XCTAssertEqual(p.recurrenceTimeMinutes, 7 * 60)
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-30")
        XCTAssertEqual(Fixtures.time(p.dueDate), "07:00")
    }

    // MARK: - Kinds

    func testExplicitPrefixes() {
        XCTAssertEqual(Fixtures.parse("Idea: move the seasonal endcap closer to the front").kind, .idea)
        XCTAssertEqual(Fixtures.parse("Note: pallet jack #3 squeaks").kind, .note)
        XCTAssertEqual(Fixtures.parse("Meeting notes: weekly huddle").kind, .meetingNote)
    }

    func testOperationalIssueDetected() {
        let p = Fixtures.parse("Freezer door in frozen is broken")
        XCTAssertEqual(p.kind, .issue)
        XCTAssertEqual(p.department, "Frozen")
    }

    func testEmptyInput() {
        let p = Fixtures.parse("   ")
        XCTAssertTrue(p.isEmpty)
        XCTAssertNil(p.dueDate)
    }
}
