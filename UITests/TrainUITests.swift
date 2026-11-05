import XCTest

final class TrainUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    private func startWithRoutine() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        return app
    }

    private func enter(_ text: String, in field: XCUIElement) {
        tap(field)
        field.typeText(text)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPlannedSetRequiresActualsAndSurvivesRelaunch() {
        let app = startWithRoutine()
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        let confirm = app.buttons["confirmSet0"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        capture("Planned workout", in: app)
        tap(confirm)
        XCTAssertTrue(app.descendants(matching: .any)["setIssue0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["undoSet0"].exists)
        enter("10", in: app.textFields["actualReps0"])
        enter("25", in: app.textFields["actualLoad0"])
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        tap(confirm)
        XCTAssertTrue(app.buttons["undoSet0"].waitForExistence(timeout: 5))
        capture("Confirmed first set", in: app)

        app.terminate()
        app.launch()
        tap(app.buttons["resumeWorkout"])
        XCTAssertTrue(app.buttons["undoSet0"].waitForExistence(timeout: 5))
        tap(app.buttons["reviewSession"])
        XCTAssertTrue(app.buttons["finishPartial"].waitForExistence(timeout: 5))
        capture("Partial workout summary", in: app)
        tap(app.buttons["finishPartial"])
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["resumeWorkout"].exists)
        tap(app.buttons["weekday0"])
        XCTAssertTrue(app.staticTexts["Partial"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 / 6 sets")).firstMatch.exists)
    }

    func testAssignSavedExtraCardioToScheduledGoal() {
        let app = startWithRoutine()
        tap(app.buttons["Schedule a cardio activity"])
        enter("Scheduled walk", in: app.textFields["scheduledCardioName"])
        tap(app.buttons["saveScheduledCardio"])
        XCTAssertTrue(app.staticTexts["Scheduled walk"].waitForExistence(timeout: 5))

        tap(app.buttons["extraCardio"])
        enter("900", in: app.textFields["cardioSeconds"])
        tap(app.buttons["confirmCardio"])
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishSession"])

        let saved = app.buttons.matching(identifier: "savedSession")
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(saved.count, 1)
        let credit = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "900 / 1200 seconds")).firstMatch
        XCTAssertFalse(credit.exists)
        tap(saved.firstMatch)
        tap(app.buttons["Assign to planned work"])
        tap(app.buttons["Credit confirmed duration"])

        // Reopen on the actual performance date to verify both records were saved.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(credit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Partial"].exists)
        XCTAssertEqual(saved.count, 1)
        tap(saved.firstMatch)
        XCTAssertTrue(app.navigationBars["Cardio"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Assign to planned work"].exists)
    }

    func testExtraCardioOnARestDay() {
        let app = startWithRoutine()
        tap(app.buttons["weekday6"])
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 5))
        tap(app.buttons["extraCardio"])
        enter("900", in: app.textFields["cardioSeconds"])
        tap(app.buttons["confirmCardio"])
        XCTAssertTrue(app.descendants(matching: .any)["cardioStatus"].waitForExistence(timeout: 5))
        tap(app.buttons["reviewSession"])
        XCTAssertTrue(app.buttons["finishSession"].waitForExistence(timeout: 5))
        capture("Cardio summary", in: app)
        tap(app.buttons["finishSession"])
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["resumeWorkout"].exists)
        XCTAssertTrue(app.staticTexts["Rest day"].exists)
        tap(app.buttons["weekday0"])
        XCTAssertTrue(app.buttons["startPlanned"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
    }
}
