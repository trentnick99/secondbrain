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
        tapTool("capture")

        XCTAssertTrue(captureField.waitForExistence(timeout: 3))
        captureField.tap()
        captureField.typeText("Order more pallet wrap for receiving")
        app.buttons["captureSaveButton"].tap()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["No Date"].firstMatch.tap()
        XCTAssertTrue(element(containing: "Order more pallet wrap for receiving").waitForExistence(timeout: 3))
    }

    func testAmbiguousCaptureAsksForConfirmation() throws {
        tapTool("capture")
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
        app.buttons["Finish shift"].firstMatch.tap()
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

    func testStandardsShowsFoodTemperatures() throws {
        openMoreTool("Standards")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("egg")
        let temps = app.buttons["reference-food-temps"].firstMatch
        XCTAssertTrue(temps.waitForExistence(timeout: 5), "Searching finds the temperature list")
        hideKeyboard()
        temps.tap()
        XCTAssertTrue(element(containing: "45°F").waitForExistence(timeout: 5), "Shell egg temperature is listed")
        XCTAssertTrue(scrollTo(element(containing: "FDA Food Code")), "Sources are listed")
    }

    func testStandardsProcessStepBecomesATask() throws {
        openMoreTool("Standards")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("freezer door")
        let process = app.buttons["guide-freezer-door"].firstMatch
        XCTAssertTrue(process.waitForExistence(timeout: 5), "The freezer door process is listed")
        hideKeyboard()
        process.tap()
        let add = app.buttons["Add step 1 as a task"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let confirm = app.buttons["Add task"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Adding a step asks first")
        confirm.tap()
        XCTAssertTrue(element(containing: "Added to Tasks").waitForExistence(timeout: 5))
    }

    func testYourOwnTemperatureListIsSearchable() throws {
        openMoreTool("Standards")
        let new = app.descendants(matching: .any).matching(identifier: "newStandard-temperatures").firstMatch
        XCTAssertTrue(scrollTo(new), "New temperature list is offered")
        new.tap()
        let title = app.descendants(matching: .any).matching(identifier: "standardTitle").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Frozen and dairy temps")
        let name = app.descendants(matching: .any).matching(identifier: "standardItemName-0").firstMatch
        name.tap()
        name.typeText("Ice cream")
        let value = app.descendants(matching: .any).matching(identifier: "standardItemValue-0").firstMatch
        value.tap()
        value.typeText("-10 F or colder")
        app.buttons["standardSave"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(scrollTo(search, up: true), "Back on Standards")
        search.tap()
        search.typeText("ice cream")
        XCTAssertTrue(element(containing: "Frozen and dairy temps").waitForExistence(timeout: 5), "Your list is found")
    }

    func testHomeShowsNotesUnderTopThree() throws {
        XCTAssertTrue(scrollTo(element(containing: "Weekly huddle")), "A sample note is on Home")
        let newNote = app.buttons["homeNewNote"].firstMatch
        XCTAssertTrue(scrollTo(newNote))
        newNote.tap()
        XCTAssertTrue(captureField.waitForExistence(timeout: 5), "New note opens Capture")
    }

    func testDeepLinkOpensEvenWhenASheetIsOpen() throws {
        let settings = app.buttons["settingsButton"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.open(try XCTUnwrap(URL(string: "secondbrain://standards?q=egg")))
        XCTAssertTrue(app.buttons["reference-food-temps"].firstMatch.waitForExistence(timeout: 10),
                      "A link replaces the open sheet instead of doing nothing")
    }

    /// Taps one of the four big tools on Home.
    private func tapTool(_ id: String) {
        let button = app.buttons["tool-\(id)"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(id) tool exists")
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }

    /// Opens a tool from Home's More tools sheet.
    private func openMoreTool(_ title: String) {
        tapTool("more")
        let row = app.buttons["moreTool-\(title)"].firstMatch
        XCTAssertTrue(scrollTo(row), "\(title) is in More tools")
        if !row.isHittable { app.swipeUp() }
        row.tap()
    }

    /// Lists only build rows as they scroll into view; swipe until the element exists.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, up: Bool = false, tries: Int = 6) -> Bool {
        if element.waitForExistence(timeout: 2) { return true }
        var count = 0
        while !element.exists && count < tries {
            if up { app.swipeDown() } else { app.swipeUp() }
            count += 1
        }
        return element.waitForExistence(timeout: 3)
    }

    /// Hides the keyboard so rows underneath it are built.
    private func hideKeyboard() {
        if app.keyboards.firstMatch.exists {
            app.navigationBars.firstMatch.tap()
        }
    }

    func testHuddleIsBuiltFromToday() throws {
        tapTool("huddle")
        XCTAssertTrue(app.navigationBars["Huddle"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Today's top three").exists || element(containing: "TODAY'S TOP THREE").exists)
        let shout = app.descendants(matching: .any).matching(identifier: "huddleShoutOuts").firstMatch
        XCTAssertTrue(scrollTo(shout), "Shout-outs can be typed")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "huddleShareButton").firstMatch.exists
                      || element(containing: "Share with your team leads").exists)
    }

    func testFloorWalkTurnsAMissIntoATask() throws {
        tapTool("floorwalk")
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
        if !element(containing: "Added 1 task").waitForExistence(timeout: 5) {
            // On a slow simulator the toast can come and go before it's read, so check the task itself.
            let walk = app.navigationBars["Floor walk"].firstMatch
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: walk)
            waitForExpectations(timeout: 15)
            app.tabBars.buttons["Tasks"].tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            search.typeText("exits")
            XCTAssertTrue(element(containing: "Clear the exits and fire equipment").waitForExistence(timeout: 10),
                          "The miss became a task")
        }
    }

    func testImportNotesAddsReviewedItems() throws {
        openMoreTool("Import notes")
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
        openMoreTool("Store terms")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("FTPR")
        XCTAssertTrue(element(containing: "First Time Pick Rate").waitForExistence(timeout: 5))
    }

    func testCaptureNudgesAwayFromDisciplinaryDetail() throws {
        tapTool("capture")
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
