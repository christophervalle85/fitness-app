import XCTest

final class DiscoverUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    private func launchWithRoutine() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        return app
    }

    private func search(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["catalogSearch"]
        tap(field)
        field.typeText(text)
    }

    private func screenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBundledSearchAndComparableAlternative() {
        let app = launchWithRoutine()
        tap(app.tabBars.buttons["Exercises"])
        XCTAssertTrue(app.buttons["catalogRow-Barbell bench press"].waitForExistence(timeout: 5))
        screenshot("Offline exercise catalog", in: app)
        search("bench press", in: app)
        let original = "Barbell bench press"
        let alternative = "Dumbbell bench press"
        XCTAssertFalse(app.buttons["catalogRow-Barbell row"].exists)
        tap(app.buttons["catalogRow-" + original])
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["favoriteExercise"].exists)
        screenshot("Exercise detail gallery", in: app)
        tap(app.buttons["catalogFrame1"])
        XCTAssertTrue(app.navigationBars["Frame 1 of 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images[original + " demonstration, image 1"].exists)
        screenshot("Expanded first demonstration frame", in: app)
        tap(app.navigationBars.buttons.element(boundBy: 0))
        XCTAssertTrue(app.buttons["favoriteExercise"].waitForExistence(timeout: 5))

        let candidate = app.buttons["catalogAlternative-" + alternative]
        for _ in 0..<12 where !candidate.isHittable { app.swipeUp() }
        tap(candidate)
        XCTAssertTrue(app.staticTexts[alternative].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["favoriteExercise"].exists)
        screenshot("Selected comparable alternative", in: app)
    }

    func testSwapRemainingSetsUsingBundledCatalog() {
        let app = launchWithRoutine()
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        let reps = app.textFields["actualReps0"]
        let load = app.textFields["actualLoad0"]
        tap(reps)
        reps.typeText("10")
        tap(load)
        load.typeText("25")
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        tap(app.buttons["confirmSet0"])
        XCTAssertTrue(app.buttons["undoSet0"].waitForExistence(timeout: 5))
        let swap = app.buttons["swapExercise"]
        for _ in 0..<8 where !swap.isHittable { app.swipeUp() }
        tap(swap)
        tap(app.buttons["browseCatalog"])
        let replacement = "Barbell front squat"
        search(replacement, in: app)
        tap(app.buttons["catalogRow-" + replacement])
        tap(app.buttons["useCatalogExercise"])
        tap(app.buttons["customSave"])

        let exerciseMenu = app.buttons["jumpExercise"]
        for _ in 0..<5 where !exerciseMenu.isHittable { app.swipeDown() }
        XCTAssertTrue(exerciseMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(exerciseMenu.label.contains(replacement))
        XCTAssertFalse(app.buttons["undoSet0"].exists)
        tap(exerciseMenu)
        tap(app.buttons["Squat"])
        XCTAssertTrue(app.buttons["undoSet0"].waitForExistence(timeout: 5))
        // End this run's Live Activity so SpringBoard can present the next workout.
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishPartial"])
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
    }

    func testCustomExerciseFavoritePersistsAndStaysWithItsProfile() {
        let app = launchWithRoutine()
        let name = "Test band march"
        tap(app.tabBars.buttons["Exercises"])
        tap(app.buttons["newCustomExercise"])
        let nameField = app.textFields["customCatalogName"]
        tap(nameField)
        nameField.typeText(name)
        tap(app.buttons["saveCatalogCustom"])
        search(name, in: app)
        let row = app.buttons["catalogRow-" + name]
        tap(row)
        let favorite = app.buttons["favoriteExercise"]
        XCTAssertEqual(favorite.label, "Add favorite")
        tap(favorite)
        XCTAssertEqual(favorite.label, "Remove favorite")

        app.terminate()
        app.launch()
        tap(app.tabBars.buttons["Exercises"])
        tap(app.buttons["Filter exercises"])
        tap(app.descendants(matching: .any)["Favorites only"].firstMatch)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'catalogRow-'")).count, 1)
        tap(row)
        XCTAssertEqual(favorite.label, "Remove favorite")
        XCTAssertTrue(app.staticTexts["No sets recorded yet."].exists)
        screenshot("Saved custom exercise", in: app)

        app.terminate()
        let secondProfile = launchWithRoutine()
        tap(secondProfile.tabBars.buttons["Exercises"])
        search(name, in: secondProfile)
        XCTAssertTrue(secondProfile.staticTexts["No matching exercises"].waitForExistence(timeout: 5))
        XCTAssertFalse(secondProfile.buttons["catalogRow-" + name].exists)
    }
}
