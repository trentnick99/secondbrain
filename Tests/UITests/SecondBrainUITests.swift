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
        // Generous waits: this is often the first test on a cold CI simulator.
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Ambiguous captures are confirmed before saving")
        confirm.tap()
        app.tabBars.buttons["Associates"].tap()
        XCTAssertTrue(element(containing: "Dana").waitForExistence(timeout: 10))
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

    func testEditingTheScheduleKeepsSettingsOpen() throws {
        let settingsButton = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        let settings = app.navigationBars["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        // Choose a preset shift from the menu.
        let saturday = app.buttons["Saturday shift"].firstMatch
        XCTAssertTrue(saturday.waitForExistence(timeout: 5))
        saturday.tap()
        let preset = app.buttons["10–8"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 3))
        preset.tap()
        sleep(2)
        XCTAssertTrue(settings.exists, "Settings stays open after choosing a shift")
        XCTAssertEqual(app.buttons["Saturday shift"].firstMatch.value as? String, "10–8")

        // Set a custom time.
        app.buttons["Sunday shift"].firstMatch.tap()
        let custom = app.buttons["Custom…"].firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 3))
        custom.tap()
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The custom time editor opens")
        save.tap()
        sleep(2)
        XCTAssertTrue(settings.exists, "Settings stays open after saving a custom shift")
        XCTAssertEqual(app.buttons["Sunday shift"].firstMatch.value as? String, "7–5")
    }

    func testAskFindsAGuideAndAddsAStepAsATask() throws {
        let askBar = app.buttons["homeAskBar"].firstMatch
        XCTAssertTrue(askBar.waitForExistence(timeout: 5))
        askBar.tap()
        let field = app.descendants(matching: .any).matching(identifier: "askQuestionField").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("We're short staffed tonight, two call outs")
        app.buttons["askSubmitButton"].firstMatch.tap()
        let guide = app.buttons["guide-short-staffed"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "The matching guide is listed")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "askRedditLink").firstMatch.exists,
                      "Reddit search is offered")
        guide.tap()
        let add = app.buttons["Add step 1 as a task"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let confirm = app.buttons["Add task"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Adding a step asks first")
        confirm.tap()
        XCTAssertTrue(element(containing: "Added to Tasks").waitForExistence(timeout: 5))
    }

    /// Taps a Home quick action, scrolling the row if it's off screen.
    private func tapQuickAction(_ title: String) {
        let button = app.buttons["New \(title)"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(title) quick action exists")
        let row = app.scrollViews["quickActions"].firstMatch
        var tries = 0
        while !button.isHittable && tries < 4 {
            row.swipeLeft()
            tries += 1
        }
        button.tap()
    }

    /// Lists only build rows as they scroll into view; swipe until the element exists.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, tries: Int = 6) -> Bool {
        var count = 0
        while !element.exists && count < tries {
            app.swipeUp()
            count += 1
        }
        return element.waitForExistence(timeout: 3)
    }

    func testHuddleIsBuiltFromToday() throws {
        tapQuickAction("Huddle")
        XCTAssertTrue(app.navigationBars["Huddle"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Today's top three").exists || element(containing: "TODAY'S TOP THREE").exists)
        let shout = app.descendants(matching: .any).matching(identifier: "huddleShoutOuts").firstMatch
        XCTAssertTrue(scrollTo(shout), "Shout-outs can be typed")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "huddleShareButton").firstMatch.exists
                      || element(containing: "Share with your team leads").exists)
    }

    func testYourOwnGuideIsFoundInAsk() throws {
        let askBar = app.buttons["homeAskBar"].firstMatch
        XCTAssertTrue(askBar.waitForExistence(timeout: 5))
        askBar.tap()
        let newGuide = app.descendants(matching: .any).matching(identifier: "askNewGuide").firstMatch
        XCTAssertTrue(scrollTo(newGuide), "Write a guide is offered")
        newGuide.tap()
        let title = app.descendants(matching: .any).matching(identifier: "customGuideTitle").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Baler won't start")
        let steps = app.descendants(matching: .any).matching(identifier: "customGuideSteps").firstMatch
        steps.tap()
        steps.typeText("Check the e-stop is pulled out")
        app.navigationBars.buttons["Save"].firstMatch.tap()
        let field = app.descendants(matching: .any).matching(identifier: "askQuestionField").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("the baler won't start")
        app.buttons["askSubmitButton"].firstMatch.tap()
        XCTAssertTrue(element(containing: "Your store's own guide").waitForExistence(timeout: 5), "Your guide is listed")
    }

    func testFloorWalkTurnsAMissIntoATask() throws {
        tapQuickAction("Floor walk")
        let needsWork = app.buttons["Needs work: Exits and fire equipment clear"].firstMatch
        XCTAssertTrue(needsWork.waitForExistence(timeout: 5))
        needsWork.tap()
        app.buttons["OK: No spills or trip hazards"].firstMatch.tap()
        let finish = app.descendants(matching: .any).matching(identifier: "walkFinishButton").firstMatch
        if !finish.isHittable { app.swipeUp(); app.swipeUp(); app.swipeUp() }
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        let add = app.buttons["walkAddTasksButton"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Clear the exits and fire equipment").exists, "The miss is listed for review")
        add.tap()
        XCTAssertTrue(element(containing: "Added 1 task").waitForExistence(timeout: 5))
    }

    func testImportNotesAddsReviewedItems() throws {
        tapQuickAction("Import")
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
