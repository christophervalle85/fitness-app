import XCTest

final class WeekformUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        return app
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStarterReviewSaveTabsAndRelaunch() {
        let app = launch()
        let starterButton = app.buttons["chooseStarter"]
        XCTAssertTrue(starterButton.waitForExistence(timeout: 10))
        capture("Welcome", in: app)
        tap(starterButton)
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])

        app.terminate()
        app.launch()
        let monday = app.buttons["reviewDay0"]
        tap(monday)
        XCTAssertTrue(app.staticTexts["Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hip hinge"].exists)
        capture("Review the training week", in: app)
        tap(app.buttons["reviewDay6"])
        XCTAssertTrue(app.staticTexts["Rest day"].firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["confirmRoutine"])

        let planTab = app.tabBars.buttons["Plan"]
        let routines = app.tabBars.buttons["Routines"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 10))
        XCTAssertTrue(planTab.isSelected)
        capture("Plan", in: app)

        tap(routines)
        XCTAssertTrue(routines.isSelected)
        XCTAssertTrue(app.staticTexts["Three-day strength"].waitForExistence(timeout: 5))
        capture("Routines", in: app)

        tap(app.buttons["Edit routine"])
        let name = app.textFields["routineName"]
        tap(name)
        name.typeText(" revised")
        let editedName = name.value as? String ?? ""
        XCTAssertTrue(editedName.contains("revised"))
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        XCTAssertTrue(app.staticTexts[editedName].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        XCTAssertTrue(planTab.waitForExistence(timeout: 10))
        XCTAssertTrue(planTab.isSelected)
    }

    func testManualDraftResumesAndBecomesAnActiveRoutine() {
        let app = launch()
        tap(app.buttons["buildRoutine"])
        let name = app.textFields["routineName"]
        tap(name)
        name.typeText("Test training week")
        app.terminate()
        app.launch()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, "Test training week")
        tap(app.buttons["day0"])
        let workout = app.textFields["workoutName"]
        tap(workout)
        workout.typeText("Monday training")
        tap(app.buttons["addExercise"])
        let exercise = app.textFields["exerciseName"]
        tap(exercise)
        exercise.typeText("Test carry")
        tap(app.navigationBars.buttons["Done"])
        tap(app.navigationBars.buttons.element(boundBy: 0))
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        tap(app.tabBars.buttons["Routines"])
        XCTAssertTrue(app.staticTexts["Test training week"].waitForExistence(timeout: 5))
    }

    func testDevelopmentStarterOffersExplicitExerciseChoices() throws {
        let app = launch()
        tap(app.buttons["chooseStarter"])
        XCTAssertTrue(app.buttons["starterGeneral"].waitForExistence(timeout: 10))
        let local = app.buttons["localStarter"]
        try XCTSkipUnless(local.exists, "This checkout has no local development starter.")
        tap(local)
        tap(app.buttons["reviewWeek"])
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["resolveVariants"].exists)

        let variants = app.buttons["chooseVariants"]
        func number(in text: String?) throws -> Int {
            let value = try XCTUnwrap(text)
            return try XCTUnwrap(value.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) })
        }
        var remaining = try number(in: variants.value as? String)
        XCTAssertGreaterThan(remaining, 0)
        tap(app.buttons["resolveVariants"])
        let matches = app.buttons["reviewCatalogMatches"]
        if matches.waitForExistence(timeout: 3) {
            let proposed = try number(in: matches.label)
            XCTAssertGreaterThan(proposed, 0)
            XCTAssertLessThanOrEqual(proposed, remaining)
            tap(matches)
            XCTAssertTrue(app.buttons["useCatalogMatches"].waitForExistence(timeout: 5))
            tap(app.navigationBars["Suggested choices"].buttons["BackButton"])
            XCTAssertTrue(matches.waitForExistence(timeout: 5))
            XCTAssertEqual(try number(in: matches.label), proposed)
            tap(matches)
            tap(app.buttons["useCatalogMatches"])
            XCTAssertTrue(variants.waitForExistence(timeout: 5))
            remaining -= proposed
            XCTAssertEqual(try number(in: variants.value as? String), remaining)
            if remaining > 0 {
                tap(variants)
                XCTAssertFalse(matches.exists)
            }
        }
        let unresolved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'variant' AND value == 'Unresolved'"))
        for _ in 0..<remaining {
            let next = unresolved.firstMatch
            var scrolls = 0
            while !next.isHittable && scrolls < 8 {
                app.swipeUp()
                scrolls += 1
            }
            tap(next)
            tap(app.buttons["variantOption0"].firstMatch)
        }
        if remaining > 0 { tap(app.navigationBars.buttons["Done"]) }
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
    }

    func testFoundationConfirmationSurvivesRelaunch() {
        let app = launch()
        func openFoundation() {
            tap(app.buttons["developerTools"])
            tap(app.buttons["Foundation workout"])
        }
        let status = app.descendants(matching: .any)["foundationStatus"]
        func waitForStatus(_ value: String) -> Bool {
            let predicate = NSPredicate(format: "exists == true AND value == %@", value)
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
            return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
        }
        openFoundation()
        XCTAssertTrue(waitForStatus("Ready"))
        tap(app.buttons["Confirm 8 reps"])
        XCTAssertTrue(waitForStatus("Saved"))
        app.terminate()
        app.launch()
        openFoundation()
        XCTAssertTrue(waitForStatus("Saved"))
        XCTAssertFalse(app.buttons["Confirm 8 reps"].exists)
    }
}
