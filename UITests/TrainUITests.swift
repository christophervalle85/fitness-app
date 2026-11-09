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
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
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
        XCTAssertFalse(app.tabBars.buttons["Plan"].isHittable)
        XCTAssertEqual(app.buttons["reviewSession"].label, "Finish")
        let workoutProgress = app.descendants(matching: .any)["workoutSetProgress"]
        XCTAssertTrue(workoutProgress.label.contains("Workout progress") || app.staticTexts["Workout progress"].exists)
        let firstReps = app.textFields["actualReps0"]
        let firstLoad = app.textFields["actualLoad0"]
        XCTAssertEqual(firstReps.value as? String, "10")
        XCTAssertFalse((firstLoad.value as? String)?.first?.isNumber == true)
        capture("Full-screen planned workout", in: app)
        tap(confirm)
        let issue = app.descendants(matching: .any)["setIssue0"]
        XCTAssertTrue(issue.waitForExistence(timeout: 5))
        XCTAssertTrue(issue.label.contains("weight"))
        XCTAssertFalse(app.buttons["undoSet0"].exists)
        enter("25", in: firstLoad)
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        XCTAssertEqual(firstLoad.value as? String, "25")
        tap(app.buttons["incrementActualReps0"])
        XCTAssertEqual(firstReps.value as? String, "11")
        XCTAssertFalse(app.buttons["undoSet0"].exists)
        tap(app.buttons["decrementActualReps0"])
        XCTAssertEqual(firstReps.value as? String, "10")
        tap(confirm)
        let loggedSet = app.buttons["editSet0"]
        XCTAssertTrue(loggedSet.waitForExistence(timeout: 5))
        XCTAssertEqual(loggedSet.label, "Set 1")
        let loggedValues = app.staticTexts["10 reps × 25 lb"]
        XCTAssertTrue(loggedValues.exists)
        XCTAssertGreaterThan(loggedValues.frame.minX, loggedSet.frame.maxX)
        XCTAssertFalse(app.buttons["undoSet0"].exists)
        tap(loggedSet)
        XCTAssertEqual(firstReps.value as? String, "10")
        tap(loggedSet)
        XCTAssertTrue(firstReps.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.textFields["actualReps1"].exists)
        let lowerSet = app.buttons["openSet2"]
        XCTAssertTrue(lowerSet.isHittable)
        let lowerSetY = lowerSet.frame.minY
        tap(lowerSet)
        let lowerReps = app.textFields["actualReps2"]
        XCTAssertTrue(lowerReps.waitForExistence(timeout: 5))
        XCTAssertEqual(lowerSet.frame.minY, lowerSetY, accuracy: 2)
        capture("Lower set expanded below its title", in: app)
        tap(lowerSet)
        XCTAssertTrue(lowerReps.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lowerSet.frame.minY, lowerSetY, accuracy: 2)
        XCTAssertFalse(app.textFields["actualReps1"].exists)
        tap(loggedSet)
        tap(app.buttons["incrementActualReps0"])
        tap(app.buttons["incrementActualLoad0"])
        capture("Expanded set editor", in: app)
        tap(app.buttons["saveSet0"])
        XCTAssertTrue(app.staticTexts["11 reps × 30 lb"].waitForExistence(timeout: 5))
        let nextReps = app.textFields["actualReps1"]
        XCTAssertFalse(nextReps.exists)
        tap(app.buttons["openSet1"])
        XCTAssertTrue(nextReps.waitForExistence(timeout: 5))
        XCTAssertEqual(nextReps.value as? String, "11")
        XCTAssertEqual(app.textFields["actualLoad1"].value as? String, "30")
        XCTAssertFalse(app.buttons["undoSet1"].exists)
        capture("Confirmed first set", in: app)

        app.terminate()
        app.launch()
        tap(app.buttons["weekday0"])
        tap(app.buttons["resumeWorkout"])
        XCTAssertTrue(loggedSet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["11 reps × 30 lb"].exists)
        tap(app.buttons["reviewSession"])
        XCTAssertTrue(app.buttons["finishPartial"].waitForExistence(timeout: 5))
        capture("Partial workout summary", in: app)
        tap(app.buttons["finishPartial"])
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["resumeWorkout"].exists)
        tap(app.buttons["weekday0"])
        XCTAssertTrue(app.staticTexts["Partial"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 / 6 sets")).firstMatch.exists)
        let groups = app.buttons.matching(identifier: "workoutSessions")
        XCTAssertEqual(groups.count, 1)
        tap(groups.element)
        XCTAssertTrue(app.buttons.matching(identifier: "savedSession").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "savedSession").count, 1)
        capture("Partial planned workout grouped on Plan", in: app)

        tap(app.buttons["startOccurrence"])
        let total = app.descendants(matching: .any)["workoutSetProgress"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue((total.label + String(describing: total.value)).contains("1 of 6"))
        let prior = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "priorSet-"))
        let priorDate = app.staticTexts["priorSetDate"]
        XCTAssertEqual(prior.count, 1)
        XCTAssertEqual(prior.element.label, "Set 1")
        XCTAssertTrue(app.staticTexts["11 reps × 30 lb"].exists)
        XCTAssertFalse(priorDate.exists)
        let next = app.descendants(matching: .any).matching(identifier: "currentSetLabel").firstMatch
        XCTAssertEqual(next.label, "Current set, Set 2")
        capture("Resumed workout with earlier set", in: app)

        tap(prior.element)
        XCTAssertTrue(priorDate.waitForExistence(timeout: 5))
        XCTAssertEqual(firstReps.value as? String, "11")
        XCTAssertEqual(firstLoad.value as? String, "30")
        tap(app.buttons["incrementActualLoad0"])
        capture("Earlier set correction", in: app)
        tap(app.buttons["saveSet0"])
        XCTAssertTrue(app.staticTexts["11 reps × 35 lb"].waitForExistence(timeout: 5))
        XCTAssertTrue(priorDate.waitForNonExistence(timeout: 5))
        XCTAssertTrue((total.label + String(describing: total.value)).contains("1 of 6"))
        XCTAssertEqual(next.label, "Current set, Set 2")
        tap(app.buttons["openSet0"])
        XCTAssertEqual(firstReps.value as? String, "10")
        XCTAssertFalse((firstLoad.value as? String)?.first?.isNumber == true)
        tap(app.buttons["incrementActualReps0"])
        XCTAssertEqual(firstReps.value as? String, "11")
        enter("30", in: firstLoad)
        XCTAssertEqual(firstLoad.value as? String, "30")
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        tap(app.buttons["confirmSet0"])
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishPartial"])
        let planTab = app.tabBars.buttons["Plan"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 10))
        XCTAssertTrue(planTab.isSelected)
        XCTAssertTrue(app.buttons["weekday0"].isSelected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "2 / 6 sets")).firstMatch.exists)
        XCTAssertEqual(groups.count, 1)
        let segments = app.buttons.matching(identifier: "savedSession")
        if segments.count == 0 { tap(groups.element) }
        XCTAssertTrue(segments.element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertEqual(segments.count, 2)
        tap(segments.element(boundBy: 0))
        XCTAssertTrue(app.navigationBars["Lower body"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1, 11 reps × 35 lb"].waitForExistence(timeout: 5))

        tap(app.tabBars.buttons["Progress"])
        let adherence = app.descendants(matching: .any)["adherence"]
        XCTAssertTrue(adherence.waitForExistence(timeout: 5))
        XCTAssertEqual(adherence.value as? String, "0 of 3")
        capture("Progress after two partial sessions", in: app)
    }

    func testExerciseFooterAddsAndRemovesOnlyItsAddedSet() {
        let app = startWithRoutine()
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        XCTAssertTrue(app.buttons["confirmSet0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Options for Squat"].exists)
        tap(app.buttons["openSet0"])

        let progress = app.descendants(matching: .any)["workoutSetProgress"]
        XCTAssertTrue((progress.value as? String)?.contains("0 of 6") == true)
        tap(app.buttons["addSet"])
        tap(app.buttons["Working set"])
        let addedSet = app.buttons["openSet3"]
        XCTAssertTrue(addedSet.waitForExistence(timeout: 5))
        XCTAssertEqual(addedSet.label, "Set 4")
        XCTAssertTrue((progress.value as? String)?.contains("0 of 7") == true)
        capture("Exercise footer with Set 4", in: app)

        func swipeRow(_ title: XCUIElement, from startX: CGFloat = 0.8, to endX: CGFloat = 0.2,
                      slow: Bool = false) {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let y = title.frame.midY - app.frame.minY
            let start = origin.withOffset(CGVector(dx: app.frame.width * startX, dy: y))
            let end = origin.withOffset(CGVector(dx: app.frame.width * endX, dy: y))
            if slow {
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            } else {
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }

        swipeRow(app.buttons["openSet2"])
        XCTAssertFalse(app.buttons["removeSet2"].exists)
        let remove = app.buttons["removeSet3"]
        let rowOrigin = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: app.frame.width * 0.8, dy: addedSet.frame.midY - app.frame.minY
        ))
        rowOrigin.press(forDuration: 0.05, thenDragTo: rowOrigin.withOffset(CGVector(dx: 0, dy: -88)))
        XCTAssertFalse(remove.exists)
        let originalFrame = addedSet.frame
        swipeRow(addedSet, to: 0.7)
        XCTAssertFalse(remove.exists)
        swipeRow(addedSet, slow: true)
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertEqual(addedSet.frame.minX, originalFrame.minX, accuracy: 2)
        XCTAssertEqual(addedSet.frame.minY, originalFrame.minY, accuracy: 2)
        XCTAssertTrue(addedSet.isHittable)
        XCTAssertTrue((progress.value as? String)?.contains("0 of 7") == true)
        capture("Swipe reveals Remove", in: app)
        swipeRow(addedSet, from: 0.3, to: 0.8)
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertEqual(addedSet.frame.minX, originalFrame.minX, accuracy: 2)
        swipeRow(addedSet)
        tap(remove)
        XCTAssertTrue(addedSet.waitForNonExistence(timeout: 5))
        XCTAssertTrue((progress.value as? String)?.contains("0 of 6") == true)
    }

    func testAssignSavedExtraCardioToScheduledGoal() {
        let app = startWithRoutine()
        tap(app.buttons["scheduleCardio"])
        tap(app.buttons["cardioKindCustom"])
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
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        XCTAssertTrue(credit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Partial"].exists)
        let group = app.buttons["workoutSessions"]
        XCTAssertTrue(group.exists)
        XCTAssertEqual(saved.count, 0)
        tap(group)
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.count, 1)
        tap(saved.firstMatch)
        XCTAssertTrue(app.navigationBars["Cardio"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Assign to planned work"].exists)
        tap(app.navigationBars.buttons.element(boundBy: 0))

        tap(app.buttons["extraCardio"])
        enter("120", in: app.textFields["cardioSeconds"])
        tap(app.buttons["confirmCardio"])
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishSession"])
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        XCTAssertTrue(credit.exists)
        if saved.count == 2 { tap(group) }
        XCTAssertEqual(saved.count, 1)
        tap(saved.element)
        XCTAssertTrue(app.buttons["Assign to planned work"].waitForExistence(timeout: 5))
        tap(app.navigationBars.buttons.element(boundBy: 0))
        tap(group)
        XCTAssertEqual(saved.count, 2)
        capture("Planned activity and separate extra cardio", in: app)
    }

    func testFulfilledCardioMarksOnlyItsScheduledDayComplete() {
        let app = startWithRoutine()
        tap(app.buttons["weekday6"])
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 5))
        tap(app.buttons["scheduleCardio"])
        tap(app.buttons["cardioKindCustom"])
        enter("Sunday walk", in: app.textFields["scheduledCardioName"])
        tap(app.buttons["saveScheduledCardio"])
        XCTAssertEqual(app.buttons["weekday6"].value as? String, "Workout")
        tap(app.buttons["startOccurrence"])
        enter("1200", in: app.textFields["cardioSeconds"])
        tap(app.buttons["confirmCardio"])
        tap(app.buttons["reviewSession"])
        tap(app.buttons["finishSession"])

        let planTab = app.tabBars.buttons["Plan"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 10))
        XCTAssertTrue(planTab.isSelected)
        XCTAssertTrue(app.buttons["weekday6"].isSelected)
        XCTAssertEqual(app.buttons["weekday6"].value as? String, "Complete")
        XCTAssertEqual(app.buttons["weekday0"].value as? String, "Workout")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1200 / 1200 seconds")).firstMatch.exists)
        tap(app.buttons["workoutSessions"])
        let segments = app.buttons.matching(identifier: "savedSession")
        XCTAssertTrue(segments.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(segments.count, 1)
        capture("Completed cardio on scheduled day", in: app)
        tap(segments.element)
        XCTAssertTrue(app.navigationBars["Sunday walk"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["resumeWorkout"].exists)
        let performedWeekday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        XCTAssertTrue(app.buttons["weekday\(performedWeekday)"].isSelected)
        XCTAssertTrue(app.buttons["savedSession"].exists)
        tap(app.buttons["weekday6"])
        XCTAssertTrue(app.staticTexts["Rest day"].exists)
        tap(app.buttons["weekday0"])
        XCTAssertTrue(app.buttons["startPlanned"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["planWorkoutStatus"].label, "Not started")
    }
}
