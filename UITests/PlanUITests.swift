import XCTest

final class PlanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var calendar: Calendar { .current }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    private func launchPlan() -> XCUIApplication {
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

    private func capture(_ name: String, in app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func weekdayIndex(_ date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    private func dayCell(_ date: Date, in app: XCUIApplication) -> XCUIElement {
        app.buttons["weekday\(weekdayIndex(date))"]
    }

    private func dateOnWeekday(_ index: Int) -> Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: index - weekdayIndex(today), to: today)!
    }

    private func nextDateInMonth(to date: Date) -> Date {
        // Both destinations are in the currently displayed month.
        let offset = calendar.component(.day, from: date) < 20 ? 1 : -1
        return calendar.date(byAdding: .day, value: offset, to: date)!
    }

    private func selectDate(_ date: Date, in app: XCUIApplication) {
        let day = calendar.component(.day, from: date)
        let monthDay = date.formatted(.dateTime.month(.wide).day())
        let possibleLabels = [String(day), monthDay, date.formatted(.dateTime.weekday(.wide).month(.wide).day()), date.formatted(date: .complete, time: .omitted)]
        let cell = app.buttons.matching(NSPredicate(format: "label IN %@", possibleLabels)).firstMatch
        tap(cell)
    }

    func testMonthSelectionWeekSwipeAndTodayShortcut() {
        let app = launchPlan()
        let today = calendar.startOfDay(for: .now)
        let otherDay = nextDateInMonth(to: today)
        let actual = dayCell(today, in: app)
        let selected = dayCell(otherDay, in: app)
        XCTAssertTrue(actual.isSelected)
        XCTAssertTrue(actual.label.hasPrefix("Today, "))
        XCTAssertFalse(app.datePickers.firstMatch.exists)
        tap(app.buttons["monthYear"])
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 5))
        selectDate(otherDay, in: app)
        capture("Month calendar", in: app)
        tap(app.buttons["showPlanDate"])
        XCTAssertTrue(selected.isSelected)
        let original = selected.label
        XCTAssertTrue(original.contains(otherDay.formatted(date: .complete, time: .omitted)))

        let left = app.buttons["weekday1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let right = app.buttons["weekday5"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        right.press(forDuration: 0.08, thenDragTo: left)
        let next = calendar.date(byAdding: .weekOfYear, value: 1, to: otherDay)!
        XCTAssertTrue(selected.isSelected)
        XCTAssertTrue(selected.label.contains(next.formatted(date: .complete, time: .omitted)))
        tap(app.buttons["previousWeek"])
        XCTAssertEqual(selected.label, original)
        tap(app.buttons["jumpToToday"])
        XCTAssertTrue(actual.isSelected)
        XCTAssertTrue(actual.label.hasPrefix("Today, "))
        XCTAssertFalse(app.buttons["jumpToToday"].exists)
        capture("Plan week with today selected", in: app)
    }

    func testActiveWorkoutBelongsToItsSelectedDay() {
        let app = launchPlan()
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        tap(app.buttons["Close"])
        XCTAssertTrue(app.buttons["resumeWorkout"].waitForExistence(timeout: 5))
        tap(app.buttons["weekday2"])
        XCTAssertFalse(app.buttons["resumeWorkout"].exists)
        XCTAssertTrue(app.buttons["startPlanned"].isHittable)
        let accessory = app.buttons["resumeAccessory"]
        XCTAssertTrue(accessory.waitForExistence(timeout: 5))
        XCTAssertTrue(accessory.label.contains("Lower body"))
        capture("Plan with another day’s workout open", in: app)
        tap(app.buttons["startPlanned"])
        XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Finish Lower body before starting Upper body."].exists)
        capture("Review open workout before switching", in: app)
        tap(app.buttons["cancelWorkoutSwitch"])
        XCTAssertTrue(accessory.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["weekday2"].isSelected)
        tap(accessory)
        XCTAssertTrue(app.navigationBars["Lower body"].waitForExistence(timeout: 5))
        tap(app.buttons["Close"])
        tap(app.buttons["weekday0"])
        tap(app.buttons["resumeWorkout"])
        let reps = app.textFields["actualReps0"]
        tap(reps)
        reps.typeText("10")
        let load = app.textFields["actualLoad0"]
        tap(load)
        load.typeText("25")
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        tap(app.buttons["confirmSet0"])
        tap(app.buttons["Close"])
        tap(app.buttons["weekday2"])
        tap(app.buttons["startPlanned"])
        XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
        tap(app.buttons["finishPartial"])
        XCTAssertTrue(app.navigationBars["Upper body"].waitForExistence(timeout: 10))
        tap(app.buttons["Close"])
        tap(app.buttons["weekday2"])
        XCTAssertTrue(app.buttons["resumeWorkout"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["resumeAccessory"].exists)
        tap(app.buttons["weekday0"])
        XCTAssertTrue(app.buttons["startOccurrence"].exists)
        XCTAssertTrue(app.buttons["resumeAccessory"].label.contains("Upper body"))
    }

    func testRescheduleBackLeavesTemplateAndConfirmMovesOneWorkout() {
        let app = launchPlan()
        let original = dateOnWeekday(2)
        let target = nextDateInMonth(to: original)
        tap(dayCell(original, in: app))
        tap(app.buttons["rescheduleWorkout"])
        XCTAssertTrue(app.navigationBars["Reschedule"].waitForExistence(timeout: 5))
        selectDate(target, in: app)
        capture("Reschedule date selection", in: app)
        tap(app.navigationBars["Reschedule"].buttons["BackButton"])
        XCTAssertTrue(app.buttons["startPlanned"].waitForExistence(timeout: 5))
        tap(dayCell(target, in: app))
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 5))

        tap(dayCell(original, in: app))
        tap(app.buttons["rescheduleWorkout"])
        let commit = app.buttons["confirmReschedule"]
        XCTAssertFalse(commit.isEnabled)
        selectDate(target, in: app)
        XCTAssertTrue(commit.isEnabled)
        tap(commit)
        tap(dayCell(target, in: app))
        XCTAssertTrue(app.buttons["startOccurrence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Upper body"].exists)
        tap(dayCell(original, in: app))
        XCTAssertFalse(app.buttons["startOccurrence"].exists)
        XCTAssertFalse(app.buttons["startPlanned"].exists)
        tap(app.buttons["nextWeek"])
        XCTAssertTrue(app.buttons["startPlanned"].waitForExistence(timeout: 5))
    }

    func testCardioIconSchedulesSelectedDayAndCompletedReview() {
        let app = launchPlan()
        tap(app.buttons["weekday6"])
        tap(app.buttons["scheduleCardio"])
        for name in ["Walking", "Running", "Cycling", "Custom"] {
            XCTAssertTrue(app.buttons["cardioKind" + name].waitForExistence(timeout: 5))
        }
        capture("Choose a cardio activity", in: app)
        tap(app.buttons["cardioKindRunning"])
        let minutes = app.textFields["cardioGoalMinutes"]
        XCTAssertEqual(minutes.value as? String, "20")
        tap(minutes)
        minutes.doubleTap()
        minutes.typeText("5")
        XCTAssertEqual(minutes.value as? String, "5")
        if app.buttons["Done"].isHittable { tap(app.buttons["Done"]) }
        capture("Running duration and scheduled date", in: app)
        tap(app.buttons["saveScheduledCardio"])
        XCTAssertTrue(app.buttons["weekday6"].isSelected)
        XCTAssertTrue(app.staticTexts["Running"].exists)
        XCTAssertTrue(app.staticTexts["5 min cardio"].exists)
        tap(app.buttons["startOccurrence"])
        let seconds = app.textFields["cardioSeconds"]
        tap(seconds)
        seconds.typeText("300")
        tap(app.buttons["confirmCardio"])
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishSession"])
        XCTAssertTrue(app.buttons["weekday6"].isSelected)
        XCTAssertEqual(app.buttons["weekday6"].value as? String, "Complete")
        XCTAssertFalse(app.buttons["startOccurrence"].exists)
        tap(app.buttons["reviewOccurrence"])
        XCTAssertTrue(app.navigationBars["Workout review"].waitForExistence(timeout: 5))
        capture("Completed planned activity review", in: app)
        let records = app.buttons.matching(identifier: "reviewedSession")
        XCTAssertEqual(records.count, 1)
        tap(records.element)
        XCTAssertTrue(app.navigationBars["Running"].waitForExistence(timeout: 5))
    }
}
