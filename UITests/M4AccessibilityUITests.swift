import UIKit
import XCTest

final class M4AccessibilityUITests: XCTestCase {
    @MainActor
    func testExerciseListAtLargeTextInLightMode() throws {
        try audit(.light, detail: false)
    }

    @MainActor
    func testExerciseListAtLargeTextInDarkMode() throws {
        try audit(.dark, detail: false)
    }

    @MainActor
    func testUnobstructedBarbellCurlAtLargeTextInLightMode() throws {
        try audit(.light, detail: false, searchCurl: true)
    }

    @MainActor
    func testUnobstructedBarbellCurlAtLargeTextInDarkMode() throws {
        try audit(.dark, detail: false, searchCurl: true)
    }

    @MainActor
    func testExerciseDetailAtLargeTextInLightMode() throws {
        try audit(.light, detail: true)
    }

    @MainActor
    func testExerciseDetailAtLargeTextInDarkMode() throws {
        try audit(.dark, detail: true)
    }

    @MainActor
    func testExpandedLiveRestOnSpringBoard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launch()

        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)")
            element.tap()
        }
        func captureScreen(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        tap(app.buttons["weekday0"])
        tap(app.buttons["startPlanned"])
        defer {
            app.activate()
            if app.buttons["reviewSession"].exists {
                app.buttons["reviewSession"].tap()
                if app.buttons["finishPartial"].exists { app.buttons["finishPartial"].tap() }
            }
        }
        tap(app.buttons["workoutRest"])
        tap(app.buttons["90 seconds"])
        let reps = app.textFields["actualReps0"]
        for _ in 0..<6 where !reps.isHittable { app.swipeDown() }
        tap(reps)
        reps.typeText("10")
        let load = app.textFields["actualLoad0"]
        tap(load)
        load.typeText("25")
        if app.buttons["dismissSetKeyboard"].isHittable { tap(app.buttons["dismissSetKeyboard"]) }
        tap(app.buttons["confirmSet0"])
        XCTAssertTrue(app.buttons["undoSet0"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemPrompt = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Weekform")).firstMatch
        if systemPrompt.exists && systemPrompt.buttons["Allow"].exists { systemPrompt.buttons["Allow"].tap() }

        captureScreen("Home screen with confirmed rest")
        let elements = springboard.descendants(matching: .any)
        // Wait for the committed rest snapshot and target its timer. A preceding
        // workout's capsule may briefly remain on SpringBoard while dismissing.
        let candidates = elements.matching(NSPredicate(format: "label CONTAINS[c] %@", "Elapsed rest"))
        _ = candidates.firstMatch.waitForExistence(timeout: 8)
        let island = candidates.allElementsBoundByIndex.first { item in
            let frame = item.frame
            return item.elementType != .icon && frame.minY >= 0 && frame.maxY < 90 && frame.width > 0 && item.isHittable
        }
        if let island {
            // The timer redraw can reorder SpringBoard's AX elements while a press
            // is synthesized. Press the observed capsule location instead.
            let frame = island.frame
            let screen = springboard.frame
            springboard.coordinate(withNormalizedOffset: CGVector(dx: frame.midX / screen.width, dy: frame.midY / screen.height))
                .press(forDuration: 1.2)
        } else {
            let hierarchy = XCTAttachment(string: springboard.debugDescription)
            hierarchy.name = "SpringBoard elements"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            // On the dedicated iPhone 17 simulators the capsule is centered in
            // the top status area, even when SpringBoard exposes no AX element.
            let capsule = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.041))
            capsule.press(forDuration: 1.2)
        }
        let target = elements.matching(NSPredicate(format: "label CONTAINS %@", "Target 1:30")).firstMatch
        let targetVisible = target.waitForExistence(timeout: 8)
        captureScreen("Expanded rest activity")
        XCTAssertTrue(targetVisible, "Expanded activity should show this interval’s 1:30 target.")
    }

    @MainActor
    private func audit(_ appearance: XCUIDevice.Appearance, detail: Bool, searchCurl: Bool = false) throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        device.appearance = appearance

        let app = XCUIApplication()
        app.launchEnvironment["WEEKFORM_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["WEEKFORM_UI_TEST_APPEARANCE"] = appearance == .dark ? "dark" : "light"
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()

        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)")
            element.tap()
        }
        tap(app.buttons["chooseStarter"])
        tap(app.buttons["starterGeneral"])
        tap(app.buttons["reviewWeek"])
        tap(app.buttons["confirmRoutine"])
        tap(app.tabBars.buttons["Exercises"])
        tap(app.buttons["exercisesBrowseAll"])
        let row = app.buttons["catalogRow-Barbell bench press"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let defaultHeight = row.frame.height
        app.terminate()

        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityLarge.rawValue,
            "-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light"
        ]
        app.launch()
        device.appearance = appearance
        tap(app.tabBars.buttons["Exercises"])
        tap(app.buttons["exercisesBrowseAll"])
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(row.frame.height, defaultHeight, "The catalog row should grow with Dynamic Type.")
        if detail {
            tap(row)
            XCTAssertTrue(app.buttons["favoriteExercise"].waitForExistence(timeout: 5))
            let frame = app.buttons["catalogFrame1"]
            XCTAssertTrue(frame.waitForExistence(timeout: 5))
            XCTAssertEqual(frame.label, "Enlarge Barbell bench press demonstration, frame 1")
        } else if searchCurl {
            // Audit the same row that can sit beneath the system's translucent
            // tabs in the unfiltered list. The unfiltered tests remain separate.
            let searchField = app.searchFields["Search"].firstMatch
            tap(searchField)
            searchField.typeText("Barbell curl\n")
            let curl = app.buttons["catalogRow-Barbell curl"]
            for _ in 0..<5 where !curl.isHittable { app.swipeUp() }
            XCTAssertTrue(curl.waitForExistence(timeout: 5))
            XCTAssertTrue(curl.isHittable)
            XCTAssertLessThan(curl.frame.maxY, app.tabBars.firstMatch.frame.minY)
        } else {
            XCTAssertTrue(app.searchFields["Search"].firstMatch.exists)
        }

        let rendered = app.screenshot()
        // Sample the opaque page margin; simulator appearance can be reported as
        // dark while the target still renders light.
        let image = try XCTUnwrap(rendered.image.cgImage)
        let margin = try XCTUnwrap(image.cropping(to: CGRect(x: 1, y: image.height / 5, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            context?.draw(margin, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        if appearance == .dark {
            XCTAssertLessThan(pixel.prefix(3).max() ?? 255, 100, "Expected a dark rendered page margin.")
        } else {
            XCTAssertGreaterThan(pixel.prefix(3).min() ?? 0, 160, "Expected a light rendered page margin.")
        }
        let screenshot = XCTAttachment(screenshot: rendered)
        let surface = detail ? "Exercise detail" : (searchCurl ? "Barbell curl result" : "Exercise list")
        screenshot.name = "\(surface) · \(appearance == .dark ? "dark" : "light") · Accessibility Large"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        continueAfterFailure = true
        try app.performAccessibilityAudit()
    }
}
