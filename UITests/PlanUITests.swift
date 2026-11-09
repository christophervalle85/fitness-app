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

    private func launchPlan(reduceMotion: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        if reduceMotion { app.launchEnvironment["WEEKFORM_UI_TEST_REDUCE_MOTION"] = "1" }
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

    private func cancelConfirmation(_ title: String, confirmID: String, in app: XCUIApplication) {
        let confirm = app.buttons[confirmID].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        let cancel = app.buttons[title]
        if cancel.isHittable {
            cancel.tap()
        } else {
            // Compact iOS popovers dismiss through their background instead of a cancel row.
            let backdrop = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(backdrop.exists)
            backdrop.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55)).tap()
        }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
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
        let weekdayAndDate = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        var possibleLabels = [String(day), monthDay, weekdayAndDate, date.formatted(date: .complete, time: .omitted)]
        if calendar.isDateInToday(date) { possibleLabels.append("Today, " + weekdayAndDate) }
        let cell = app.buttons.matching(NSPredicate(format: "label IN %@", possibleLabels)).firstMatch
        tap(cell)
    }

    private func swipeWeek(forward: Bool, in app: XCUIApplication) {
        let left = app.buttons["weekday0"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let right = app.buttons["weekday6"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let from = forward ? right : left
        let to = forward ? left : right
        from.press(forDuration: 0.06, thenDragTo: to)
    }

    private func assertSelected(_ date: Date, in app: XCUIApplication, line: UInt = #line) {
        let cell = dayCell(date, in: app)
        let formatted = date.formatted(date: .complete, time: .omitted)
        let match = NSPredicate(format: "selected == true AND label CONTAINS %@", formatted)
        let changed = XCTNSPredicateExpectation(predicate: match, object: cell)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "Expected selected day \(formatted), found \(cell.label)", line: line)
        XCTAssertEqual(app.buttons.matching(identifier: cell.identifier).count, 1, line: line)
        XCTAssertTrue(cell.isHittable, "Selected day must be visible in the settled week", line: line)
        XCTAssertTrue(app.frame.contains(cell.frame), "Selected cell is outside the visible screen", line: line)
    }

    private func selectCalendarYear(from year: Int, to target: Int, in app: XCUIApplication) {
        tap(app.buttons["DatePicker.Show"])
        let yearWheel = app.pickerWheels.matching(NSPredicate(format: "value == %@", String(year))).firstMatch
        XCTAssertTrue(yearWheel.waitForExistence(timeout: 5))
        yearWheel.adjust(toPickerWheelValue: String(target))
        XCTAssertTrue(app.pickerWheels.matching(NSPredicate(format: "value == %@", String(target))).firstMatch.waitForExistence(timeout: 5))
        if target > year { capture("Calendar month and year selection", in: app) }
        tap(app.buttons.matching(NSPredicate(format: "identifier IN %@ OR label IN %@",
            ["DatePicker.Show", "DatePicker.Hide"], ["Hide year picker", "Show calendar"])).firstMatch)
    }

    func testMonthYearCalendarWeekPagingAndReturnToCurrentDate() {
        let app = launchPlan()
        let today = calendar.startOfDay(for: .now)
        let destination = calendar.date(byAdding: .year, value: 2, to: today)!
        let year = calendar.component(.year, from: today)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: calendar.dateInterval(of: .month, for: destination)!.end)!
        let next = calendar.date(byAdding: .day, value: 7, to: lastDay)!
        assertSelected(today, in: app)
        XCTAssertTrue(dayCell(today, in: app).label.hasPrefix("Today, "))
        XCTAssertFalse(app.datePickers.firstMatch.exists)
        for id in ["previousWeek", "nextWeek", "jumpToToday"] { XCTAssertFalse(app.buttons[id].exists) }

        tap(app.buttons["monthYear"])
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 5))
        selectCalendarYear(from: year, to: year + 2, in: app)
        selectDate(lastDay, in: app)
        capture("Month calendar", in: app)
        tap(app.buttons["showPlanDate"])
        assertSelected(lastDay, in: app)
        swipeWeek(forward: true, in: app)
        assertSelected(next, in: app)
        XCTAssertEqual(app.buttons["monthYear"].label, next.formatted(.dateTime.month(.wide).year()))
        swipeWeek(forward: false, in: app)
        assertSelected(lastDay, in: app)

        tap(app.buttons["monthYear"])
        selectCalendarYear(from: year + 2, to: year, in: app)
        selectDate(today, in: app)
        tap(app.buttons["showPlanDate"])
        assertSelected(today, in: app)
        XCTAssertTrue(dayCell(today, in: app).label.hasPrefix("Today, "))
        capture("Plan week with today selected", in: app)
    }

    func testConsecutiveWeekSwipesAndVerticalScrollPreserveSelection() {
        let app = launchPlan()
        let monday = dateOnWeekday(0)
        tap(dayCell(monday, in: app))
        for offset in 1...3 {
            swipeWeek(forward: true, in: app)
            assertSelected(calendar.date(byAdding: .day, value: 7 * offset, to: monday)!, in: app)
        }
        swipeWeek(forward: false, in: app)
        swipeWeek(forward: false, in: app)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        assertSelected(nextMonday, in: app)
        let anchor = app.buttons["weekday3"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = anchor.withOffset(CGVector(dx: 4, dy: -125))
        let initialHeader = app.buttons["monthYear"].frame.minY
        anchor.press(forDuration: 0.06, thenDragTo: destination)
        XCTAssertLessThan(app.buttons["monthYear"].frame.minY, initialHeader - 12)
        app.swipeDown()
        assertSelected(nextMonday, in: app)
        swipeWeek(forward: false, in: app)
        assertSelected(monday, in: app)
        let today = calendar.startOfDay(for: .now)
        XCTAssertTrue(dayCell(today, in: app).label.hasPrefix("Today, "))
    }

    func testReduceMotionKeepsWeekAndDaySelectionUsable() {
        let app = launchPlan(reduceMotion: true)
        let wednesday = dateOnWeekday(2)
        tap(dayCell(wednesday, in: app))
        swipeWeek(forward: true, in: app)
        assertSelected(calendar.date(byAdding: .day, value: 7, to: wednesday)!, in: app)
        swipeWeek(forward: false, in: app)
        assertSelected(wednesday, in: app)
        tap(app.buttons["weekday3"])
        assertSelected(dateOnWeekday(3), in: app)
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 5))
        capture("Plan with reduced motion", in: app)
    }

    func testOpenWorkoutsResumeIndependentlyOnTheirPlanDays() {
        let app = launchPlan()
        tap(app.buttons["weekday0"])
        XCTAssertEqual(app.staticTexts["planWorkoutStatus"].label, "Not started")
        tap(app.buttons["startPlanned"])
        XCTAssertTrue(app.navigationBars["Lower body"].waitForExistence(timeout: 5))
        let reps = app.textFields["actualReps0"]
        XCTAssertTrue(reps.waitForExistence(timeout: 5))
        XCTAssertEqual(reps.value as? String, "10")
        let load = app.textFields["actualLoad0"]
        tap(load)
        load.typeText("25")
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        tap(app.buttons["confirmSet0"])
        tap(app.buttons["Close"])

        tap(app.buttons["weekday2"])
        XCTAssertTrue(app.buttons["startPlanned"].isHittable)
        XCTAssertTrue(app.buttons["resumeAccessory"].label.contains("Lower body"))
        tap(app.buttons["startPlanned"])
        XCTAssertTrue(app.navigationBars["Upper body"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Workout summary"].exists)
        tap(app.buttons["Close"])

        tap(app.buttons["weekday0"])
        XCTAssertEqual(app.staticTexts["planWorkoutStatus"].label, "In progress")
        XCTAssertEqual(app.buttons["resumeWorkout"].label, "Resume Lower body")
        XCTAssertFalse(app.buttons["planWorkoutOptions"].exists)
        tap(app.buttons["resumeWorkout"])
        XCTAssertTrue(app.navigationBars["Lower body"].waitForExistence(timeout: 5))
        tap(app.buttons["reviewSession"])
        let finish = app.buttons["finishPartial"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        XCTAssertTrue(finish.isEnabled)
        tap(finish)

        XCTAssertTrue(app.buttons["startOccurrence"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["startOccurrence"].label, "Continue Lower body")
        tap(app.buttons["weekday2"])
        XCTAssertTrue(app.buttons["resumeWorkout"].waitForExistence(timeout: 5))
        tap(app.buttons["resumeWorkout"])
        XCTAssertTrue(app.navigationBars["Upper body"].waitForExistence(timeout: 5))
    }

    func testPastWeekHidesPlanChanges() {
        let app = launchPlan()
        tap(app.buttons["weekday0"])
        swipeWeek(forward: false, in: app)
        XCTAssertTrue(app.staticTexts["Lower body"].waitForExistence(timeout: 5))
        for id in ["startPlanned", "startOccurrence", "resumeWorkout", "planWorkoutOptions",
                   "scheduleCardio", "extraWorkout", "extraCardio"] {
            XCTAssertFalse(app.buttons[id].exists, "\(id) should be unavailable in a past week.")
        }
    }

    func testUnscheduledWorkoutCanResumeAfterStartingAnother() {
        let app = launchPlan()
        tap(app.buttons["weekday3"])
        tap(app.buttons["extraWorkout"])
        XCTAssertTrue(app.navigationBars["Extra workout"].waitForExistence(timeout: 5))
        tap(app.buttons["Close"])

        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        XCTAssertTrue(app.navigationBars["Lower body"].waitForExistence(timeout: 5))
        tap(app.buttons["Close"])
        tap(app.buttons["resumeUnscheduledWorkout"])
        XCTAssertTrue(app.navigationBars["Extra workout"].waitForExistence(timeout: 5))
    }

    func testRescheduleBackLeavesTemplateAndConfirmMovesOneWorkout() {
        let app = launchPlan()
        let original = dateOnWeekday(2)
        let target = nextDateInMonth(to: original)
        tap(dayCell(original, in: app))
        XCTAssertFalse(app.buttons["rescheduleWorkout"].exists)
        capture("Plan workout card and today marker", in: app)
        tap(app.buttons["planWorkoutOptions"])
        XCTAssertTrue(app.buttons["skipPlannedWorkout"].exists)
        XCTAssertFalse(app.buttons["removePlannedActivity"].exists)
        tap(app.buttons["rescheduleWorkout"])
        XCTAssertTrue(app.navigationBars["Reschedule"].waitForExistence(timeout: 5))
        selectDate(target, in: app)
        capture("Reschedule date selection", in: app)
        tap(app.navigationBars["Reschedule"].buttons["BackButton"])
        XCTAssertTrue(app.buttons["startPlanned"].waitForExistence(timeout: 5))
        tap(dayCell(target, in: app))
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 5))

        tap(dayCell(original, in: app))
        tap(app.buttons["planWorkoutOptions"])
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
        swipeWeek(forward: true, in: app)
        XCTAssertTrue(app.buttons["startPlanned"].waitForExistence(timeout: 5))

        tap(app.buttons["planWorkoutOptions"])
        tap(app.buttons["skipPlannedWorkout"])
        cancelConfirmation("Keep workout", confirmID: "confirmSkipWorkout", in: app)
        XCTAssertEqual(app.staticTexts["planWorkoutStatus"].label, "Not started")
        tap(app.buttons["planWorkoutOptions"])
        tap(app.buttons["skipPlannedWorkout"])
        tap(app.buttons["confirmSkipWorkout"].firstMatch)
        XCTAssertEqual(app.staticTexts["planWorkoutStatus"].label, "Skipped")
        XCTAssertFalse(app.buttons["startOccurrence"].exists)
        swipeWeek(forward: true, in: app)
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
        tap(app.buttons["planWorkoutOptions"])
        XCTAssertTrue(app.buttons["rescheduleWorkout"].exists)
        XCTAssertFalse(app.buttons["skipPlannedWorkout"].exists)
        tap(app.buttons["removePlannedActivity"])
        cancelConfirmation("Keep activity", confirmID: "confirmRemovePlannedActivity", in: app)
        XCTAssertEqual(app.staticTexts["planWorkoutStatus"].label, "Not started")
        tap(app.buttons["startOccurrence"])
        let seconds = app.textFields["cardioSeconds"]
        tap(seconds)
        seconds.typeText("300")
        tap(app.buttons["confirmCardio"])
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishSession"])
        XCTAssertTrue(app.buttons["weekday6"].isSelected)
        XCTAssertEqual(app.buttons["weekday6"].value as? String, "Complete")
        XCTAssertEqual(app.staticTexts["planWorkoutStatus"].label, "Finished")
        XCTAssertFalse(app.buttons["startOccurrence"].exists)
        tap(app.buttons["reviewOccurrence"])
        XCTAssertTrue(app.navigationBars["Workout review"].waitForExistence(timeout: 5))
        capture("Completed planned activity review", in: app)
        let records = app.buttons.matching(identifier: "reviewedSession")
        XCTAssertEqual(records.count, 1)
        tap(records.element)
        XCTAssertTrue(app.navigationBars["Running"].waitForExistence(timeout: 5))
        tap(app.navigationBars["Running"].buttons["BackButton"])
        tap(app.navigationBars["Workout review"].buttons["BackButton"])
        tap(app.buttons["planWorkoutOptions"])
        XCTAssertFalse(app.buttons["rescheduleWorkout"].exists)
        tap(app.buttons["removePlannedActivity"])
        tap(app.buttons["confirmRemovePlannedActivity"].firstMatch)
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["planWorkoutOptions"].exists)
        tap(app.tabBars.buttons["Progress"])
        tap(app.buttons["progressHistory"])
        XCTAssertTrue(app.buttons["historySession0"].label.contains("Running"))
    }
}
