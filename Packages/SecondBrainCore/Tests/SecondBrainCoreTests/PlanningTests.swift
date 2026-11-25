import XCTest
@testable import SecondBrainCore

final class PlanningTests: XCTestCase {
    let cal = Fixtures.calendar
    let now = Fixtures.now

    private var sample: [TaskSnapshot] {
        [
            Fixtures.task("Overdue cooler repair", quadrant: .doFirst, category: .operations, due: Fixtures.date(2026, 11, 21)),
            Fixtures.task("Spill in aisle 9", priority: .critical, quadrant: .doFirst, category: .safety, due: Fixtures.date(2026, 11, 23)),
            Fixtures.task("Talk to Sarah about schedule", kind: .followUp, quadrant: .schedule, category: .people,
                          due: Fixtures.date(2026, 11, 23), associate: "Sarah Kim"),
            Fixtures.task("Prep market visit", quadrant: .schedule, category: .meeting, due: Fixtures.date(2026, 11, 26)),
            Fixtures.task("Check results", quadrant: .schedule, category: .admin, due: Fixtures.date(2026, 11, 24),
                          reminder: Fixtures.date(2026, 11, 24, 7)),
            Fixtures.task("Reprint labels", quadrant: .delegate, due: Fixtures.date(2026, 11, 23), delegatedTo: "Alex"),
            Fixtures.task("Old binder cleanup", quadrant: .eliminate),
            Fixtures.task("Done earlier", status: .completed, completedAt: Fixtures.date(2026, 11, 23, 8)),
            Fixtures.task("Inbox thought", status: .inbox, createdAt: Fixtures.date(2026, 11, 18)),
            Fixtures.task("Daily safety walk", quadrant: .schedule, category: .safety, due: Fixtures.date(2026, 11, 23, 15),
                          hasTime: true, reminder: Fixtures.date(2026, 11, 23, 15), recurring: true)
        ]
    }

    func testDayAgendaSections() {
        let a = DayAgenda.build(tasks: sample, day: now, now: now, calendar: cal)
        XCTAssertEqual(a.overdue.map(\.title), ["Overdue cooler repair"])
        XCTAssertTrue(a.dueToday.map(\.title).contains("Spill in aisle 9"))
        XCTAssertEqual(a.followUpsDue.map(\.title), ["Talk to Sarah about schedule"])
        XCTAssertEqual(a.completedToday.map(\.title), ["Done earlier"])
        XCTAssertEqual(a.tomorrow.map(\.title), ["Check results"])
        XCTAssertTrue(a.restOfWeek.map(\.title).contains("Prep market visit"))
        XCTAssertEqual(a.inbox.map(\.title), ["Inbox thought"])
        XCTAssertEqual(a.waiting.map(\.title), ["Reprint labels"], "Delegated without confirmation is awaiting")
        XCTAssertEqual(a.upcomingReminders.first?.title, "Daily safety walk")
        XCTAssertEqual(a.recurring.map(\.title), ["Daily safety walk"])
        XCTAssertEqual(a.suggestedPriorities.first?.title, "Spill in aisle 9")
        XCTAssertFalse(a.suggestedPriorities.contains { $0.quadrant == .eliminate })
        XCTAssertGreaterThanOrEqual(a.priorityCount, 2)
    }

    func testChosenTopPrioritiesWin() {
        var tasks = sample
        tasks[3].focusDate = Fixtures.date(2026, 11, 23)
        let a = DayAgenda.build(tasks: tasks, day: now, now: now, calendar: cal)
        XCTAssertEqual(a.topPriorities.map(\.title), ["Prep market visit"])
        XCTAssertEqual(a.primaryTask?.title, "Prep market visit")
    }

    func testGreetingFollowsTheClockAndCarriesNoCounts() {
        XCTAssertEqual(BriefingBuilder.greeting(now: Fixtures.date(2026, 11, 23, 6, 30), calendar: cal), "Good morning")
        XCTAssertEqual(BriefingBuilder.greeting(now: Fixtures.date(2026, 11, 23, 11, 59), calendar: cal), "Good morning")
        XCTAssertEqual(BriefingBuilder.greeting(now: Fixtures.date(2026, 11, 23, 12, 0), calendar: cal), "Good afternoon")
        XCTAssertEqual(BriefingBuilder.greeting(now: Fixtures.date(2026, 11, 23, 17, 0), calendar: cal), "Good evening")
        XCTAssertEqual(BriefingBuilder.greeting(now: Fixtures.date(2026, 11, 23, 23, 30), calendar: cal), "Good evening")
    }

    func testHomeAgendaMovesToTheNewDayAtMidnight() {
        // Home rebuilds its agenda from a refreshed clock; just after midnight "today" is the new day.
        let lateNight = Fixtures.date(2026, 11, 23, 23, 50)
        let afterMidnight = Fixtures.date(2026, 11, 24, 0, 5)
        let before = DayAgenda.build(tasks: sample, day: lateNight, now: lateNight, calendar: cal)
        let after = DayAgenda.build(tasks: sample, day: afterMidnight, now: afterMidnight, calendar: cal)
        XCTAssertTrue(before.dueToday.map(\.title).contains("Spill in aisle 9"))
        XCTAssertTrue(after.dueToday.map(\.title).contains("Check results"))
        XCTAssertTrue(after.overdue.map(\.title).contains("Spill in aisle 9"))
    }

    func testUnfinishedWorkNeverDisappearsOvernight() {
        // The next morning, yesterday's unfinished items are overdue — not gone.
        let tomorrowMorning = Fixtures.date(2026, 11, 24, 7)
        let a = DayAgenda.build(tasks: sample, day: tomorrowMorning, now: tomorrowMorning, calendar: cal)
        let overdue = Set(a.overdue.map(\.title))
        XCTAssertTrue(overdue.contains("Spill in aisle 9"))
        XCTAssertTrue(overdue.contains("Talk to Sarah about schedule"))
        XCTAssertTrue(overdue.contains("Overdue cooler repair"))
    }

    func testShiftReview() {
        let r = ShiftReview.build(tasks: sample, now: Fixtures.date(2026, 11, 23, 16), calendar: cal)
        XCTAssertEqual(r.completedToday.map(\.title), ["Done earlier"])
        XCTAssertEqual(r.overdue.map(\.title), ["Overdue cooler repair"])
        XCTAssertTrue(r.unfinishedToday.map(\.title).contains("Spill in aisle 9"))
        XCTAssertTrue(r.outstandingCommitments.map(\.title).contains("Talk to Sarah about schedule"))
        XCTAssertEqual(r.awaitingConfirmation.map(\.title), ["Reprint labels"])
        XCTAssertTrue(r.upcomingDeadlines.map(\.title).contains("Check results"))
        XCTAssertTrue(r.importantQ2.map(\.title).contains("Prep market visit"))
        XCTAssertEqual(r.suggestedTomorrow.count, 3)
        // Carry-forward candidates include overdue + unfinished, de-duplicated.
        let titles = r.carryForwardCandidates.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(titles.contains("Overdue cooler repair"))
        XCTAssertFalse(titles.contains("Done earlier"))
    }

    func testWeeklyReview() {
        var tasks = sample
        tasks.append(Fixtures.task("Pushed again", due: Fixtures.date(2026, 11, 25), reschedules: 4))
        tasks.append(Fixtures.task("Resolved follow-up", kind: .followUp, status: .completed,
                                   completedAt: Fixtures.date(2026, 11, 23, 9)))
        let r = WeeklyReview.build(tasks: tasks, now: now, calendar: cal, weekStartsOn: 7) // Saturday weeks
        XCTAssertEqual(Fixtures.day(r.weekStart), "2026-11-21")
        XCTAssertEqual(r.repeatedlyPostponed.map(\.title), ["Pushed again"])
        XCTAssertEqual(r.staleInbox.map(\.title), ["Inbox thought"])
        XCTAssertTrue(r.eliminationCandidates.map(\.title).contains("Old binder cleanup"))
        XCTAssertFalse(r.eliminationCandidates.contains { $0.category.isSafetyCritical })
        XCTAssertEqual(r.followUpsResolved.map(\.title), ["Resolved follow-up"])
        XCTAssertEqual(r.quadrantCounts[.doFirst], 2)
        XCTAssertNotNil(r.completionRate)
    }

    func testBriefingText() {
        let a = DayAgenda.build(tasks: sample, day: now, now: now, calendar: cal)
        let text = BriefingBuilder.dailyBriefing(a, now: now, calendar: cal)
        XCTAssertTrue(text.hasPrefix("Good morning."))
        XCTAssertTrue(text.contains("overdue"))
        XCTAssertTrue(text.contains("Sarah Kim"))
        XCTAssertFalse(BriefingBuilder.countsLine(a).isEmpty)
    }

    func testPriorityRankerPrefersSafetyAndOverdue() {
        let ranked = PriorityRanker.ranked(sample, for: now, now: now, calendar: cal)
        XCTAssertEqual(ranked.prefix(2).map(\.title).sorted(), ["Overdue cooler repair", "Spill in aisle 9"])
        XCTAssertFalse(ranked.contains { $0.status == .completed })
    }

    func testSnoozeOptions() {
        XCTAssertEqual(Fixtures.time(SnoozeOption.fifteenMinutes.date(from: now, morningMinutes: 420, calendar: cal)), "10:15")
        XCTAssertEqual(Fixtures.time(SnoozeOption.thirtyMinutes.date(from: now, morningMinutes: 420, calendar: cal)), "10:30")
        XCTAssertEqual(Fixtures.time(SnoozeOption.oneHour.date(from: now, morningMinutes: 420, calendar: cal)), "11:00")
        let tomorrow = SnoozeOption.tomorrowMorning.date(from: now, morningMinutes: 420, calendar: cal)
        XCTAssertEqual(Fixtures.day(tomorrow), "2026-11-24")
        XCTAssertEqual(Fixtures.time(tomorrow), "07:00")
    }

    func testRescheduleKeepsTimeAndShiftsReminder() {
        let r = Rescheduler.move(dueDate: Fixtures.date(2026, 11, 23, 15), hasDueTime: true,
                                 reminderDate: Fixtures.date(2026, 11, 23, 14, 45), to: Fixtures.date(2026, 11, 25),
                                 now: now, defaultReminderMinutes: 420, calendar: cal)
        XCTAssertEqual(Fixtures.day(r.dueDate), "2026-11-25")
        XCTAssertEqual(Fixtures.time(r.dueDate), "15:00")
        XCTAssertEqual(Fixtures.time(r.reminderDate), "14:45")
        XCTAssertEqual(Fixtures.day(r.reminderDate), "2026-11-25")
        XCTAssertTrue(r.isPostponement)
    }

    func testRescheduleEarlierIsNotPostponement() {
        let r = Rescheduler.move(dueDate: Fixtures.date(2026, 11, 27), hasDueTime: false, reminderDate: nil,
                                 to: Fixtures.date(2026, 11, 24), now: now, defaultReminderMinutes: 420, calendar: cal)
        XCTAssertFalse(r.isPostponement)
        XCTAssertNil(r.reminderDate, "No reminder is invented for a dated task that had none")
    }

    func testSchedulingAnUndatedTaskUsesDefaultReminder() {
        let r = Rescheduler.move(dueDate: nil, hasDueTime: false, reminderDate: nil, to: Fixtures.date(2026, 11, 24),
                                 now: now, defaultReminderMinutes: 420, calendar: cal)
        XCTAssertEqual(Fixtures.time(r.reminderDate), "07:00")
        XCTAssertFalse(r.hasDueTime)
    }

    func testCarryForwardDay() {
        XCTAssertEqual(Fixtures.day(Rescheduler.carryForwardDay(now: Fixtures.date(2026, 11, 23, 23, 30), calendar: cal)), "2026-11-24")
    }
}
