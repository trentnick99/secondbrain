import XCTest
@testable import SecondBrainCore

/// The store's vocabulary (coaches, team leads, areas) and delegation phrases.
final class StoreVocabularyTests: XCTestCase {
    func testHaveNameIsADelegation() {
        let p = Fixtures.parse("Have Jordan zone aisle 12 before lunch")
        XCTAssertEqual(p.delegateTo, "Jordan")
        XCTAssertEqual(p.kind, .task)
        XCTAssertTrue(p.notes.contains { $0.contains("Hand-off to Jordan") })
    }

    func testKnownTeamLeadDelegation() {
        let p = Fixtures.parse("Have Jordan work the truck", known: ["Jordan Ellis"])
        XCTAssertEqual(p.delegateTo, "Jordan Ellis")
        XCTAssertTrue(p.delegateIsKnown)
        XCTAssertFalse(p.needsReview, "A hand-off to a known team lead saves without extra steps")
    }

    func testAskRoleToDoSomething() {
        let p = Fixtures.parse("Ask the fresh TL to check dates in dairy")
        XCTAssertEqual(p.delegateTo, "Fresh TL")
        XCTAssertEqual(p.associateName, "Fresh TL")
        XCTAssertTrue(p.associateIsRole)
    }

    func testTellMyTeamLeads() {
        let p = Fixtures.parse("Tell my TLs to work the truck at 2pm")
        XCTAssertEqual(p.delegateTo, "TLs")
        XCTAssertEqual(Fixtures.time(p.dueDate), "14:00")
    }

    func testDelegateToName() {
        XCTAssertEqual(Fixtures.parse("Delegate the price change audit to Avery").delegateTo, "Avery")
        XCTAssertEqual(Fixtures.parse("Hand off the mod to Priya tomorrow").delegateTo, "Priya")
        XCTAssertEqual(Fixtures.parse("Give this to Marcus").delegateTo, "Marcus")
        XCTAssertNil(Fixtures.parse("Give feedback to Sarah after the huddle").delegateTo, "Feedback is a follow-up, not a hand-off")
    }

    func testAskAboutIsAFollowUpNotADelegation() {
        let p = Fixtures.parse("Ask Maria about her schedule tomorrow")
        XCTAssertNil(p.delegateTo)
        XCTAssertEqual(p.kind, .followUp)
        XCTAssertEqual(p.associateName, "Maria")
    }

    func testPossessiveIsNotADelegation() {
        XCTAssertNil(Fixtures.parse("Get Marcus's availability for next week").delegateTo)
    }

    func testCoachRoles() {
        let ap = Fixtures.parse("Talk to the AP coach about the shrink report")
        XCTAssertEqual(ap.associateName, "AP Coach")
        XCTAssertEqual(ap.department, "Asset Protection")
        XCTAssertEqual(Fixtures.parse("Check with the OPD coach on late orders").associateName, "OPD Coach")
        XCTAssertEqual(Fixtures.parse("Tell the front end coach we need cashiers").associateName, "Front End Coach")
        XCTAssertEqual(Fixtures.parse("Update the ACC coach on the tire delivery").associateName, "ACC Coach")
    }

    func testStoreManager() {
        let p = Fixtures.parse("Tell the store manager the truck is late")
        XCTAssertEqual(p.associateName, "Store Manager")
        XCTAssertEqual(Fixtures.parse("Send numbers to the SM by end of shift").associateName, "Store Manager")
    }

    func testStoreManagerRequestsAreImportant() {
        let p = Fixtures.parse("Store manager asked for the freight plan by Friday")
        XCTAssertTrue(p.classification.isImportant)
    }

    func testStoreAreas() {
        XCTAssertEqual(Fixtures.parse("OPD orders are backing up").department, "Digital (OPD)")
        XCTAssertEqual(Fixtures.parse("Check the ACC tire rack").department, "Auto Care Center (ACC)")
        XCTAssertEqual(Fixtures.parse("Fitting room recovery in fashion").department, "Fashion")
        XCTAssertEqual(Fixtures.parse("Overnight stocking left pallets in aisle 4").department, "Overnight")
        XCTAssertEqual(Fixtures.parse("Stocking team needs to finish the steel").department, "Stocking")
        XCTAssertNil(Fixtures.parse("Talk to AP").associateName, "Area words alone aren't people")
    }

    func testAreasComeFirstInPickers() {
        XCTAssertEqual(Array(DepartmentLexicon.allNames.prefix(9)), StoreAreas.all)
    }

    func testRoleInference() {
        XCTAssertEqual(StoreRole.infer(from: "Fresh TL"), .teamLead)
        XCTAssertEqual(StoreRole.infer(from: "Stocking Coach"), .coach)
        XCTAssertEqual(StoreRole.infer(from: "Store Manager"), .storeManager)
        XCTAssertEqual(StoreRole.infer(from: "Cashier"), .associate)
        XCTAssertNil(StoreRole.infer(from: ""))
    }
}

/// 10-hour shifts (7–5, 10–8, 12–10), five days a week.
final class ShiftScheduleTests: XCTestCase {
    let cal = Fixtures.calendar

    /// Mon 7–5 · Tue 10–8 · Wed off · Thu 12–10 · Fri 7–5 · Sat off · Sun off.
    var schedule: ShiftSchedule {
        var s = ShiftSchedule(shifts: Array(repeating: nil, count: 7))
        s.setShift(.opening, forWeekday: 2)
        s.setShift(.mid, forWeekday: 3)
        s.setShift(.closing, forWeekday: 5)
        s.setShift(.opening, forWeekday: 6)
        return s
    }

    func context(now: Date = Fixtures.now) -> CaptureContext {
        CaptureContext(now: now, calendar: cal, knownAssociates: [], defaultReminderMinutes: 7 * 60,
                       shiftStartMinutes: 7 * 60, shiftEndMinutes: 17 * 60, weekStartsOn: 7,
                       schedule: schedule, defaultReminderAtShiftStart: true)
    }

    func parse(_ text: String, now: Date = Fixtures.now) -> ParsedCapture {
        NaturalLanguageParser().parse(text, context: context(now: now))
    }

    func testPresetsAndLabels() {
        XCTAssertEqual(ShiftTime.presets.map(\.shortLabel), ["7–5", "10–8", "12–10"])
        XCTAssertEqual(ShiftTime.opening.lengthMinutes, 600)
        XCTAssertEqual(schedule.workdayCount, 4)
        XCTAssertEqual(schedule.summary(calendar: cal, startingOn: 2), "Mon 7–5 · Tue 10–8 · Wed off · Thu 12–10 · Fri 7–5 · Sat off · Sun off")
    }

    func testNextWorkdaySkipsDaysOff() {
        XCTAssertEqual(Fixtures.day(schedule.nextWorkday(after: Fixtures.date(2026, 11, 23), calendar: cal)), "2026-11-24")
        XCTAssertEqual(Fixtures.day(schedule.nextWorkday(after: Fixtures.date(2026, 11, 24), calendar: cal)), "2026-11-26")
        XCTAssertEqual(Fixtures.day(schedule.nextWorkday(after: Fixtures.date(2026, 11, 27), calendar: cal)), "2026-11-30")
    }

    func testEndOfShiftUsesTodaysShift() {
        let p = parse("Send the freight recap by end of shift")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-23")
        XCTAssertEqual(Fixtures.time(p.dueDate), "17:00")
    }

    func testEndOfShiftOnAnotherDayUsesThatDaysShift() {
        let p = parse("Finish the modular by end of shift Tuesday")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-24")
        XCTAssertEqual(Fixtures.time(p.dueDate), "20:00", "Tuesday is a 10–8")
    }

    func testBeforeILeave() {
        XCTAssertEqual(Fixtures.time(parse("Count the safe before I leave").dueDate), "17:00")
    }

    func testFirstThingRollsToNextShiftWhenStarted() {
        let p = parse("First thing check the bakery temps")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-24")
        XCTAssertEqual(Fixtures.time(p.dueDate), "10:00", "Tuesday starts at 10")
    }

    func testNextShift() {
        // Tuesday evening: next shift is Thursday (Wednesday off), reminder at Thursday's 12:00 start.
        let p = parse("Check the steel next shift", now: Fixtures.date(2026, 11, 24, 19))
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-26")
        XCTAssertFalse(p.hasDueTime)
        XCTAssertEqual(Fixtures.time(p.reminderDate), "12:00")
        XCTAssertEqual(p.title, "Check the steel")
    }

    func testDefaultReminderFollowsShiftStart() {
        let p = parse("Walk fresh with the TL Thursday")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-26")
        XCTAssertEqual(Fixtures.time(p.reminderDate), "12:00", "Thursday is a 12–10")
    }

    func testDayOffIsPointedOut() {
        let p = parse("Review the schedule Wednesday")
        XCTAssertTrue(p.notes.contains { $0.contains("you're off") })
    }

    func testBriefingsOnlyOnWorkdaysAtShiftStart() {
        let prefs = NotificationPreferences(briefingMinutes: 7 * 60, shiftEndMinutes: 17 * 60, schedule: schedule)
        let plan = NotificationPlanner.plan(tasks: [], preferences: prefs, now: Fixtures.now, calendar: cal)
        XCTAssertEqual(plan.map { Fixtures.day($0.fireDate)! }, ["2026-11-24", "2026-11-26", "2026-11-27"])
        XCTAssertEqual(plan.map { Fixtures.time($0.fireDate)! }, ["10:00", "12:00", "07:00"])
    }

    func testStillOpenNudgeAtThatDaysShiftEnd() {
        let task = Fixtures.task("Finish modular", due: Fixtures.date(2026, 11, 24))
        let prefs = NotificationPreferences(dailyBriefingEnabled: false, shiftEndMinutes: 17 * 60, schedule: schedule)
        let plan = NotificationPlanner.plan(tasks: [task], preferences: prefs, now: Fixtures.now, calendar: cal)
        XCTAssertEqual(Fixtures.time(plan.first?.fireDate), "20:00")
    }

    func testCarryForwardGoesToNextShift() {
        XCTAssertEqual(Fixtures.day(Rescheduler.carryForwardDay(now: Fixtures.date(2026, 11, 24, 20), calendar: cal, schedule: schedule)), "2026-11-26")
        XCTAssertEqual(Fixtures.day(Rescheduler.carryForwardDay(now: Fixtures.date(2026, 11, 24, 20), calendar: cal)), "2026-11-25")
    }

    func testScheduleCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(schedule)
        XCTAssertEqual(try JSONDecoder().decode(ShiftSchedule.self, from: data), schedule)
    }
}
