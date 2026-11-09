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
        let field = app.searchFields["Search"].firstMatch
        tap(field)
        field.typeText(text)
    }

    private func searchPicker(_ text: String, in app: XCUIApplication) {
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
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        tap(app.buttons["Close"])
        tap(app.tabBars.buttons["Exercises"])
        let accessory = app.buttons["resumeAccessory"]
        XCTAssertTrue(accessory.waitForExistence(timeout: 5))
        let field = app.searchFields["Search"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        XCTAssertLessThan(field.frame.maxY, app.frame.height * 0.38)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'catalogRow-'")).firstMatch.exists)
        for id in ["exercisesFavorites", "exercisesMyExercises", "exercisesBrowseAll", "exercisesFilters", "newCustomExercise"] {
            XCTAssertFalse(app.buttons[id].exists)
        }
        screenshot("Blank Exercises with native search", in: app)
        search("machine chest press", in: app)
        field.typeText("\n")
        let original = "Machine chest press"
        let alternative = "Pec deck fly"
        XCTAssertFalse(app.buttons["catalogRow-Barbell row"].exists)
        tap(app.buttons["catalogRow-" + original])
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
        XCTAssertFalse(field.isHittable)
        XCTAssertTrue(app.buttons["favoriteExercise"].exists)
        XCTAssertFalse(app.tabBars.buttons["Exercises"].isHittable)
        let nativeBar = app.navigationBars.firstMatch
        XCTAssertFalse(nativeBar.exists && nativeBar.isHittable)
        XCTAssertFalse(accessory.isHittable)
        let pose = app.images["catalogFrame1"]
        XCTAssertTrue(pose.waitForExistence(timeout: 5))
        XCTAssertEqual(pose.label, original + " demonstration, image 1")
        XCTAssertFalse(app.buttons["catalogFrame1"].exists)
        XCTAssertTrue(app.staticTexts["Instructions"].exists)
        screenshot("Exercise movement guide", in: app)

        let history = app.descendants(matching: .any)["exerciseHistoryMax"].firstMatch
        for _ in 0..<5 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue((history.label + String(describing: history.value)).contains("N/A"))
        let lastLogged = app.descendants(matching: .any)["exerciseHistoryLastLogged"].firstMatch
        XCTAssertTrue((lastLogged.label + String(describing: lastLogged.value)).contains("N/A"))
        screenshot("Exercise history without logged sets", in: app)

        let cards = app.scrollViews["similarExerciseCards"].firstMatch
        for _ in 0..<8 where !cards.isHittable { app.swipeUp() }
        XCTAssertTrue(cards.waitForExistence(timeout: 5))
        let firstCard = app.buttons["catalogAlternative-Barbell bench press"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        let firstCardHeight = firstCard.frame.height
        XCTAssertGreaterThan(firstCardHeight, 0)
        let candidate = app.buttons["catalogAlternative-" + alternative]
        for _ in 0..<8 {
            if candidate.exists, !candidate.frame.isEmpty,
               cards.frame.contains(CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)) { break }
            cards.swipeLeft()
        }
        XCTAssertEqual(candidate.frame.height, firstCardHeight, accuracy: 1)
        screenshot("Even similar exercise cards", in: app)
        tap(candidate)
        XCTAssertTrue(app.staticTexts[alternative].waitForExistence(timeout: 5))
        XCTAssertFalse(accessory.isHittable)
        screenshot("Selected comparable alternative", in: app)
        tap(app.buttons["exerciseDetailBack"])
        XCTAssertFalse(accessory.isHittable)
        let credits = app.descendants(matching: .any)["exerciseSourceCredits"].firstMatch
        for _ in 0..<4 where !credits.exists || !credits.isHittable { app.swipeUp() }
        XCTAssertTrue(credits.exists)
        screenshot("Compact illustration credits", in: app)
        tap(app.buttons["exerciseDetailBack"])
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Exercises"].isHittable)
        tap(accessory)
        tap(app.buttons["reviewSession"])
        tap(app.buttons["Discard empty workout"])
        tap(app.buttons["Discard workout"].firstMatch)
    }

    func testSwapRemainingSetsUsingBundledCatalog() {
        let app = launchWithRoutine()
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        let reps = app.textFields["actualReps0"]
        let load = app.textFields["actualLoad0"]
        XCTAssertTrue(reps.waitForExistence(timeout: 5))
        XCTAssertEqual(reps.value as? String, "10")
        tap(load)
        load.typeText("25")
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        tap(app.buttons["confirmSet0"])
        XCTAssertTrue(app.buttons["editSet0"].waitForExistence(timeout: 5))
        let swap = app.buttons["swapExercise"]
        for _ in 0..<8 where !swap.isHittable { app.swipeUp() }
        tap(swap)
        tap(app.buttons["browseCatalog"])
        let replacement = "Barbell front squat"
        searchPicker(replacement, in: app)
        tap(app.buttons["catalogRow-" + replacement])
        tap(app.buttons["useCatalogExercise"])
        tap(app.buttons["customSave"])

        XCTAssertTrue(app.buttons[replacement].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["jumpExercise"].exists)
        XCTAssertFalse(app.buttons["undoSet0"].exists)
        let squatGroup = app.buttons["Squat"]
        for _ in 0..<5 where !squatGroup.isHittable { app.swipeDown() }
        XCTAssertTrue(squatGroup.waitForExistence(timeout: 5))
        if (squatGroup.value as? String)?.hasSuffix("collapsed") == true { tap(squatGroup) }
        tap(app.buttons["editSet0"])
        XCTAssertTrue(app.buttons["saveSet0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["undoSet0"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        tap(app.buttons["editSet0"])
        // End this run's Live Activity so SpringBoard can present the next workout.
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishPartial"])
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
    }

    func testCustomExerciseFavoritePersistsAndStaysWithItsProfile() {
        let app = launchWithRoutine()
        let name = "Test band march"
        let routines = app.tabBars.buttons["Routines"]
        tap(routines)
        if app.buttons["routineActions"].exists {
            tap(app.buttons["routineActions"])
            tap(app.buttons["editRoutine"])
        } else {
            tap(app.buttons["Edit routine"])
        }
        tap(app.buttons["day0"])
        tap(app.buttons.containing(.staticText, identifier: "Squat").firstMatch)
        tap(app.buttons["Choose from exercise library"])
        tap(app.buttons["newCustomExercise"])
        let nameField = app.textFields["customCatalogName"]
        tap(nameField)
        nameField.typeText(name)
        tap(app.buttons["saveCatalogCustom"])
        tap(app.navigationBars.buttons["Close"])
        tap(app.navigationBars.buttons["Done"])
        tap(app.navigationBars.buttons["BackButton"])
        tap(app.navigationBars.buttons["Cancel"])
        if !routines.waitForExistence(timeout: 3) { tap(app.buttons["Discard draft"]) }
        tap(app.tabBars.buttons["Exercises"])
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
        search(name, in: app)
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
        XCTAssertFalse(secondProfile.buttons["newCustomExercise"].exists)
    }

    func testMuscleSearchWithAnOpenWorkout() {
        let app = launchWithRoutine()
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        tap(app.buttons["Close"])
        tap(app.tabBars.buttons["Exercises"])
        let resume = app.buttons["resumeAccessory"]
        let field = app.searchFields["Search"].firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertLessThan(field.frame.maxY, resume.frame.minY)
        screenshot("Exercises with the workout Resume bar", in: app)

        search("chest", in: app)
        let bench = app.buttons["catalogRow-Barbell bench press"]
        let dumbbell = app.buttons["catalogRow-Dumbbell bench press"]
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        XCTAssertTrue(dumbbell.exists)
        XCTAssertFalse(app.buttons["catalogRow-Barbell curl"].exists)
        field.typeText(" dumbbell")
        XCTAssertTrue(bench.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dumbbell.exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertLessThan(field.frame.maxY, app.frame.height * 0.38)
        screenshot("Native search for chest and dumbbell", in: app)
        tap(field.buttons["Clear text"].firstMatch)
        XCTAssertTrue(dumbbell.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No matching exercises"].exists)
        search("chest", in: app)
        field.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        tap(resume)
        tap(app.buttons["reviewSession"])
        tap(app.buttons["Discard empty workout"])
        tap(app.buttons["Discard workout"].firstMatch)
    }
}
