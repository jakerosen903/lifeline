import XCTest

/// M4.1: "Same as X?" on a retold card, Same story and its undo, Tell me when, merging from the
/// Change sheet, and the shelf row's inline actions. Scripted voice and extraction.
final class SameStoryUITests: XCTestCase {
    @MainActor
    private func launchToTimeline() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.skipFirstOpen()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        return app
    }

    /// Records one scripted session and keeps the first `keep` memory cards.
    @MainActor
    private func record(_ app: XCUIApplication, keep: Int) {
        app.startSession()
        for _ in 0..<keep {
            let add = app.buttons["card.add"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 15), "a memory card should arrive")
            add.tap()
        }
        app.finishSession()
    }

    @MainActor
    private func memoryRows(_ app: XCUIApplication, containing text: String) -> XCUIElementQuery {
        app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", text))
    }

    @MainActor
    func testRetellingOffersSameStoryAndMergesIntoOneMemory() {
        let app = launchToTimeline()
        record(app, keep: 1)   // the blue door, first telling
        app.startSession()     // the scripted voice tells the blue door again
        let line = app.staticTexts["card.sameAs"]
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the retold card names the earlier memory")
        XCTAssertTrue(line.label.hasPrefix("Same as The blue door?"), line.label)
        app.buttons["card.sameStory"].tap()
        let notice = app.staticTexts["card.mergedNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertEqual(notice.label, "Added to The blue door.")
        app.finishSession()
        XCTAssertTrue(app.reveal(memoryRows(app, containing: "The blue door").firstMatch))
        XCTAssertEqual(memoryRows(app, containing: "The blue door").count, 1, "one memory, not two")
        memoryRows(app, containing: "The blue door").firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons["memory.play"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements.matching(identifier: "memory.span").count, 2, "both tellings are listed")
    }

    @MainActor
    func testUndoBringsTheSameStoryCardBack() {
        let app = launchToTimeline()
        record(app, keep: 1)
        app.startSession()
        XCTAssertTrue(app.buttons["card.sameStory"].waitForExistence(timeout: 15))
        app.buttons["card.sameStory"].tap()
        XCTAssertTrue(app.staticTexts["card.mergedNotice"].waitForExistence(timeout: 3))
        app.buttons["card.undo"].tap()
        XCTAssertTrue(app.buttons["card.sameStory"].waitForExistence(timeout: 3), "the card is back with its offer")
        XCTAssertFalse(app.staticTexts["card.mergedNotice"].exists)
        app.finishSession()
        XCTAssertTrue(app.reveal(memoryRows(app, containing: "The blue door").firstMatch))
        memoryRows(app, containing: "The blue door").firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons["memory.play"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements.matching(identifier: "memory.span").count, 1)
    }
}
