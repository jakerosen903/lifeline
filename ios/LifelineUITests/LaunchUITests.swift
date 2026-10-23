import XCTest

/// Every test launches with a fresh temp database and a scripted voice session.
final class LaunchUITests: XCTestCase {
    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        return app
    }

    @MainActor
    func testFirstOpenShowsAboutYouAndSkipLeadsHome() {
        let app = launch()
        XCTAssertTrue(app.textFields["aboutYou.name"].waitForExistence(timeout: 5))
        app.buttons["aboutYou.skip"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAboutYouNameAppearsInSettings() {
        let app = launch()
        let name = app.textFields["aboutYou.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rina")
        app.buttons["aboutYou.continue"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        app.buttons["home.settings"].tap()
        let settingsName = app.textFields["aboutYou.name"]
        XCTAssertTrue(settingsName.waitForExistence(timeout: 5))
        XCTAssertEqual(settingsName.value as? String, "Rina")
    }

    @MainActor
    func testRecordStopAndPlayBackAMoment() {
        let app = launch()
        XCTAssertTrue(app.buttons["aboutYou.skip"].waitForExistence(timeout: 5))
        app.buttons["aboutYou.skip"].tap()
        app.startSession()

        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 5))
        let firstMoment = app.staticTexts["session.segment"].firstMatch
        XCTAssertTrue(firstMoment.waitForExistence(timeout: 10), "a scripted segment should appear")
        XCTAssertTrue(firstMoment.label.contains("blue door"))
        XCTAssertTrue(app.staticTexts["session.prompt"].exists, "the prompt stays on screen while the person talks")
        XCTAssertTrue(app.otherElements["session.listening"].exists, "the listening indicator stays on screen")
        app.buttons["session.finish"].tap()

        XCTAssertTrue(app.buttons["timeline.sessions"].waitForExistence(timeout: 10))
        app.buttons["timeline.sessions"].tap()
        let row = app.buttons["home.sessionRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("moments"))
        row.tap()

        let segment = app.buttons["detail.segment"].firstMatch
        for _ in 0..<6 where !segment.exists { app.swipeUp() }   // moments sit below the waiting cards
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        segment.tap()
        XCTAssertFalse(app.staticTexts["detail.error"].exists, "playback must not fail for a recorded moment")
    }
}
