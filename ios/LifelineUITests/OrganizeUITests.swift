import XCTest

/// M5: "Are these the same?" pairs, a continuation arriving as one card, the story line on a
/// card with its opt-out, story rows on the timeline, and Separate this telling. Scripted voice,
/// extraction and reconciler.
final class OrganizeUITests: XCTestCase {
    @MainActor
    private func launchToTimeline(arguments: [String] = [], firstOpen: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        if firstOpen { app.skipFirstOpen() }
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        return app
    }

    /// Records one scripted session and keeps the first `keep` memory cards with Keep.
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
    private func open(_ app: XCUIApplication, row text: String) {
        let row = memoryRows(app, containing: text).firstMatch
        XCTAssertTrue(app.reveal(row), "the row \(text) is on the timeline")
        var tries = 0
        while tries < 4 && row.frame.maxY > app.buttons["home.start"].frame.minY - 8 {
            app.swipeUp(); tries += 1
        }
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)).tap()
    }

    /// Scrolls the pair card into view and clear of the floating Start button.
    @MainActor
    private func revealPair(_ app: XCUIApplication) -> XCUIElement {
        let pair = app.buttons["pair.separate"]
        if !app.reveal(pair, swipes: 8) {
            let lines = app.debugDescription.split(separator: "\n").filter { $0.contains("pair.") || $0.contains("Waiting") || $0.contains("error") }
            XCTFail("the pass asks whether the two blue doors are the same; hierarchy: \(lines.prefix(12).joined(separator: " | "))")
        }
        var tries = 0
        while tries < 4 && pair.frame.maxY > app.buttons["home.start"].frame.minY - 8 { app.swipeUp(); tries += 1 }
        return pair
    }

    /// Taps a pair button and checks the card answered; a tap that lands mid-scroll is tried again.
    @MainActor
    private func answerPair(_ app: XCUIApplication, _ identifier: String) {
        for _ in 0..<3 {
            let button = app.buttons[identifier]
            guard app.waitHittable(button, timeout: 3) else { break }
            button.tap()
            if !button.waitForExistence(timeout: 1) { return }
        }
        XCTFail("the pair card did not take the answer")
    }

    /// Finds an element that may sit above or below the visible part of the list.
    @MainActor
    private func locate(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 1.5) { return true }
        app.swipeUp()
        return element.waitForExistence(timeout: 0.5)
    }

    /// Two "The blue door" memories: the first kept, the retelling kept with Keep, not Same story.
    @MainActor
    private func keepTheBlueDoorTwice(_ app: XCUIApplication) {
        record(app, keep: 1)
        app.startSession()
        XCTAssertTrue(app.buttons["card.sameStory"].waitForExistence(timeout: 15), "the retold card offers Same story")
        app.buttons["card.add"].firstMatch.tap()
        app.finishSession()
    }

    @MainActor
    func testPairCardMergesTwoKeptMemories() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lifeline-ui-pair").path
        try? FileManager.default.removeItem(atPath: dir)
        let app = launchToTimeline(arguments: ["-uiTesting-db", dir])
        keepTheBlueDoorTwice(app)
        _ = app.buttons["pair.separate"].waitForExistence(timeout: 6)
        _ = revealPair(app)
        XCTAssertEqual(app.buttons.matching(identifier: "pair.play").count, 2)
        answerPair(app, "pair.same")
        let notice = app.staticTexts["pair.notice"]
        if !locate(notice, in: app) {
            let lines = app.debugDescription.split(separator: "\n").filter { $0.contains("notice") || $0.contains("Undo") || $0.contains("Merged") || $0.contains("Kept") || $0.contains("timeline.") }
            let error = app.staticTexts["timeline.error"]
            let shown = app.reveal(error, swipes: 10) ? error.label : "(no error shown)"
            XCTFail("no notice; error: \(shown); hierarchy: \(lines.prefix(12).joined(separator: " | "))")
        }
        XCTAssertEqual(notice.label, "Merged.")
        XCTAssertTrue(app.buttons["pair.undo"].exists)
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.reveal(memoryRows(app, containing: "The blue door").firstMatch))
        XCTAssertEqual(memoryRows(app, containing: "The blue door").count, 1, "one memory remains")
        open(app, row: "The blue door")
        XCTAssertTrue(app.buttons["memory.play"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements.matching(identifier: "memory.span").count, 2, "both tellings play")
    }

    @MainActor
    func testKeepSeparateNeverReturns() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lifeline-ui-\(UUID().uuidString)").path
        let app = launchToTimeline(arguments: ["-uiTesting-db", dir])
        keepTheBlueDoorTwice(app)
        _ = app.buttons["pair.separate"].waitForExistence(timeout: 6)
        _ = revealPair(app)
        answerPair(app, "pair.separate")
        let notice = app.staticTexts["pair.notice"]
        XCTAssertTrue(locate(notice, in: app))
        XCTAssertEqual(notice.label, "Kept separate.")
        XCTAssertFalse(app.buttons["pair.separate"].exists)
        XCTAssertTrue(app.reveal(memoryRows(app, containing: "The blue door").firstMatch))
        XCTAssertEqual(memoryRows(app, containing: "The blue door").count, 2, "both memories stay")
        app.terminate()
        let again = launchToTimeline(arguments: ["-uiTesting-db", dir], firstOpen: false)
        sleep(4)   // the launch pass has run by now
        XCTAssertFalse(again.reveal(again.buttons["pair.separate"], swipes: 6), "a declined pair never returns")
    }

    @MainActor
    func testContinuationArrivesAsOneCard() {
        let app = launchToTimeline(arguments: ["-uiTesting-slow"])
        app.startSession()
        let segments = app.staticTexts["card.segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 30), "the third scripted line carries on the Maya card")
        XCTAssertEqual(segments.label, "+ 1 segment")
        let mayaCards = app.otherElements.matching(identifier: "card.memory").containing(NSPredicate(format: "identifier == %@ AND label == %@", "card.title", "Maya climbed it"))
        XCTAssertEqual(mayaCards.count, 1, "one card, not a second one for the continuation")
        mayaCards.firstMatch.buttons["card.add"].tap()
        app.finishSession()
        open(app, row: "Maya climbed it")
        XCTAssertTrue(app.buttons["memory.play"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements.matching(identifier: "memory.span").count, 1, "one telling, told across a pause")
    }

    @MainActor
    func testStoryLineOnTheCardAndOptOut() {
        let app = launchToTimeline()
        app.startSession()
        // Both cards name the same new story; the Maya card's line names the blue door.
        let line = app.staticTexts.matching(identifier: "card.storyLine").matching(NSPredicate(format: "label CONTAINS %@", "The blue door")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the second card says which story it joins")
        XCTAssertEqual(line.label, "Part of a new story with: The blue door")
        let mayaCard = app.otherElements.matching(identifier: "card.memory").containing(NSPredicate(format: "identifier == %@ AND label == %@", "card.title", "Maya climbed it")).firstMatch
        mayaCard.buttons["card.notPartOfIt"].tap()
        XCTAssertFalse(line.exists, "the membership is gone before Keep")
        XCTAssertFalse(app.staticTexts["card.storyLine"].exists, "and the other card no longer names a story of one")
        for _ in 0..<2 {
            let add = app.buttons["card.add"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 15))
            add.tap()
        }
        app.finishSession()
        XCTAssertTrue(app.reveal(memoryRows(app, containing: "The blue door").firstMatch))
        XCTAssertTrue(app.reveal(memoryRows(app, containing: "Maya climbed it").firstMatch))
        XCTAssertEqual(memoryRows(app, containing: "The blue door").count, 1)
        XCTAssertEqual(memoryRows(app, containing: "Maya climbed it").count, 1)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "timeline.story").firstMatch.exists, "no story row: the person opted out")
    }
}
