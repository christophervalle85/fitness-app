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
            tap(app.buttons["recordGroup0"])
        }
        func openLoggedSet() {
            tapOverviewControl(app.buttons["progressHistory"])
            tap(app.buttons["historySession0"])
            tap(app.buttons["historySet0-0"])
        }
        func backToProgress() {
            tap(app.navigationBars.buttons.element(boundBy: 0))
            tap(app.navigationBars.buttons.element(boundBy: 0))
            XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        }

        openProgress()
        capture("Progress overview", in: app)
        openRecord()
        XCTAssertTrue(app.staticTexts["25 lb · 10 reps"].firstMatch.waitForExistence(timeout: 5))
        capture("Exercise record", in: app)
        backToProgress()

        tapOverviewControl(app.segmentedControls["weightUnit"].buttons["kg"])
        openRecord()
        XCTAssertTrue(app.staticTexts["11.34 kg · 10 reps"].firstMatch.waitForExistence(timeout: 5))
        backToProgress()
        tapOverviewControl(app.segmentedControls["weightUnit"].buttons["lb"])

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
        XCTAssertTrue(app.staticTexts["No exercise records"].waitForExistence(timeout: 5))
    }
}
