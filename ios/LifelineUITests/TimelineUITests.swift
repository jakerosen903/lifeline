import XCTest

/// The timeline, the memory screen and the relative question, with the scripted services.
final class TimelineUITests: XCTestCase {
    @MainActor
    private func launchToTimeline() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.buttons["aboutYou.skip"].waitForExistence(timeout: 5))
        app.buttons["aboutYou.skip"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        return app
    }

    /// Records one scripted session, accepting the first `accept` memory cards, then stops.
    @MainActor
    private func record(_ app: XCUIApplication, accept: Int) {
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.buttons["session.stop"].waitForExistence(timeout: 5))
        for _ in 0..<accept {
            let add = app.buttons["card.add"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 15), "a memory card should arrive")
            add.tap()
        }
        if accept == 0 {
            XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15))
        }
        app.buttons["session.stop"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 10))
    }

    /// Lists are lazy: a row below the fold is not in the tree until it scrolls into view.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 2)
    }

    @MainActor
    func testTimelineWithOnlyUnplacedMemoriesShowsTheShelf() {
        let app = launchToTimeline()
        record(app, accept: 1)   // the blue door: an age anchor with no birthday, a before-anchor with no target
        XCTAssertTrue(reveal(app.staticTexts["timeline.shelf"], in: app), "unplaced memories sit on the shelf")
        let memory = app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "The blue door")).firstMatch
        XCTAssertTrue(reveal(memory, in: app))
        XCTAssertTrue(memory.label.contains("no date yet"), memory.label)
        XCTAssertFalse(app.otherElements["timeline.axis"].exists, "no year axis when nothing is placed")
        XCTAssertTrue(app.buttons["home.start"].exists)
    }

    @MainActor
    func testAddingABirthdayPlacesTheAgeMemory() {
        let app = launchToTimeline()
        record(app, accept: 1)
        app.buttons["home.settings"].tap()
        let toggle = app.switches["aboutYou.hasBirthday"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(app.datePickers["aboutYou.birthday"].waitForExistence(timeout: 3), "the birthday picker appears once the toggle is on")
        app.buttons["aboutYou.continue"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        let memory = app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "The blue door")).firstMatch
        XCTAssertTrue(reveal(memory, in: app))
        XCTAssertTrue(memory.label.contains("around"), "a placed guess reads as a guess: \(memory.label)")
        XCTAssertTrue(app.otherElements["timeline.axis"].exists, "a placed memory brings the year axis")
    }

    @MainActor
    func testAnsweringTheRelativeQuestionConfirmsTheRange() {
        let app = launchToTimeline()
        record(app, accept: 2)   // the blue door (before Maya climbed it) and Maya climbed it (in 1998)
        let question = app.otherElements["timeline.question"]
        XCTAssertTrue(reveal(question, in: app), "the timeline asks the one question it can")
        XCTAssertTrue(app.staticTexts["Was this the same year as Maya climbed it?"].exists)
        app.buttons["refine.choice"].firstMatch.tap()   // Yes (1998)
        app.swipeDown(); app.swipeDown()
        let blueDoor = app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "The blue door")).firstMatch
        XCTAssertTrue(reveal(blueDoor, in: app))
        XCTAssertTrue(blueDoor.label.contains("1998") && !blueDoor.label.contains("around") && !blueDoor.label.contains("sometime"), blueDoor.label)
        XCTAssertFalse(app.otherElements["timeline.question"].exists, "the answered question goes away")
    }

    @MainActor
    func testMemoryScreenPlaysAndShowsEvidence() {
        let app = launchToTimeline()
        record(app, accept: 2)
        let maya = app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "Maya climbed it")).firstMatch
        XCTAssertTrue(reveal(maya, in: app))
        // The floating Start button can sit over a row's centre; tap the row's title instead.
        maya.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons["memory.play"].waitForExistence(timeout: 5))
        app.buttons["memory.play"].tap()
        XCTAssertTrue(app.buttons["memory.range"].exists)
        XCTAssertTrue(app.staticTexts["memory.evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["memory.evidence"].label.contains("in 1998"))
        XCTAssertFalse(app.staticTexts["memory.error"].exists)
    }

    @MainActor
    func testSecondSessionOpensWithADifferentPrompt() {
        let app = launchToTimeline()
        app.buttons["home.start"].tap()
        let prompt = app.staticTexts["session.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertEqual(prompt.label, "Tell me about the house you grew up in.")
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["session.stop"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 10))

        app.buttons["home.start"].tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertNotEqual(prompt.label, "Tell me about the house you grew up in.", "the second session opens with a fresh question")
        let alternate = app.buttons["session.alternate"].firstMatch
        XCTAssertTrue(alternate.exists)
        let alternateText = alternate.label
        alternate.tap()
        XCTAssertEqual(prompt.label, alternateText, "tapping an alternate swaps it in")
        app.buttons["session.stop"].tap()
    }

    @MainActor
    func testTappingAWaitingCardDoesNotDismissIt() {
        let app = launchToTimeline()
        record(app, accept: 0)
        let title = app.staticTexts.matching(identifier: "card.title").matching(NSPredicate(format: "label == %@", "The blue door")).firstMatch
        XCTAssertTrue(reveal(title, in: app), "the unacted card waits on the timeline")
        title.tap()   // a tap on the card's body, not on a button
        XCTAssertTrue(title.waitForExistence(timeout: 2), "a tap on the card must not act on it")
        let who = app.staticTexts["Who's this?"].firstMatch
        XCTAssertTrue(reveal(who, in: app))
        who.tap()
        XCTAssertTrue(who.waitForExistence(timeout: 2), "same for a who-is-this card")
    }

    @MainActor
    func testDismissedCardsCanBeBroughtBack() {
        let app = launchToTimeline()
        app.buttons["home.start"].tap()
        let dismiss = app.buttons["card.dismiss"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 15))
        dismiss.tap()   // "Not quite" on the blue door, in the session
        app.buttons["session.stop"].tap()
        XCTAssertTrue(app.buttons["timeline.sessions"].waitForExistence(timeout: 10))
        app.buttons["timeline.sessions"].tap()
        app.buttons["home.sessionRow"].firstMatch.tap()
        let bringBack = app.buttons["detail.bringBack"].firstMatch
        XCTAssertTrue(reveal(bringBack, in: app), "a dismissed card is listed with a way back")
        bringBack.tap()
        let title = app.staticTexts.matching(identifier: "card.title").matching(NSPredicate(format: "label == %@", "The blue door")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "it waits again")
    }

    @MainActor
    func testSessionsAreOneTapAway() {
        let app = launchToTimeline()
        record(app, accept: 0)
        XCTAssertTrue(app.buttons["timeline.sessions"].waitForExistence(timeout: 5))
        app.buttons["timeline.sessions"].tap()
        XCTAssertTrue(app.buttons["home.sessionRow"].firstMatch.waitForExistence(timeout: 5))
    }
}
