import XCTest

/// M6: the sorting status line, sorting that starts again, Your copy, and Which part of the recording.
final class SteadyUITests: XCTestCase {
    @MainActor
    private func launchToTimeline(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        app.skipFirstOpen()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        return app
    }

    /// The status line, whatever element type carries it.
    @MainActor
    private func sortingLine(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "timeline.sorting").firstMatch
    }

    @MainActor
    func testStatusLineShowsWhileSortingAndGoes() {
        let app = launchToTimeline(arguments: ["-uiTesting-slowExtract"])
        app.startSession(review: false)
        sleep(3)   // two segments are stored; sorting them takes seconds each
        app.finishSession()
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@ AND label CONTAINS %@", "timeline.sorting", "Still sorting", "today's recording")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5), "the timeline says sorting is still going on")
        let deadline = Date().addingTimeInterval(40)
        while sortingLine(app).exists && Date() < deadline { usleep(500_000) }
        XCTAssertFalse(sortingLine(app).exists, "the line goes when the last moment lands")
        XCTAssertTrue(app.reveal(app.buttons["card.add"].firstMatch), "the sorted cards wait on the timeline")
    }

    @MainActor
    func testNoKeyLineOpensSettingsAndSavingAKeyStartsSorting() {
        let app = launchToTimeline(arguments: ["-uiTesting-noKey"])
        app.startSession(review: false)
        sleep(2)
        app.finishSession()
        let keyLine = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label == %@", "timeline.sorting", "Add a key in Settings to sort what you say")).firstMatch
        XCTAssertTrue(keyLine.waitForExistence(timeout: 8), "the timeline says a key is needed")
        XCTAssertTrue(app.waitHittable(keyLine, timeout: 3))
        keyLine.tap()
        let field = app.textFields["settings.apiKey"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the key line opens Settings")
        field.tap()
        field.typeText("sk-ant-api03-" + String(repeating: "x", count: 40))
        app.buttons["settings.apiKeySave"].tap()
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.reveal(app.buttons["card.add"].firstMatch, swipes: 8), "saving a key starts sorting; the cards arrive")
        let after = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "timeline.sorting", "Add a key")).firstMatch
        XCTAssertFalse(after.exists, "the key line is gone once sorting has a key")
    }
}
