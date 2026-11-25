import XCTest
@testable import SecondBrainCore

final class HuddleTests: XCTestCase {
    func testHuddleHasSafetyYesterdayTopThreeAndShoutOuts() {
        let now = Fixtures.now
        let yesterday = Fixtures.calendar.date(byAdding: .day, value: -1, to: now)!
        var lead = Fixtures.task("Work the remix in aisle 12", quadrant: .doFirst, due: now)
        lead.delegatedTo = "Alex Rivera"
        let tasks = [
            lead,
            Fixtures.task("Clear the fire exits", quadrant: .doFirst, category: .safety, due: now),
            Fixtures.task("Zone the bread aisle", status: .completed, completedAt: yesterday),
            Fixtures.task("Talk with Jordan", kind: .followUp, status: .completed, completedAt: yesterday, associate: "Jordan Ellis")
        ]
        let script = Huddle.build(tasks: tasks, role: nil, now: now, calendar: Fixtures.calendar, shoutOuts: "Maria crushed the frozen truck\n")
        XCTAssertEqual(script.sections.map(\.title), ["Safety", "Yesterday", "Today's top three", "Shout-outs", "Questions"])
        XCTAssertEqual(script.sections[1].lines, ["1 thing done", "Zone the bread aisle"], "Associate follow-ups stay out")
        XCTAssertTrue(script.sections[2].lines.contains("Work the remix in aisle 12 (Alex Rivera)"))
        XCTAssertTrue(script.sections[2].lines.contains("Clear the fire exits (safety)"))
        XCTAssertEqual(script.sections[3].lines, ["Maria crushed the frozen truck"])
        XCTAssertTrue(script.text.contains("SAFETY\n• "))
        XCTAssertTrue(script.heading.contains("Week "), script.heading)
    }

    func testSafetyTipIsSeasonalNearBlackFriday() {
        // Fixtures.now is Monday, Nov 23, 2026; Black Friday is Nov 27.
        XCTAssertTrue(Huddle.safetyTip(now: Fixtures.now, calendar: Fixtures.calendar).hasPrefix("Black Friday is close"))
        XCTAssertNotEqual(Huddle.safetyTip(now: Fixtures.now, calendar: Fixtures.calendar, offset: 1),
                          Huddle.safetyTip(now: Fixtures.now, calendar: Fixtures.calendar, offset: 2), "Shuffle gives another tip")
        let april = Fixtures.date(2026, 4, 14, 9)
        XCTAssertTrue(Huddle.safetyTips.contains(Huddle.safetyTip(now: april, calendar: Fixtures.calendar)))
    }
}

final class ShiftPlanTests: XCTestCase {
    func testDefaultPlanFitsTheShift() {
        let blocks = ShiftPlan.defaultBlocks(for: UserRole(role: .coach, areas: ["Stocking"]), shiftMinutes: 600)
        XCTAssertEqual(blocks.first?.title, "Check Home, messages and today's plan")
        XCTAssertTrue(blocks.contains { $0.title == "Work the freight" })
        XCTAssertEqual(blocks.last?.title, "Wrap up and End My Shift")
        XCTAssertEqual(blocks.last?.offsetMinutes, 570)
        for block in blocks { XCTAssertLessThanOrEqual(block.offsetMinutes + block.durationMinutes, 600) }
        let short = ShiftPlan.defaultBlocks(for: nil, shiftMinutes: 300)
        XCTAssertEqual(short.last?.offsetMinutes, 270)
        XCTAssertFalse(short.contains { $0.title == "Second floor walk" }, "Blocks past the end are dropped")
    }

    func testTimelineMergesBlocksAndTimedTasks() {
        let start = Fixtures.date(2026, 11, 23, 7)
        let end = Fixtures.date(2026, 11, 23, 17)
        let blocks = ShiftPlan.defaultBlocks(for: nil, shiftMinutes: 600)
        var timed = Fixtures.task("Vendor meeting", due: Fixtures.date(2026, 11, 23, 9, 30))
        timed.hasDueTime = true
        let entries = ShiftPlan.entries(blocks: blocks, shiftStart: start, shiftEnd: end,
                                        tasks: [timed, Fixtures.task("No time", due: Fixtures.date(2026, 11, 23, 0))])
        XCTAssertEqual(entries.first?.title, "Check Home, messages and today's plan")
        XCTAssertTrue(entries.contains { $0.isTask && $0.title == "Vendor meeting" })
        XCTAssertFalse(entries.contains { $0.title == "No time" }, "Only tasks with a time go on the timeline")
        XCTAssertEqual(ShiftPlan.current(entries, now: Fixtures.date(2026, 11, 23, 7, 20))?.title, "Huddle")
        XCTAssertNil(ShiftPlan.current(entries, now: Fixtures.date(2026, 11, 23, 18)))
    }
}

final class TeamListAndRecapTests: XCTestCase {
    func testTeamLeadListIsTitlesAndDueOnly() {
        let now = Fixtures.now
        var a = Fixtures.task("Work the remix in aisle 12", due: now)
        a.delegatedTo = "Alex Rivera"
        var b = Fixtures.task("Clear the backroom exit", category: .safety)
        b.delegatedTo = "alex rivera "
        var c = Fixtures.task("Not Alex's")
        c.delegatedTo = "Sam Lee"
        let tasks = [a, b, c]
        let alex = TeamLists.tasks(for: "Alex Rivera", in: tasks)
        XCTAssertEqual(alex.map(\.title), ["Clear the backroom exit", "Work the remix in aisle 12"], "Safety first; names match loosely")
        let text = TeamLists.text(for: "Alex Rivera", tasks: alex, now: now, calendar: Fixtures.calendar)
        XCTAssertTrue(text.hasPrefix("Hi Alex, here's your list for"))
        XCTAssertTrue(text.contains("1. Clear the backroom exit (safety)"))
        XCTAssertTrue(text.contains("2. Work the remix in aisle 12 · today"))
        XCTAssertFalse(text.contains("Sam"))
        let people = TeamLists.people(tasks: tasks, leads: ["Sam Lee", "Pat Kim"])
        XCTAssertEqual(people.map(\.name), ["Alex Rivera", "Sam Lee", "Pat Kim"])
        XCTAssertEqual(people.map(\.open), [2, 1, 0])
    }

    func testWeeklyRecap() {
        let now = Fixtures.now
        let tasks = [
            Fixtures.task("Fixed the blocked exit", status: .completed, category: .safety, completedAt: now),
            Fixtures.task("Set the holiday endcaps", status: .completed, completedAt: now),
            Fixtures.task("Talk with Jordan", kind: .followUp, status: .completed, completedAt: now, associate: "Jordan Ellis"),
            Fixtures.task("Submit the cooler repair request", due: Fixtures.date(2026, 11, 21, 9))
        ]
        let review = WeeklyReview.build(tasks: tasks, now: now, calendar: Fixtures.calendar, weekStartsOn: 7)
        let text = WeeklyRecap.text(review: review, role: UserRole(role: .coach, areas: ["Stocking"]), calendar: Fixtures.calendar)
        XCTAssertTrue(text.hasPrefix("Week recap · FY27 · Week 43 · Nov 21–27 · Stocking Coach"), text)
        XCTAssertTrue(text.contains("Stocking Coach"))
        XCTAssertTrue(text.contains("Done: 3 tasks, including 1 safety item."), text)
        XCTAssertTrue(text.contains("Highlights:\n• Fixed the blocked exit"), "Safety first")
        XCTAssertFalse(text.contains("Jordan"), "Associate follow-ups appear only as counts")
        XCTAssertTrue(text.contains("Submit the cooler repair request"))
    }

    func testWhatsNext() {
        let now = Fixtures.date(2026, 11, 23, 10)
        var meeting = Fixtures.task("Vendor meeting", due: Fixtures.date(2026, 11, 23, 14))
        meeting.hasDueTime = true
        let tasks = [meeting,
                     Fixtures.task("Clear the fire exits", quadrant: .doFirst, category: .safety, due: now),
                     Fixtures.task("Submit the cooler repair request", due: Fixtures.date(2026, 11, 21, 9))]
        let summary = NextUp.summary(tasks: tasks, now: now, calendar: Fixtures.calendar)
            .replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertTrue(summary.hasPrefix("Next up at 2:00 PM: Vendor meeting."), summary)
        XCTAssertTrue(summary.contains("Top priority (overdue): Submit the cooler repair request."), summary)
        XCTAssertFalse(summary.contains("You also have"), "The overdue item isn't repeated")
        XCTAssertEqual(NextUp.summary(tasks: [], now: now, calendar: Fixtures.calendar), "You're all caught up for today.")
    }
}

final class CustomGuideTests: XCTestCase {
    func testOldGuidesKeepTheirShapeForTheMove() throws {
        let own = CustomGuide(title: "Baler won't start", category: .operations,
                              steps: ["Check the e-stop is pulled out", "Call the facilities number on the baler sign", ""],
                              checkWith: "Facilities", extraKeywords: "cardboard, bale")
        XCTAssertTrue(own.isValid)
        let decoded = try JSONDecoder().decode(CustomGuide.self, from: JSONEncoder().encode(own))
        XCTAssertEqual(decoded, own, "Guides saved by earlier versions still decode")
        XCTAssertEqual(StandardList(migrating: own).items.count, 2, "Blank steps are dropped when it moves")
        XCTAssertFalse(CustomGuide(title: " ", steps: ["x"]).isValid)
    }
}
