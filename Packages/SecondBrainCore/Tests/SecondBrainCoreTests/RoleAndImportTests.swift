import XCTest
@testable import SecondBrainCore

final class UserRoleTests: XCTestCase {
    let food = UserRole(role: .coach, areas: ["Food"])

    func testTitlesAndCoverage() {
        XCTAssertEqual(food.title, "Food Coach")
        XCTAssertEqual(UserRole(role: .teamLead, areas: ["Digital (OPD)"]).title, "Digital Team Lead")
        XCTAssertEqual(UserRole(role: .storeManager).title, "Store Manager")
        XCTAssertTrue(food.covers("Food"))
        XCTAssertTrue(food.covers("Dairy"), "Departments roll up to their area")
        XCTAssertFalse(food.covers("Produce"))
        XCTAssertFalse(food.covers("Electronics"), "Departments that vary by store aren't assumed")
        XCTAssertTrue(UserRole(role: .coach, areas: ["Stocking", "Electronics"]).covers("Electronics"), "Extra areas count")
        XCTAssertTrue(UserRole(role: .storeManager).covers("Produce"))
    }

    func testRelevance() {
        XCTAssertEqual(food.relevance(of: ["Food"], isTotalStore: false), .mine)
        XCTAssertEqual(food.relevance(of: ["Fresh"], isTotalStore: false), .other)
        XCTAssertEqual(food.relevance(of: [], isTotalStore: true), .totalStore)
        XCTAssertEqual(food.relevance(of: [], isTotalStore: false), .unassigned)
        XCTAssertEqual(food.relevance(of: ["Fresh", "Dairy"], isTotalStore: false), .mine, "Any of your areas makes it yours")
        XCTAssertEqual(UserRole(role: .storeManager).relevance(of: ["Fresh"], isTotalStore: false), .mine)
    }

    func testRoleRoundTrips() throws {
        let data = try JSONEncoder().encode(food)
        XCTAssertEqual(try JSONDecoder().decode(UserRole.self, from: data), food)
    }
}

final class RolePlaybookTests: XCTestCase {
    func testRoutinesMatchTheRole() {
        let food = RolePlaybook.suggestions(for: UserRole(role: .coach, areas: ["Food"]))
        XCTAssertTrue(food.contains { $0.title.contains("Date code") && $0.category == .compliance })
        XCTAssertTrue(food.contains { $0.title.contains("huddle") }, "Every coach gets the shared routines")
        XCTAssertFalse(food.contains { $0.area == "Fresh" })
        let fresh = RolePlaybook.suggestions(for: UserRole(role: .coach, areas: ["Fresh"]))
        XCTAssertTrue(fresh.contains { $0.title == "Temp logs complete" })
        let manager = RolePlaybook.suggestions(for: UserRole(role: .storeManager))
        XCTAssertTrue(manager.contains { $0.title.contains("Business review") })
        let ids = food.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testScheduleText() {
        let food = RolePlaybook.suggestions(for: UserRole(role: .coach, areas: ["Food"]))
        XCTAssertEqual(food.first { $0.id == "coach.numbers" }?.scheduleText, "Every Saturday")
        XCTAssertEqual(food.first { $0.id == "food.dates" }?.scheduleText, "Every day")
    }
}

final class NoteImporterTests: XCTestCase {
    let marketEmail = """
    From: Dana Whitfield
    Sent: Monday, November 23, 2026 4:12 PM
    To: Store Coaches
    Subject: RE: Market walk follow-up

    Hi team,

    Thanks for walking with me today. Overall the store looked good.

    Total store:
    - Clear all fire exits and keep Action Alley open for Black Friday
    - Safety sweep before 10am every day this week

    Food
    - Fill the holes in dairy and frozen by Wednesday
    - Rotate the bread aisle and pull out of date product

    Fresh:
    - Wet wall needs culling, fix signage by tomorrow
    - Temp logs were missing — make sure they're done

    Front End - SCO coverage was thin at 5pm, adjust the schedule

    Also, please send me the Black Friday pallet drop map by Friday.

    Thanks,
    Dana
    Market Manager
    """

    func parse(_ text: String, _ role: UserRole?) -> NoteImport {
        NoteImporter.parse(text, role: role, context: Fixtures.context())
    }

    func testFoodCoachSeesFoodAndTotalStore() {
        let result = parse(marketEmail, UserRole(role: .coach, areas: ["Food"]))
        XCTAssertEqual(result.subject, "Market walk follow-up")
        XCTAssertEqual(result.items.count, 8)

        let mine = result.items(.mine).map(\.text)
        XCTAssertEqual(mine, ["Fill the holes in dairy and frozen by Wednesday", "Rotate the bread aisle and pull out of date product"])
        XCTAssertEqual(result.items(.totalStore).count, 2)
        XCTAssertEqual(result.items(.other).count, 3, "Two Fresh items and the Front End line")
        XCTAssertEqual(result.items(.unassigned).map(\.text), ["Also, please send me the Black Friday pallet drop map by Friday."])

        let dairy = result.items(.mine)[0]
        XCTAssertEqual(Fixtures.day(dairy.parsed.dueDate), "2026-11-25", "Only stated dates are used")
        XCTAssertEqual(dairy.parsed.department, "Food")
        XCTAssertNil(result.items(.mine)[1].parsed.dueDate, "No date is invented")
        XCTAssertEqual(result.items(.totalStore)[0].parsed.department, "Total Store")
        XCTAssertTrue(result.items(.totalStore)[0].parsed.classification.isImportant, "Fire exits are safety")
    }

    func testFreshCoachGetsTheFreshItems() {
        let result = parse(marketEmail, UserRole(role: .coach, areas: ["Fresh"]))
        XCTAssertEqual(result.items(.mine).count, 2)
        XCTAssertEqual(result.items(.mine)[0].areas.first, "Fresh")
        XCTAssertEqual(Fixtures.day(result.items(.mine)[0].parsed.dueDate), "2026-11-24")
    }

    func testStoreManagerSeesEverything() {
        let result = parse(marketEmail, UserRole(role: .storeManager))
        XCTAssertEqual(result.items(.other).count, 0)
        XCTAssertEqual(result.items.count, 8)
    }

    func testInlineLabelDoesNotLeakIntoTheNextLine() {
        let result = parse(marketEmail, UserRole(role: .coach, areas: ["Front End"]))
        XCTAssertEqual(result.items(.mine).map(\.text), ["SCO coverage was thin at 5pm, adjust the schedule"])
    }

    func testQuotedEmailAndSignatureAreIgnored() {
        let text = """
        Please get the steel in aisle 9 worked tonight.
        Thanks!
        Sam
        From: Someone Else
        Sent: Friday
        - Old item that shouldn't come back
        """
        let result = parse(text, nil)
        XCTAssertEqual(result.items.map(\.text), ["Please get the steel in aisle 9 worked tonight."])
    }

    func testUppercaseHeadingsAndAllCoaches() {
        let text = """
        FRESH
        - Rotate the dairy wall
        All coaches:
        - Tour ready by Thursday
        """
        let result = parse(text, UserRole(role: .coach, areas: ["Fresh"]))
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].areas, ["Fresh", "Food"], "Heading plus the department the line names")
        XCTAssertEqual(result.items[0].relevance, .mine)
        XCTAssertTrue(result.items[1].isTotalStore)
    }

    func testProseOnlyKeepsActionableSentences() {
        let text = "Great job on the truck today. We need to clean up the backroom before the market visit. The team was friendly."
        let result = parse(text, nil)
        XCTAssertEqual(result.items.map(\.text), ["We need to clean up the backroom before the market visit."])
        XCTAssertEqual(result.skippedLines, 0)
    }

    func testEmptyAndNoiseInput() {
        XCTAssertTrue(parse("", nil).items.isEmpty)
        XCTAssertTrue(parse("Hi team,\n\nThanks,\nDana", nil).items.isEmpty)
    }
}
