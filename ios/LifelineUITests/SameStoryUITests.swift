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

    /// Opens a memory row. The floating Start button covers the bottom of the list, so the row is
    /// scrolled clear of it first and tapped near its title.
    @MainActor
    private func open(_ app: XCUIApplication, row text: String) {
        let row = memoryRows(app, containing: text).firstMatch
        XCTAssertTrue(app.reveal(row), "the row \(text) is on the timeline")
        var tries = 0
        while tries < 4 && row.frame.maxY > app.buttons["home.start"].frame.minY - 8 {
            app.swipeUp(); tries += 1
        }
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)).tap()
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
        open(app, row: "The blue door")
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
        // Dismiss another card inside the window: two notices, two undos, each its own.
        let dismiss = app.buttons["card.dismiss"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 15))
        dismiss.tap()
        XCTAssertTrue(app.staticTexts["card.dismissedNotice"].waitForExistence(timeout: 3))
        app.buttons["card.undoMerge"].tap()
        XCTAssertTrue(app.buttons["card.sameStory"].waitForExistence(timeout: 3), "the card is back with its offer")
        XCTAssertFalse(app.staticTexts["card.mergedNotice"].exists)
        XCTAssertTrue(app.staticTexts["card.dismissedNotice"].exists, "undoing the merge did not touch the dismiss")
        app.finishSession()
        open(app, row: "The blue door")
        XCTAssertTrue(app.buttons["memory.play"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements.matching(identifier: "memory.span").count, 1)
    }

    @MainActor
    func testTellMeWhenPlacesAShelfMemory() {
        let app = launchToTimeline()
        record(app, keep: 1)   // the blue door alone: no birthday, its target untold, so it sits on the shelf
        XCTAssertTrue(app.reveal(memoryRows(app, containing: "The blue door").firstMatch))
        XCTAssertTrue(memoryRows(app, containing: "The blue door").firstMatch.label.contains("no date yet"))
        open(app, row: "The blue door")
        XCTAssertTrue(app.waitHittable(app.buttons["memory.range"], timeout: 5))
        app.buttons["memory.range"].tap()
        XCTAssertTrue(app.buttons["refine.tellMeWhen"].waitForExistence(timeout: 5))
        app.buttons["refine.tellMeWhen"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5), "A year is the first shape")
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "1998")
        app.buttons["when.save"].tap()
        let range = app.buttons["memory.range"]
        XCTAssertTrue(range.waitForExistence(timeout: 5))
        XCTAssertTrue(range.label.contains("1998") && !range.label.contains("around"), range.label)
        app.navigationBars.buttons.firstMatch.tap()
        let row = memoryRows(app, containing: "1998").firstMatch
        XCTAssertTrue(app.reveal(row), "the dated memory left the shelf")
        XCTAssertTrue(app.otherElements["timeline.axis"].exists)
    }

    @MainActor
    func testChangeSheetMergesIntoAnotherMemory() {
        let app = launchToTimeline()
        record(app, keep: 2)   // the blue door and Maya climbed it, under one story row (M5)
        let story = app.buttons["timeline.story"].firstMatch
        XCTAssertTrue(app.reveal(story))
        var tries = 0
        while tries < 4 && story.frame.maxY > app.buttons["home.start"].frame.minY - 8 { app.swipeUp(); tries += 1 }
        story.tap()
        open(app, row: "Maya climbed it")
        XCTAssertTrue(app.buttons["memory.change"].waitForExistence(timeout: 5))
        app.buttons["memory.change"].tap()
        XCTAssertTrue(app.buttons["change.sameAs"].waitForExistence(timeout: 5))
        app.buttons["change.sameAs"].tap()
        let match = app.buttons.matching(identifier: "picker.match").matching(NSPredicate(format: "label CONTAINS %@", "The blue door")).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        match.tap()
        let merged = app.staticTexts["change.merged"]
        XCTAssertTrue(merged.waitForExistence(timeout: 5))
        XCTAssertTrue(merged.label.hasPrefix("Merged into “The blue door”"), merged.label)
        app.buttons["change.done"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5), "the merged memory's screen closed")
        XCTAssertFalse(app.buttons["memory.change"].exists)
        XCTAssertEqual(memoryRows(app, containing: "Maya climbed it").count, 0)
        open(app, row: "The blue door")
        XCTAssertTrue(app.buttons["memory.play"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements.matching(identifier: "memory.span").count, 2)
    }

    @MainActor
    func testShelfRowActionsAreVisible() {
        let app = launchToTimeline()
        record(app, keep: 1)   // the blue door alone has no date and sits on the shelf
        let addCollection = app.buttons["row.addCollection"].firstMatch
        XCTAssertTrue(app.reveal(addCollection), "a shelf row shows Add to a collection without the menu")
        XCTAssertTrue(app.buttons["row.addDate"].firstMatch.exists, "and Add a date")
        XCTAssertEqual(app.buttons.matching(identifier: "row.addDate").count, 1, "one shelf row, one offer")
        var tries = 0
        while tries < 4 && addCollection.frame.maxY > app.buttons["home.start"].frame.minY - 8 { app.swipeUp(); tries += 1 }
        addCollection.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Doors")
        app.buttons["Add"].firstMatch.tap()
        // The collection section sits above the shelf; the alert may have left the list scrolled down.
        app.swipeDown(); app.swipeDown()
        let title = app.staticTexts["Doors"].firstMatch
        XCTAssertTrue(app.reveal(title), "the memory now sits under a collection titled Doors")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "timeline.collection").firstMatch.exists)
    }
}
