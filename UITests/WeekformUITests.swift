import XCTest

final class WeekformUITests: XCTestCase {
    func testConfirmAndReopen() {
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["Weekform"].waitForExistence(timeout: 10))
        let status = app.descendants(matching: .any)["foundationStatus"]
        func waitForStatus(_ value: String) -> Bool {
            let predicate = NSPredicate(format: "exists == true AND value == %@", value)
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
            return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
        }
        XCTAssertTrue(waitForStatus("Ready"))
        let confirm = app.buttons["Confirm 8 reps"]
        XCTAssertTrue(confirm.exists)
        confirm.tap()
        XCTAssertTrue(waitForStatus("Saved"))
        app.terminate()
        app.launch()
        XCTAssertTrue(waitForStatus("Saved"))
        XCTAssertFalse(app.buttons["Confirm 8 reps"].exists)
    }
}
