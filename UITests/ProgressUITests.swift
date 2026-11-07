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

    func testHistoryCorrectionRecalculatesRecordsAndUndoRemovesLastRecord() {
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
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
        tap(app.buttons["confirmSet0"])
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishPartial"])

        func tapOverviewControl(_ element: XCUIElement) {
            for _ in 0..<5 where !element.isHittable { app.swipeUp() }
            if !element.isHittable {
                for _ in 0..<5 where !element.isHittable { app.swipeDown() }
            }
            tap(element)
        }
        func openProgress() {
            tap(app.tabBars.buttons["Progress"])
            XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        }
        func openRecord() {
            tapOverviewControl(app.buttons["progressRecords"])
            let search = app.searchFields["Find an exercise"].firstMatch
            tap(search)
            search.typeText("squat\n")
            tap(app.buttons["recordGroup0"])
        }
        func setUnit(_ unit: String) {
            tap(app.buttons["progressSettings"])
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            let option = app.segmentedControls["weightUnit"].buttons[unit]
            tap(option)
            XCTAssertTrue(option.isSelected)
            tap(app.navigationBars["Settings"].buttons.element(boundBy: 0))
            XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        }
        func openLoggedSet() {
            tapOverviewControl(app.buttons["progressHistory"])
            tap(app.buttons["historySession0"])
            tap(app.buttons["historySet0-0"])
        }
        func backToProgress() {
            let overview = app.navigationBars["Progress"]
            // The native search presentation adds its own Close button on the way back from a record.
            for _ in 0..<3 where !overview.exists {
                tap(app.navigationBars.buttons.element(boundBy: 0))
            }
            XCTAssertTrue(overview.waitForExistence(timeout: 5))
        }

        openProgress()
        capture("Progress overview", in: app)
        XCTAssertFalse(app.segmentedControls["weightUnit"].exists)
        XCTAssertTrue(app.buttons["recentSession0"].exists)
        let chart = app.descendants(matching: .any)["progressActivityChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let earlierDay = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.45))
        let finalDay = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.45))
        earlierDay.tap()
        XCTAssertTrue(app.staticTexts["0 finished sessions"].waitForExistence(timeout: 5), app.debugDescription)
        earlierDay.press(forDuration: 0.1, thenDragTo: finalDay)
        XCTAssertTrue(app.staticTexts["1 finished session"].waitForExistence(timeout: 5))
        let dayPicker = app.descendants(matching: .any)["progressActivityDay"].firstMatch
        XCTAssertTrue(dayPicker.waitForExistence(timeout: 5), app.debugDescription)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        tap(dayPicker)
        tap(app.buttons[yesterday.formatted(date: .complete, time: .omitted)].firstMatch)
        XCTAssertTrue(app.staticTexts["0 finished sessions"].waitForExistence(timeout: 5))
        tap(dayPicker)
        let today = Date.now.formatted(date: .complete, time: .omitted)
        tap(app.buttons[today].firstMatch)
        XCTAssertTrue(app.buttons["progressDaySession0"].waitForExistence(timeout: 5))
        capture("Selected day on the activity chart", in: app)
        let chartTop = chart.frame.minY
        let scrollStart = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        scrollStart.press(forDuration: 0.08, thenDragTo: scrollStart.withOffset(CGVector(dx: 0, dy: -150)))
        XCTAssertLessThan(chart.frame.minY, chartTop - 20, "Vertical swipes should scroll Progress.")
        openRecord()
        XCTAssertTrue(app.staticTexts["25 lb · 10 reps"].firstMatch.waitForExistence(timeout: 5))
        capture("Exercise record", in: app)
        backToProgress()

        setUnit("kg")
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
        tapOverviewControl(app.buttons["progressRecords"])
        XCTAssertTrue(app.staticTexts["No exercise records yet"].waitForExistence(timeout: 5))
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
        XCTAssertFalse(app.descendants(matching: .any)["progressActivityChart"].firstMatch.exists)
        XCTAssertFalse(app.buttons["backupRecovery"].exists)
        capture("Progress before the first workout", in: app)

        tap(app.buttons["progressSettings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("Progress settings", in: app)
        tap(app.buttons["Lock Screen privacy"])
        XCTAssertTrue(app.navigationBars["Lock Screen privacy"].waitForExistence(timeout: 5))
        tap(app.navigationBars["Lock Screen privacy"].buttons.element(boundBy: 0))
        tap(app.buttons["backupRecovery"])
        XCTAssertTrue(app.navigationBars["Backup and export"].waitForExistence(timeout: 5))
    }
}
