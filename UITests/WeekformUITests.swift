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

        tap(app.buttons["routineActions"])
        tap(app.buttons["editRoutine"])
        tap(app.navigationBars.buttons["Cancel"])
        XCTAssertTrue(routines.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Discard draft"].exists)

        tap(app.buttons["routineActions"])
        tap(app.buttons["editRoutine"])
        let name = app.textFields["routineName"]
        tap(name)
        name.typeText(" draft")
        tap(app.navigationBars.buttons["Cancel"])
        let keepEditing = app.buttons["Keep editing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Inline discard choice", in: app)
        tap(keepEditing)
        XCTAssertTrue((name.value as? String)?.hasSuffix(" draft") == true)
        tap(app.navigationBars.buttons["Cancel"])
        tap(app.buttons["Discard draft"])
        XCTAssertTrue(routines.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Three-day strength"].exists)

        tap(app.buttons["routineActions"])
        tap(app.buttons["editRoutine"])
        tap(name)
        name.typeText(" revised")
        let editedName = name.value as? String ?? ""
        XCTAssertTrue(editedName.contains("revised"))
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        XCTAssertTrue(routines.waitForExistence(timeout: 10))
        XCTAssertTrue(routines.isSelected)
        XCTAssertTrue(app.staticTexts[editedName].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        XCTAssertTrue(planTab.waitForExistence(timeout: 10))
        XCTAssertTrue(planTab.isSelected)
    }

    func testAdditionalRoutineUsesItsOwnFlowAndKeepsTheCurrentRoutineActive() {
        let app = launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        let routines = app.tabBars.buttons["Routines"]
        tap(routines)
        capture("Routine card actions", in: app)

        tap(app.buttons["newRoutine"])
        XCTAssertTrue(app.navigationBars["New routine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startFromScratch"].exists)
        XCTAssertTrue(app.buttons["usePreset"].exists)
        XCTAssertFalse(app.buttons["chooseStarter"].exists)
        capture("New routine choices", in: app)

        tap(app.buttons["startFromScratch"])
        let name = app.textFields["routineName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, name.placeholderValue)
        tap(app.navigationBars.buttons["Cancel"])
        tap(app.buttons["Discard draft"])
        XCTAssertTrue(routines.waitForExistence(timeout: 5))
        XCTAssertTrue(routines.isSelected)

        tap(app.buttons["newRoutine"])
        tap(app.buttons["usePreset"])
        XCTAssertTrue(app.navigationBars["Choose a preset"].waitForExistence(timeout: 5))
        tap(app.buttons["starterGeneral"])
        tap(name)
        name.typeText(" for later")
        let newName = name.value as? String ?? ""
        XCTAssertTrue(newName.hasSuffix(" for later"))
        tap(app.buttons["reviewWeek"])

        app.terminate()
        app.launch()
        let save = app.buttons["confirmRoutine"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.label, "Save routine")
        tap(save)
        XCTAssertTrue(routines.waitForExistence(timeout: 5))
        XCTAssertTrue(routines.isSelected)
        XCTAssertTrue(app.staticTexts[newName].waitForExistence(timeout: 5))

        let originalActions = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@", "routineActions", "More actions for Three-day strength"
        )).firstMatch
        tap(originalActions)
        XCTAssertTrue(app.buttons["Duplicate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Make active"].exists)
    }

    func testAdditionalRoutineCanBeMadeActiveAtSave() {
        let app = launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        let routines = app.tabBars.buttons["Routines"]
        tap(routines)
        tap(app.buttons["newRoutine"])
        tap(app.buttons["usePreset"])
        tap(app.buttons["starterGeneral"])
        let name = app.textFields["routineName"]
        tap(name)
        name.typeText(" alternate")
        tap(app.buttons["reviewWeek"])

        let activate = app.switches["activateNewRoutine"]
        if !activate.isHittable { app.swipeUp() }
        tap(activate)
        let save = app.buttons["confirmRoutine"]
        XCTAssertEqual(save.label, "Save and use routine")
        tap(save)
        XCTAssertTrue(routines.waitForExistence(timeout: 5))
        XCTAssertTrue(routines.isSelected)

        let originalActions = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@", "routineActions", "More actions for Three-day strength"
        )).firstMatch
        tap(originalActions)
        XCTAssertTrue(app.buttons["Make active"].waitForExistence(timeout: 5))
    }

    func testRoutineMenuDeletesOnlyAfterConfirmation() {
        let app = launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        tap(app.tabBars.buttons["Routines"])

        let original = app.buttons["More actions for Three-day strength"]
        let copy = app.buttons["More actions for Three-day strength (copy)"]
        let confirmDelete = app.alerts["Delete this routine?"].buttons["confirmDeleteRoutine"].firstMatch
        tap(original)
        XCTAssertTrue(app.buttons["editRoutine"].exists)
        XCTAssertTrue(app.buttons["Archive"].exists)
        tap(app.buttons["Duplicate"])
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertEqual(original.frame.midX, copy.frame.midX, accuracy: 1)
        let activeTitle = app.staticTexts["Three-day strength"]
        let copyTitle = app.staticTexts["Three-day strength (copy)"]
        let badge = app.staticTexts["Active routine"]
        XCTAssertLessThan(badge.frame.maxY, activeTitle.frame.minY)
        XCTAssertLessThanOrEqual(original.frame.maxY, activeTitle.frame.minY)
        XCTAssertEqual(original.frame.midY, badge.frame.midY, accuracy: 2)
        XCTAssertEqual(copy.frame.minY, copyTitle.frame.minY, accuracy: 2)
        capture("Active routine menu above the name", in: app)

        tap(copy)
        tap(app.buttons["deleteRoutine"])
        tap(app.buttons["Cancel"])
        XCTAssertTrue(copy.exists)
        tap(copy)
        tap(app.buttons["deleteRoutine"])
        tap(confirmDelete)
        XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
        XCTAssertTrue(original.exists)

        tap(original)
        tap(app.buttons["deleteRoutine"])
        tap(confirmDelete)
        XCTAssertTrue(original.waitForNonExistence(timeout: 5))
        tap(app.buttons["newRoutine"])
        tap(app.buttons["startFromScratch"])
        app.terminate()
        app.launch()
        tap(app.navigationBars.buttons["Cancel"])
        tap(app.buttons["Discard draft"])
        XCTAssertTrue(app.tabBars.buttons["Routines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Routines"].isSelected)
    }

    func testRoutinesTitleStaysHiddenWhileScrolling() {
        let app = launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        let routines = app.tabBars.buttons["Routines"]
        tap(routines)

        let menu = app.buttons["More actions for Three-day strength"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let header = app.navigationBars.staticTexts["Routines"]
        XCTAssertFalse(header.exists)
        XCTAssertFalse(app.navigationBars["Routines"].exists)
        for _ in 0..<5 {
            tap(menu)
            tap(app.buttons["Duplicate"])
        }
        let firstRowY = menu.frame.midY
        app.swipeUp()
        XCTAssertTrue(!menu.isHittable || menu.frame.midY < firstRowY - 40, "The routine list should scroll.")
        XCTAssertFalse(header.exists)
        XCTAssertFalse(app.navigationBars["Routines"].exists)
        XCTAssertTrue(routines.isSelected)
        capture("Routines after scrolling", in: app)

        app.swipeDown()
        XCTAssertTrue(menu.isHittable)
        XCTAssertFalse(header.exists)
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
