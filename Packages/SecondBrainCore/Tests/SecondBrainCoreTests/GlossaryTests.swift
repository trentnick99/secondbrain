import XCTest
@testable import SecondBrainCore

/// The store-terms reference and the vocabulary Quick Capture learned from it.
final class GlossaryTests: XCTestCase {
    func testEveryLineParses() {
        XCTAssertGreaterThan(StoreGlossary.terms.count, 400)
        for category in GlossaryTerm.Category.allCases {
            XCTAssertFalse(StoreGlossary.terms.filter { $0.category == category }.isEmpty, "\(category) has terms")
        }
        for entry in StoreGlossary.terms {
            XCTAssertFalse(entry.term.isEmpty)
            XCTAssertFalse(entry.meaning.isEmpty, entry.term)
            XCTAssertFalse(entry.meaning.contains("|"), entry.term)
        }
        let ids = StoreGlossary.terms.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "No duplicate entries within a category")
    }

    func testLookupFindsEveryMeaning() {
        XCTAssertEqual(StoreGlossary.lookup("ftpr").first?.meaning.hasPrefix("First Time Pick Rate"), true)
        XCTAssertEqual(StoreGlossary.lookup("OS").first?.term, "Overstock", "Aliases in parentheses are searchable")
        XCTAssertEqual(StoreGlossary.lookup("O/N").first?.term, "ON")
        XCTAssertGreaterThanOrEqual(StoreGlossary.lookup("Pick Walk").count, 2, "Backroom and OPD pick walks differ")
        XCTAssertTrue(StoreGlossary.termsWithSeveralMeanings.contains("Pick Walk"))
        XCTAssertTrue(StoreGlossary.lookup("nonsense").isEmpty)
    }

    func testSearchRanksExactThenPrefixThenMeaning() {
        let results = StoreGlossary.search("cap")
        XCTAssertEqual(results.first?.term, "CAP")
        XCTAssertTrue(results.prefix(5).contains { $0.term == "CAP 2" })
        XCTAssertTrue(StoreGlossary.search("missing child").contains { $0.term == "Code Adam" })
        XCTAssertEqual(StoreGlossary.search("", in: .equipment).count, StoreGlossary.terms.filter { $0.category == .equipment }.count)
    }

    func testUsageTags() {
        XCTAssertEqual(StoreGlossary.lookup("CAP 2").first?.usage, .legacy)
        XCTAssertEqual(StoreGlossary.lookup("Getting Buried").first?.usage, .informal)
        XCTAssertEqual(StoreGlossary.lookup("Code White").first?.usage, .varies)
        XCTAssertNil(StoreGlossary.lookup("Stock 2").first?.usage.label)
    }

    func testDepartmentNumbers() {
        XCTAssertEqual(StoreGlossary.departmentName(number: 94), "Produce")
        XCTAssertEqual(DepartmentLexicon.match(in: "Dept 94 mod set by Friday"), "Produce")
        XCTAssertEqual(DepartmentLexicon.match(in: "check D90 outs"), "Dairy")
        XCTAssertEqual(DepartmentLexicon.match(in: "department #1 needs a reset"), "Candy and Tobacco")
        XCTAssertNil(DepartmentLexicon.match(in: "aisle 12 needs zoning"))
    }

    func testAcronymsMentioned() {
        let found = StoreGlossary.acronymsMentioned(in: "Review FTPR and nil picks with the OPD TL ON the floor").map(\.term)
        XCTAssertEqual(found, ["FTPR", "OPD", "TL"], "Common capitalised words like ON are skipped")
        XCTAssertEqual(StoreGlossary.acronymsMentioned(in: "Ask the O/N TL about WOSH").map(\.term), ["ON", "TL", "WOSH"])
        XCTAssertTrue(StoreGlossary.acronymsMentioned(in: "zone aisle 5 before lunch").isEmpty)
    }
}

final class StoreTermCaptureTests: XCTestCase {
    func testStockingTeamsAreGroupsYouCanHandOffTo() {
        let p = Fixtures.parse("Have Stock 2 work the remix tonight")
        XCTAssertEqual(p.delegateTo, "Stock 2")
        XCTAssertEqual(p.department, "Stocking")
        XCTAssertEqual(p.category, .freight)
        XCTAssertFalse(p.ambiguities.contains { $0.field == .person }, "A team isn't a new contact to confirm")
        XCTAssertEqual(Fixtures.parse("Tell CAP 2 to condense the bins").delegateTo, "CAP 2")
    }

    func testOvernightTeamLead() {
        let p = Fixtures.parse("Ask the O/N TL to finish the FDD freight")
        XCTAssertEqual(p.delegateTo, "O/N TL")
        XCTAssertEqual(p.department, "Overnight")
        XCTAssertEqual(Fixtures.parse("Ask the Stock 1 TL to pull OS for aisle 12").delegateTo, "Stock 1 TL")
        XCTAssertEqual(Fixtures.parse("Tell the FE TL to open more registers").delegateTo, "FE TL")
    }

    func testManagerOnDutyOnlyInCapitals() {
        XCTAssertEqual(Fixtures.parse("Tell the MOD the baler is full").associateName, "Manager on Duty")
        XCTAssertNil(Fixtures.parse("Help with the mod in aisle 4").associateName, "Lowercase mod is a modular")
    }

    func testMarketLeadershipIsImportant() {
        let p = Fixtures.parse("Market is coming Thursday, get the store tour ready")
        XCTAssertTrue(p.classification.isImportant)
        XCTAssertEqual(Fixtures.day(p.dueDate), "2026-11-26")
    }

    func testSafetyEquipmentAndDrillsAreSafetyLocked() {
        for text in ["Pre-use inspection on the walkie stacker", "LOTO refresher for Marcus next month",
                     "Schedule a fire drill in December", "PIT certifications for the unloaders"] {
            let p = Fixtures.parse(text)
            XCTAssertTrue(p.classification.isSafetyLocked, text)
            XCTAssertTrue(p.classification.isImportant, text)
        }
        XCTAssertTrue(Fixtures.parse("Code Adam drill review").classification.isImportant)
    }

    func testFreshComplianceTerms() {
        let p = Fixtures.parse("Temp logs and expiration pull on the meat wall")
        XCTAssertTrue(p.classification.isSafetyLocked)
        XCTAssertEqual(p.department, "Meat")
        XCTAssertEqual(Fixtures.parse("Cold chain check for the wet wall").department, "Produce")
    }

    func testDigitalMetrics() {
        let p = Fixtures.parse("Nil picks are up, review FTPR with Avery Friday")
        XCTAssertEqual(p.department, "Digital (OPD)")
        XCTAssertTrue(p.classification.isImportant, "Performance results are important")
        XCTAssertEqual(p.associateName, "Avery")
    }

    func testMerchandisingTerms() {
        XCTAssertEqual(Fixtures.parse("Build the wing stack for the PDQ").category, .merchandising)
        XCTAssertEqual(Fixtures.parse("Work the VizPick list and downstack the pallets").category, .freight)
    }

    func testNameFollowedByAWeekday() {
        XCTAssertEqual(Fixtures.parse("Check with John Monday about his availability").associateName, "John")
        XCTAssertEqual(Fixtures.parse("Review FTPR with Avery Friday").associateName, "Avery")
    }

    func testCoverageIsAboutPeople() {
        XCTAssertEqual(Fixtures.parse("Ask Tasha to cover SCO at 3").category, .people)
        XCTAssertTrue(Fixtures.parse("Watch overtime this week").classification.isImportant)
    }

    func testGroupNames() {
        for name in ["TLs", "Stocking TLs", "Stock 2", "CAP 3", "the overnight team", "O/N", "Coaches", "Manager on Duty", "everyone"] {
            XCTAssertTrue(StoreRole.isGroupName(name), name)
        }
        for name in ["Fresh Coach", "Jordan Ellis", "O/N TL", "Store Manager", "Stock 2 TL"] {
            XCTAssertFalse(StoreRole.isGroupName(name), name)
        }
    }

    func testRoleInferenceForNewTitles() {
        XCTAssertEqual(StoreRole.infer(from: "Market Coach"), .storeManager)
        XCTAssertEqual(StoreRole.infer(from: "People Lead"), .coach)
        XCTAssertEqual(StoreRole.infer(from: "O/N TL"), .teamLead)
        XCTAssertEqual(StoreRole.infer(from: "APA"), .associate)
    }
}

final class SensitiveContentTests: XCTestCase {
    func testFlagsDetailsThatBelongElsewhere() {
        XCTAssertEqual(SensitiveContent.check("Write up Tasha for being late")?.kind, .disciplinary)
        XCTAssertEqual(SensitiveContent.check("Give Marcus a DA tomorrow")?.kind, .disciplinary)
        XCTAssertEqual(SensitiveContent.check("Priya NCNS again")?.kind, .attendance)
        XCTAssertEqual(SensitiveContent.check("Jordan on FMLA until March")?.kind, .medical)
        XCTAssertEqual(SensitiveContent.check("ORC case from Saturday")?.kind, .assetProtection)
        XCTAssertEqual(SensitiveContent.check("my WIN number is 1234")?.kind, .credentials)
        XCTAssertEqual(SensitiveContent.check("Sam's date of birth")?.kind, .personal)
    }

    func testLeavesOrdinaryWorkAlone() {
        for text in ["Zone aisle 5 before lunch", "Find coverage for Stock 2 — Tasha called out",
                     "da da da", "Coach Jordan on topstock", "Check the handheld login screen",
                     "ISA investigation for dept 92", "I suspect the baler is jammed"] {
            XCTAssertNil(SensitiveContent.check(text), text)
        }
    }
}
