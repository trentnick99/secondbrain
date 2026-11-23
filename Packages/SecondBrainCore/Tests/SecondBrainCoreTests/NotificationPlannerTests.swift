import XCTest
@testable import SecondBrainCore

final class NotificationPlannerTests: XCTestCase {
    let cal = Fixtures.calendar
    let now = Fixtures.now

    func testReminderDeadlineAndOverdue() {
        let id = UUID()
        var t = Fixtures.task("Call electrician", due: Fixtures.date(2026, 11, 23, 15), hasTime: true,
                              reminder: Fixtures.date(2026, 11, 23, 14, 30))
        t.id = id
        let plan = NotificationPlanner.plan(tasks: [t], preferences: NotificationPreferences(dailyBriefingEnabled: false),
                                            now: now, calendar: cal)
        XCTAssertEqual(plan.map(\.kind), [.reminder, .deadline, .overdue])
        XCTAssertEqual(plan[0].id, "task.\(id.uuidString).reminder")
        XCTAssertEqual(Fixtures.time(plan[2].fireDate), "16:00", "Overdue nudge 60 minutes after the deadline")
        XCTAssertEqual(PlannedNotification.taskID(fromIdentifier: plan[0].id), id)
        XCTAssertTrue(plan[0].hasTaskActions)
    }

    func testReminderAtDeadlineSuppressesDuplicateDeadlineAlert() {
        let t = Fixtures.task("Call electrician", due: Fixtures.date(2026, 11, 23, 15), hasTime: true,
                              reminder: Fixtures.date(2026, 11, 23, 15))
        let plan = NotificationPlanner.plan(tasks: [t], preferences: NotificationPreferences(dailyBriefingEnabled: false),
                                            now: now, calendar: cal)
        XCTAssertEqual(plan.map(\.kind), [.reminder, .overdue])
    }

    func testDateOnlyTaskGetsEndOfShiftNudge() {
        let t = Fixtures.task("Finish modular", due: Fixtures.date(2026, 11, 23))
        let plan = NotificationPlanner.plan(tasks: [t], preferences: NotificationPreferences(dailyBriefingEnabled: false),
                                            now: now, calendar: cal)
        XCTAssertEqual(plan.map(\.kind), [.overdue])
        XCTAssertEqual(Fixtures.time(plan[0].fireDate), "16:00")
    }

    func testCompletedAndPastItemsAreNotScheduled() {
        let done = Fixtures.task("Done", status: .completed, reminder: Fixtures.date(2026, 11, 23, 12), completedAt: now)
        let past = Fixtures.task("Past", reminder: Fixtures.date(2026, 11, 23, 9))
        let plan = NotificationPlanner.plan(tasks: [done, past], preferences: NotificationPreferences(dailyBriefingEnabled: false),
                                            now: now, calendar: cal)
        XCTAssertTrue(plan.isEmpty)
    }

    func testRespectsIOSPendingLimit() {
        let tasks = (0..<100).map { i in
            Fixtures.task("Task \(i)", reminder: now.addingTimeInterval(TimeInterval(600 * (i + 1))))
        }
        let plan = NotificationPlanner.plan(tasks: tasks, preferences: NotificationPreferences(), now: now, calendar: cal)
        XCTAssertEqual(plan.count, 60)
        XCTAssertEqual(plan.first?.title, "Task 0", "Soonest notifications are kept")
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func testDailyBriefingsSkipPastTimes() {
        let plan = NotificationPlanner.plan(tasks: [], preferences: NotificationPreferences(briefingMinutes: 7 * 60), now: now, calendar: cal)
        XCTAssertEqual(plan.count, 6, "Today's 7:00 briefing already passed; the next six days remain")
        XCTAssertEqual(plan.first?.id, "briefing.2026-11-24")
        XCTAssertFalse(plan.first?.hasTaskActions ?? true)
    }

    func testPrivacyHidesTitles() {
        let t = Fixtures.task("Talk to Maria about her write-up", reminder: Fixtures.date(2026, 11, 23, 12))
        let plan = NotificationPlanner.plan(tasks: [t], preferences: NotificationPreferences(dailyBriefingEnabled: false, hidePreviews: true),
                                            now: now, calendar: cal)
        XCTAssertFalse(plan.contains { $0.title.contains("Maria") || $0.body.contains("Maria") })
    }

    func testFollowUpTitleNamesThePerson() {
        let t = Fixtures.task("Schedule question", kind: .followUp, reminder: Fixtures.date(2026, 11, 23, 12), associate: "Sarah Kim")
        let plan = NotificationPlanner.plan(tasks: [t], preferences: NotificationPreferences(dailyBriefingEnabled: false),
                                            now: now, calendar: cal)
        XCTAssertEqual(plan.first?.title, "Follow up with Sarah Kim")
        XCTAssertEqual(plan.first?.threadID, "followups")
    }

    func testDisabledCategories() {
        let t = Fixtures.task("X", due: Fixtures.date(2026, 11, 23, 15), hasTime: true, reminder: Fixtures.date(2026, 11, 23, 14))
        let prefs = NotificationPreferences(remindersEnabled: false, deadlineAlertsEnabled: false,
                                            overdueAlertsEnabled: false, dailyBriefingEnabled: false)
        XCTAssertTrue(NotificationPlanner.plan(tasks: [t], preferences: prefs, now: now, calendar: cal).isEmpty)
    }
}
