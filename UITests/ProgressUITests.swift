import XCTest

final class ProgressUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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

    private func assertProgressTitleHidden(in app: XCUIApplication, line: UInt = #line) {
        XCTAssertFalse(app.navigationBars["Progress"].exists, line: line)
        XCTAssertFalse(app.navigationBars.staticTexts["Progress"].exists, line: line)
    }

    func testHistoryCorrectionRecalculatesRecordsAndUndoRemovesLastRecord() {
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        let exercise = "Barbell bench press"
        tap(app.buttons["day0"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Squat")).firstMatch)
        tap(app.buttons["Choose from exercise library"])
        let catalogSearch = app.textFields["catalogSearch"]
        tap(catalogSearch)
        catalogSearch.typeText(exercise)
        tap(app.buttons["catalogRow-" + exercise])
        tap(app.buttons["useCatalogExercise"])
        tap(app.navigationBars.buttons["Done"])
        tap(app.navigationBars.buttons.element(boundBy: 0))
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])

        let reps = app.textFields["actualReps0"]
        let load = app.textFields["actualLoad0"]
        tap(reps)
        reps.typeText("10")
        tap(load)
        load.typeText("25")
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        let loggedDate = Date.now.formatted(.dateTime.month(.abbreviated).day().year())
        tap(app.buttons["confirmSet0"])
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishPartial"])

        func revealOverviewControl(_ element: XCUIElement) {
            for _ in 0..<5 where !element.isHittable { app.swipeUp() }
            if !element.isHittable {
                for _ in 0..<5 where !element.isHittable { app.swipeDown() }
            }
            XCTAssertTrue(element.isHittable)
        }
        let settings = app.navigationBars.buttons["progressSettings"]
        func openProgress() {
            tap(app.tabBars.buttons["Progress"])
            XCTAssertTrue(settings.waitForExistence(timeout: 10))
            assertProgressTitleHidden(in: app)
        }
        let routineRecord = app.buttons["progressExerciseRecord-" + exercise]
        func openRecord() {
            revealOverviewControl(routineRecord)
            tap(routineRecord)
        }
        func setUnit(_ unit: String) {
            tap(settings)
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            let option = app.segmentedControls["weightUnit"].buttons[unit]
            tap(option)
            XCTAssertTrue(option.isSelected)
            tap(app.navigationBars["Settings"].buttons.element(boundBy: 0))
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
        }
        func openLoggedSet() {
            let history = app.buttons["progressHistory"]
            revealOverviewControl(history)
            tap(history)
            tap(app.buttons["historySession0"])
            tap(app.buttons["historySet0-0"])
        }
        func backToProgress() {
            for _ in 0..<3 where !settings.isHittable {
                tap(app.navigationBars.buttons.element(boundBy: 0))
            }
            XCTAssertTrue(settings.isHittable)
            assertProgressTitleHidden(in: app)
        }

        openProgress()
        capture("Progress overview", in: app)
        XCTAssertFalse(app.segmentedControls["weightUnit"].exists)
        XCTAssertFalse(app.staticTexts["Includes dated workouts and upcoming days in your current routine."].exists)
        XCTAssertFalse(app.buttons["recentSession0"].exists)
        XCTAssertFalse(app.buttons["progressRecords"].exists)
        XCTAssertFalse(app.staticTexts["Best logged working sets"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "progressHistory").count, 1)
        XCTAssertEqual(app.buttons["progressHistory"].label, "Workout history")
        XCTAssertFalse(app.staticTexts["View workout history"].exists)
        let chart = app.descendants(matching: .any)["progressActivityChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let earlierDay = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.45))
        let finalDay = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.45))
        earlierDay.tap()
        XCTAssertTrue(app.staticTexts["No sessions logged."].waitForExistence(timeout: 5), app.debugDescription)
        earlierDay.press(forDuration: 0.1, thenDragTo: finalDay)
        XCTAssertTrue(app.buttons["progressDaySession0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["progressActivityDay"].firstMatch.exists)
        let selectedDate = app.descendants(matching: .any)["progressSelectedDate"].firstMatch
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.45)).tap()
        XCTAssertTrue(app.staticTexts["No sessions logged."].waitForExistence(timeout: 5))
        XCTAssertEqual(selectedDate.label, yesterday.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        finalDay.tap()
        let daySession = app.buttons["progressDaySession0"]
        XCTAssertTrue(daySession.waitForExistence(timeout: 5))
        XCTAssertTrue(daySession.label.contains("Partial"))
        XCTAssertFalse(daySession.label.contains(Date.now.formatted(date: .abbreviated, time: .omitted)))
        capture("Selected day on the activity chart", in: app)
        let chartTop = chart.frame.minY
        let scrollStart = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        scrollStart.press(forDuration: 0.08, thenDragTo: scrollStart.withOffset(CGVector(dx: 0, dy: -150)))
        XCTAssertLessThan(chart.frame.minY, chartTop - 20, "Vertical swipes should scroll Progress.")
        assertProgressTitleHidden(in: app)
        revealOverviewControl(routineRecord)
        XCTAssertTrue(app.staticTexts["progressExerciseMuscle-Chest"].exists)
        XCTAssertFalse(app.staticTexts["Monday"].exists)
        XCTAssertTrue(routineRecord.label.contains("25"))
        XCTAssertTrue(routineRecord.label.contains(loggedDate))
        capture("Exercise record rows by muscle", in: app)
        tap(routineRecord)
        XCTAssertTrue(app.navigationBars[exercise].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["exerciseWorkoutTrend"].firstMatch.waitForExistence(timeout: 5))
        capture("Exercise trend from the routine", in: app)
        XCTAssertTrue(app.staticTexts["25 lb · 10 reps"].firstMatch.waitForExistence(timeout: 5))
        backToProgress()

        setUnit("kg")
        revealOverviewControl(routineRecord)
        XCTAssertTrue(routineRecord.label.contains("11.34"))
        openRecord()
        XCTAssertTrue(app.staticTexts["11.34 kg · 10 reps"].firstMatch.waitForExistence(timeout: 5))
        backToProgress()
        setUnit("lb")

        openLoggedSet()
        capture("Correct a working set", in: app)
        let correctReps = app.textFields["correctReps"]
        XCTAssertTrue(correctReps.waitForExistence(timeout: 5))
        correctReps.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).doubleTap()
        correctReps.typeText("8")
        XCTAssertEqual(correctReps.value as? String, "8")
        tap(app.buttons["saveCorrection"])
        backToProgress()
        openRecord()
        XCTAssertTrue(app.staticTexts["25 lb · 8 reps"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["25 lb · 10 reps"].firstMatch.exists)
        backToProgress()

        openLoggedSet()
        tap(app.buttons["undoHistorySet"])
        app.terminate()
        app.launch()
        openProgress()
        let emptyRecord = app.descendants(matching: .any)["progressExerciseRecord-" + exercise].firstMatch
        revealOverviewControl(emptyRecord)
        XCTAssertFalse(routineRecord.exists)
        XCTAssertTrue(emptyRecord.label.contains("No result logged"))
        XCTAssertTrue(emptyRecord.label.contains("Date unavailable"))
        XCTAssertFalse(emptyRecord.label.contains(loggedDate))
        capture("Exercise record row without a result", in: app)
    }

    func testEmptyActivityAndSettingsDestinations() {
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        tap(app.tabBars.buttons["Progress"])
        XCTAssertTrue(app.staticTexts["No finished workouts in the last seven days."].waitForExistence(timeout: 5))
        assertProgressTitleHidden(in: app)
        let emptyRecord = app.descendants(matching: .any)["progressExerciseRecord-Hip hinge"].firstMatch
        XCTAssertTrue(emptyRecord.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyRecord.label.contains("pounds"))
        XCTAssertTrue(emptyRecord.label.contains("Date unavailable"))
        XCTAssertFalse(app.descendants(matching: .any)["progressActivityChart"].firstMatch.exists)
        XCTAssertFalse(app.buttons["backupRecovery"].exists)
        capture("Progress before the first workout", in: app)

        let history = app.buttons["progressHistory"]
        let activityHeading = app.staticTexts["Last 7 days"]
        XCTAssertTrue(history.isHittable)
        XCTAssertEqual(history.label, "Workout history")
        XCTAssertGreaterThanOrEqual(history.frame.width, 43.99)
        XCTAssertGreaterThanOrEqual(history.frame.height, 43.99)
        XCTAssertGreaterThan(history.frame.minX, activityHeading.frame.maxX)
        XCTAssertEqual(history.frame.midY, activityHeading.frame.midY, accuracy: 2)
        tap(history)
        XCTAssertTrue(app.navigationBars["Workout history"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No finished workouts"].exists)
        tap(app.navigationBars["Workout history"].buttons.element(boundBy: 0))
        assertProgressTitleHidden(in: app)

        tap(app.buttons["progressSettings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("Progress settings", in: app)
        tap(app.segmentedControls["weightUnit"].buttons["kg"])
        tap(app.navigationBars["Settings"].buttons.element(boundBy: 0))
        XCTAssertTrue(emptyRecord.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyRecord.label.contains("kg"))
        assertProgressTitleHidden(in: app)
        tap(app.buttons["progressSettings"])
        tap(app.buttons["Lock Screen privacy"])
        XCTAssertTrue(app.navigationBars["Lock Screen privacy"].waitForExistence(timeout: 5))
        tap(app.navigationBars["Lock Screen privacy"].buttons.element(boundBy: 0))
        tap(app.buttons["backupRecovery"])
        XCTAssertTrue(app.navigationBars["Backup and export"].waitForExistence(timeout: 5))
    }
}
