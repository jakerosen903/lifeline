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

// MARK: - Your copy

extension SteadyUITests {
    /// A fixture archive copied to a path the app can read.
    private func fixtureArchive(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: SteadyUITests.self).url(forResource: name, withExtension: "lifeline"), "fixture \(name) in the UI test bundle")
        let dest = FileManager.default.temporaryDirectory.appending(path: "restore-\(UUID().uuidString).lifeline")
        try FileManager.default.copyItem(at: url, to: dest)
        return dest.path
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.waitHittable(app.buttons["home.settings"], timeout: 5))
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExportMakesAFileAndRemembersWhen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        XCTAssertTrue(app.buttons["card.add"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["card.add"].firstMatch.tap()
        app.finishSession()
        openSettings(app)
        XCTAssertTrue(app.reveal(app.buttons["settings.export"]))
        app.buttons["settings.export"].tap()
        // Under UI testing the file is kept in Documents and no share sheet opens (a test cannot drive one).
        let last = app.staticTexts["settings.lastExport"]
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(last.label.hasPrefix("Last copy:"), last.label)
    }

    @MainActor
    func testRestoreFromACopyReplacesTheTimeline() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lifeline-ui-\(UUID().uuidString)").path
        let archive = try fixtureArchive("fixture-v8")
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-db", dir, "-uiTesting-restoreFrom", archive]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        XCTAssertTrue(app.buttons["card.add"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["card.add"].firstMatch.tap()
        app.finishSession()
        openSettings(app)
        XCTAssertTrue(app.reveal(app.buttons["settings.restore"]))
        app.buttons["settings.restore"].tap()
        let summary = app.staticTexts["restore.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("1 memory") && summary.label.contains("1 recording"), summary.label)
        app.buttons["restore.confirm"].tap()
        XCTAssertTrue(app.staticTexts["restore.relaunch"].waitForExistence(timeout: 20))
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["-uiTesting", "-uiTesting-db", dir]
        again.launch()
        if again.buttons["firstOpen.context"].waitForExistence(timeout: 3) { again.skipFirstOpen() }   // the fixture has no profile row
        XCTAssertTrue(again.buttons["home.start"].waitForExistence(timeout: 10))
        let orange = again.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "The orange house")).firstMatch
        XCTAssertTrue(again.reveal(orange), "the copy's memory is on the timeline")
        XCTAssertEqual(again.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "The blue door")).count, 0, "the scripted memory is gone")
    }

    @MainActor
    func testRestoreFromAnOlderCopyMigratesAndOpens() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lifeline-ui-\(UUID().uuidString)").path
        let archive = try fixtureArchive("fixture-v7-missing-audio")
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-db", dir, "-uiTesting-restoreFrom", archive]
        app.launch()
        app.skipFirstOpen()
        openSettings(app)
        XCTAssertTrue(app.reveal(app.buttons["settings.restore"]))
        app.buttons["settings.restore"].tap()
        XCTAssertTrue(app.staticTexts["restore.summary"].waitForExistence(timeout: 10))
        app.buttons["restore.confirm"].tap()
        XCTAssertTrue(app.staticTexts["restore.relaunch"].waitForExistence(timeout: 20))
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["-uiTesting", "-uiTesting-db", dir]
        again.launch()
        if again.buttons["firstOpen.context"].waitForExistence(timeout: 3) { again.skipFirstOpen() }
        XCTAssertTrue(again.buttons["home.start"].waitForExistence(timeout: 10))
        let canal = again.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "The canal")).firstMatch
        XCTAssertTrue(again.reveal(canal), "the older copy opened and migrated")
        var tries = 0
        while tries < 4 && canal.frame.maxY > again.buttons["home.start"].frame.minY - 8 { again.swipeUp(); tries += 1 }
        canal.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)).tap()
        XCTAssertTrue(again.buttons["memory.play"].firstMatch.waitForExistence(timeout: 5))
        again.buttons["memory.play"].firstMatch.tap()
        XCTAssertTrue(again.staticTexts["memory.error"].waitForExistence(timeout: 5), "a missing recording is said, not crashed on")
    }
}
