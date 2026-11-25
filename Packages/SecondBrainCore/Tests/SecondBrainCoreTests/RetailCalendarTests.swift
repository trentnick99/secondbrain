import XCTest
@testable import SecondBrainCore

/// Holidays, the fiscal week, announced events and prep timing — all against fixed dates.
final class RetailCalendarTests: XCTestCase {
    let cal = Fixtures.calendar

    func day(_ date: Date) -> String { Fixtures.day(date) ?? "nil" }

    func testHolidayRules() {
        XCTAssertEqual(day(RetailCalendar.date(of: .thanksgiving, year: 2026, calendar: cal)), "2026-11-26")
        XCTAssertEqual(day(RetailCalendar.date(of: .blackFriday, year: 2026, calendar: cal)), "2026-11-27")
        XCTAssertEqual(day(RetailCalendar.date(of: .cyberMonday, year: 2026, calendar: cal)), "2026-11-30")
        XCTAssertEqual(day(RetailCalendar.date(of: .easter, year: 2026, calendar: cal)), "2026-04-05")
        XCTAssertEqual(day(RetailCalendar.date(of: .easter, year: 2027, calendar: cal)), "2027-03-28")
        XCTAssertEqual(day(RetailCalendar.date(of: .memorialDay, year: 2027, calendar: cal)), "2027-05-31")
        XCTAssertEqual(day(RetailCalendar.date(of: .laborDay, year: 2027, calendar: cal)), "2027-09-06")
        XCTAssertEqual(day(RetailCalendar.date(of: .mothersDay, year: 2027, calendar: cal)), "2027-05-09")
        XCTAssertEqual(day(RetailCalendar.date(of: .fathersDay, year: 2027, calendar: cal)), "2027-06-20")
        XCTAssertEqual(day(RetailCalendar.date(of: .bigGame, year: 2027, calendar: cal)), "2027-02-14")
    }

    func testFiscalWeeks() {
        XCTAssertEqual(day(RetailCalendar.fiscalYearStart(fiscalYear: 2027, calendar: cal)), "2026-01-31", "Saturday of the week containing Feb 1")
        XCTAssertEqual(day(RetailCalendar.fiscalYearStart(fiscalYear: 2028, calendar: cal)), "2027-01-30")
        let now = RetailCalendar.fiscalWeek(of: Fixtures.now, calendar: cal)
        XCTAssertEqual(now.fiscalYear, 2027)
        XCTAssertEqual(now.week, 43)
        XCTAssertEqual(RetailCalendar.fiscalWeekLabel(for: Fixtures.now, calendar: cal), "FY27 · Week 43")
        let firstDay = RetailCalendar.fiscalWeek(of: Fixtures.date(2026, 1, 31, 8, 0), calendar: cal)
        XCTAssertEqual(firstDay.week, 1)
        XCTAssertEqual(RetailCalendar.fiscalWeek(of: Fixtures.date(2026, 1, 30, 8, 0), calendar: cal).fiscalYear, 2026)
    }

    func testUpcomingIsOrderedAndIncludesAnnouncedEvents() {
        let next = RetailCalendar.upcoming(from: Fixtures.now, days: 45, calendar: cal)
        let titles = next.map(\.title)
        XCTAssertTrue(titles.contains("Thanksgiving"))
        XCTAssertTrue(titles.contains("Black Friday Deals"), "Ongoing announced events are included")
        XCTAssertFalse(titles.contains("Early Black Friday Deals"), "Finished events drop off")
        XCTAssertEqual(next.map(\.start), next.map(\.start).sorted())
        XCTAssertEqual(next.first { $0.title == "Black Friday Deals" }?.certainty, .announced)
        XCTAssertEqual(next.first { $0.title == "Thanksgiving" }?.certainty, .calendar)
        XCTAssertTrue(next.allSatisfy { $0.start <= Fixtures.date(2027, 1, 7, 0, 0) })
    }

    func testEveryYearHasTheCoreMomentsWithUniqueKeys() {
        for year in 2026...2028 {
            let moments = RetailCalendar.moments(inYear: year, calendar: cal)
            XCTAssertGreaterThanOrEqual(moments.count, 25)
            let keys = moments.map(\.key) + moments.flatMap(\.prep).map(\.key)
            XCTAssertEqual(keys.count, Set(keys).count, "Keys are unique so added prep steps can be remembered")
            XCTAssertTrue(moments.contains { $0.title == "Halloween set" && $0.certainty == .typical })
        }
        XCTAssertFalse(RetailCalendar.moments(inYear: 2027, calendar: cal).contains { $0.certainty == .announced },
                       "No sales-event dates are invented for years that haven't been announced")
    }

    func testHalloweenSetFollowsLaborDay() {
        let moments = RetailCalendar.moments(inYear: 2027, calendar: cal)
        XCTAssertEqual(day(moments.first { $0.title == "Halloween set" }!.start), "2027-09-07")
    }

    func testPrepDueDatesLandOnWorkdaysBeforeTheMoment() {
        let thanksgiving = RetailCalendar.moments(inYear: 2026, calendar: cal).first { $0.title == "Thanksgiving" }!
        let stockUp = thanksgiving.prep.first { $0.daysBefore == 14 }!
        // 14 days before Thanksgiving is in the past, so it's due today.
        XCTAssertEqual(day(stockUp.suggestedDue(for: thanksgiving, now: Fixtures.now, schedule: nil, calendar: cal)), "2026-11-23")

        let christmas = RetailCalendar.moments(inYear: 2026, calendar: cal).first { $0.title == "Christmas" }!
        let gifts = christmas.prep.first { $0.daysBefore == 10 }!   // Tue Dec 15
        var schedule = ShiftSchedule.unset
        schedule.setShift(nil, forWeekday: 3)                        // off Tuesdays
        XCTAssertEqual(day(gifts.suggestedDue(for: christmas, now: Fixtures.now, schedule: schedule, calendar: cal)), "2026-12-14",
                       "Moved back to Monday, not past the moment")
        let clearance = christmas.prep.first { $0.daysBefore == -1 }!
        XCTAssertEqual(day(clearance.suggestedDue(for: christmas, now: Fixtures.now, schedule: nil, calendar: cal)), "2026-12-26")
    }

    func testSafetyMomentsHaveSafetyPrep() {
        for moment in RetailCalendar.moments(inYear: 2027, calendar: cal) where moment.kind == .safety {
            XCTAssertTrue(moment.prep.contains { $0.category == .safety }, moment.title)
        }
    }
}

final class HolidayCaptureTests: XCTestCase {
    func testEventNamesAreNotWeekdays() {
        let alley = Fixtures.parse("Keep Action Alley open for Black Friday")
        XCTAssertNil(alley.dueDate, "“for Black Friday” isn't a due date, and it isn't this Friday")
        XCTAssertTrue(alley.title.contains("Black Friday"), alley.title)
        XCTAssertNil(Fixtures.parse("Build the Cyber Monday endcap").dueDate)
        XCTAssertNil(Fixtures.parse("Set the Good Friday ham display").dueDate)
        XCTAssertEqual(Fixtures.day(Fixtures.parse("Black Friday signs up by Friday").dueDate), "2026-11-27",
                       "A plain weekday in the same sentence still counts")
    }

    func testHolidaysAfterAPrepositionAreDueDates() {
        XCTAssertEqual(Fixtures.day(Fixtures.parse("Get the toy wall full by Black Friday").dueDate), "2026-11-27")
        XCTAssertEqual(Fixtures.day(Fixtures.parse("Turkeys out before Thanksgiving").dueDate), "2026-11-25")
        XCTAssertEqual(Fixtures.day(Fixtures.parse("Gift cards restocked by Christmas Eve").dueDate), "2026-12-24")
        XCTAssertEqual(Fixtures.day(Fixtures.parse("Grills set by Memorial Day").dueDate), "2027-05-31")
        XCTAssertEqual(Fixtures.day(Fixtures.parse("Clear the Easter set by the 4th of July").dueDate), "2027-07-04")
        XCTAssertEqual(Fixtures.day(Fixtures.parse("Halloween candy out ahead of Halloween").dueDate), "2027-10-30")
    }

    func testBareHolidayNamesAreNotDates() {
        XCTAssertNil(Fixtures.parse("Work the Christmas trees").dueDate)
        let p = Fixtures.parse("Finish the Halloween set by Friday")
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-27")
        XCTAssertEqual(p.category, .merchandising)
    }

    func testRecentChangesVocabulary() {
        XCTAssertEqual(DepartmentLexicon.match(in: "Fill the Vizio endcap"), "Electronics")
        XCTAssertNil(DepartmentLexicon.match(in: "Work digital shelf label exceptions"), "DSLs are not the OPD area")
        XCTAssertEqual(Fixtures.parse("Work digital shelf label exceptions").category, .merchandising)
        XCTAssertEqual(StoreGlossary.lookup("SL").first?.usage, .legacy)
        XCTAssertFalse(StoreGlossary.lookup("Emerging Store Manager").isEmpty)
        XCTAssertFalse(StoreGlossary.search("vizio", in: .updates).isEmpty)
        XCTAssertEqual(Fixtures.parse("Tell the emerging store manager about the truck").associateName, "Emerging Store Manager")
        XCTAssertEqual(StoreRole.infer(from: "Emerging Store Manager"), .storeManager)
    }
}

final class StoreEventTests: XCTestCase {
    let cal = Fixtures.calendar

    func testYourEventsAppearWithTheirPrepSteps() {
        let remodel = StoreEvent(title: "Remodel walk", start: Fixtures.date(2027, 1, 20), note: "Regional team visiting",
                                 steps: [StoreEvent.Step(title: "Features full and signed", daysBefore: 5),
                                         StoreEvent.Step(title: "  ", daysBefore: 1)])
        let upcoming = RetailCalendar.upcoming(from: Fixtures.now, days: 90, calendar: cal, including: [remodel])
        let moment = upcoming.first { $0.key == remodel.key }
        XCTAssertNotNil(moment, "Your event is in the planner")
        XCTAssertEqual(moment?.kind, .store)
        XCTAssertEqual(moment?.certainty, .yours)
        XCTAssertEqual(moment?.prep.map(\.title), ["Features full and signed"], "Empty steps are skipped")
        XCTAssertTrue(moment?.areas.isEmpty == true, "Store-wide, so area filters keep it")
        XCTAssertFalse(RetailCalendar.upcoming(from: Fixtures.now, days: 30, calendar: cal, including: [remodel])
            .contains { $0.key == remodel.key }, "Outside the window it isn't shown")
    }

    func testStepKeysSurviveEditing() {
        let step = StoreEvent.Step(title: "Order extra carts", daysBefore: 10)
        var event = StoreEvent(title: "Local festival", start: Fixtures.date(2026, 12, 12), steps: [step])
        let before = event.moment(calendar: cal).prep.first?.key
        event.steps.insert(StoreEvent.Step(title: "Staffing plan", daysBefore: 14), at: 0)
        event.title = "Downtown festival"
        XCTAssertEqual(event.moment(calendar: cal).prep.last?.key, before, "An added step doesn't change the others' keys")
    }

    func testCleanedEventsAreTidy() {
        let event = StoreEvent(title: "  Inventory  ", start: Fixtures.date(2026, 12, 3, 15), end: Fixtures.date(2026, 12, 1),
                               steps: [StoreEvent.Step(title: " Count the backroom ", daysBefore: 2), StoreEvent.Step(title: "")])
            .cleaned(calendar: cal)
        XCTAssertEqual(event.title, "Inventory")
        XCTAssertEqual(event.start, Fixtures.date(2026, 12, 3))
        XCTAssertNil(event.end, "An end before the start collapses to a one-day event")
        XCTAssertEqual(event.steps.map(\.title), ["Count the backroom"])
        XCTAssertFalse(StoreEvent(title: "  ").isValid)
        let decoded = try? JSONDecoder().decode([StoreEvent].self, from: JSONEncoder().encode([event]))
        XCTAssertEqual(decoded, [event])
    }
}
