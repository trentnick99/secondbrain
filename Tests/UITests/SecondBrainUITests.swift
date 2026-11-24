import XCTest

/// End-to-end workflow on the simulator with an in-memory store and fictional sample data:
/// capture → classify → follow-up → matrix → planner → End My Shift → carry forward.
final class SecondBrainUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-sampleData"]
        app.launch()
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private var captureField: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "captureTextField").firstMatch
    }

    func testQuickCaptureSavesATask() throws {
        let capture = app.buttons["quickCaptureButton"].firstMatch
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        capture.tap()

        XCTAssertTrue(captureField.waitForExistence(timeout: 3))
        captureField.tap()
        captureField.typeText("Order more pallet wrap for receiving")
        app.buttons["captureSaveButton"].tap()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["No Date"].firstMatch.tap()
        XCTAssertTrue(element(containing: "Order more pallet wrap for receiving").waitForExistence(timeout: 3))
    }

    func testAmbiguousCaptureAsksForConfirmation() throws {
        app.buttons["quickCaptureButton"].firstMatch.tap()
        XCTAssertTrue(captureField.waitForExistence(timeout: 3))
        captureField.tap()
        captureField.typeText("Follow up with Dana about availability next week")
        let confirm = app.buttons["Confirm & Save"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "Ambiguous captures are confirmed before saving")
        confirm.tap()
        app.tabBars.buttons["Associates"].tap()
        XCTAssertTrue(element(containing: "Dana").waitForExistence(timeout: 3))
    }

    func testMatrixShowsFourQuadrants() throws {
        app.tabBars.buttons["Matrix"].tap()
        for prefix in ["Q1 Do First", "Q2 Schedule", "Q3 Delegate", "Q4 Eliminate"] {
            let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 3), "Missing \(prefix)")
        }
    }

    func testEndMyShiftCarriesUnfinishedWork() throws {
        let endShift = app.buttons["endShiftButton"].firstMatch
        XCTAssertTrue(endShift.waitForExistence(timeout: 5))
        endShift.tap()
        let carryAll = app.buttons["carryAllButton"].firstMatch
        if carryAll.waitForExistence(timeout: 3) {
            carryAll.tap()
            let confirm = app.buttons["Carry forward"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        }
        app.buttons["Finish"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 3))
    }

    func testSeasonPlannerAddsAPrepTask() throws {
        let card = app.buttons["seasonComingUpCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Home always shows what's coming up next")
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fiscalWeekLabel"].waitForExistence(timeout: 5))
        let add = app.buttons.matching(identifier: "seasonAddButton").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "seasonAddedMark").firstMatch.waitForExistence(timeout: 5),
                      "The step shows as added")
    }

    func testImportNotesAddsReviewedItems() throws {
        let importButton = app.buttons["New Import"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()
        let editor = app.textViews["importTextEditor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Food\n- Fill the holes in dairy by Wednesday\n- Rotate the bread aisle")
        app.buttons["importReviewButton"].firstMatch.tap()
        let add = app.buttons["importAddButton"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        app.tabBars.buttons["Tasks"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("bread aisle")
        XCTAssertTrue(element(containing: "Rotate the bread aisle").waitForExistence(timeout: 5))
    }

    func testStoreTermsLookup() throws {
        let terms = app.buttons["storeTermsButton"].firstMatch
        XCTAssertTrue(terms.waitForExistence(timeout: 5))
        terms.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("FTPR")
        XCTAssertTrue(element(containing: "First Time Pick Rate").waitForExistence(timeout: 5))
    }

    func testCaptureNudgesAwayFromDisciplinaryDetail() throws {
        app.buttons["quickCaptureButton"].firstMatch.tap()
        XCTAssertTrue(captureField.waitForExistence(timeout: 3))
        captureField.tap()
        captureField.typeText("Write up Tasha for being late")
        let notice = app.descendants(matching: .any).matching(identifier: "sensitiveNotice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3), "A gentle privacy note appears; saving is still allowed")
        XCTAssertTrue(app.buttons["captureSaveButton"].isEnabled)
    }

    func testWeeklyPlannerOpens() throws {
        let planner = app.buttons["Daily and weekly planner"].firstMatch
        XCTAssertTrue(planner.waitForExistence(timeout: 5))
        planner.tap()
        let week = app.buttons["Week"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 10))
        week.tap()
        XCTAssertTrue(app.buttons["Previous week"].waitForExistence(timeout: 20))
    }
}
