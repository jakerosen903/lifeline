import XCTest

/// Follow-ups are chips on the kept memory card: one memory with a domain hint, a thing and a
/// person, all referring to it (the `-uiTesting-followUps` fixture).
final class FollowUpUITests: XCTestCase {
    /// Launches into the review view and taps Keep on the one memory card.
    @MainActor
    private func keepTheMemory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-followUps"]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        let add = app.buttons["card.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), "the memory card arrives")
        add.tap()
        XCTAssertTrue(app.any("card.kept").waitForExistence(timeout: 5), "Keep turns the card into a kept card")
        return app
    }

    private func chip(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(identifier: "card.followUp").matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    func testKeepShowsChipsOnTheSameCard() {
        let app = keepTheMemory()
        XCTAssertTrue(app.staticTexts["Mending the garden gate"].exists, "the kept card holds the memory's title")
        XCTAssertEqual(app.buttons.matching(identifier: "card.followUp").count, 2, "a domain and a person; the gate the memory is about is linked, not asked")
        XCTAssertTrue(chip(app, "Family?").exists)
        XCTAssertTrue(chip(app, "Dara: who's this?").exists)
        for old in ["card.hint", "card.entity", "card.hintYes", "card.entityKeep"] {
            XCTAssertFalse(app.any(old).exists, "\(old) is not a card of its own any more")
        }
        XCTAssertFalse(app.any("card.memory").exists, "the memory card became the kept card")
    }

    @MainActor
    func testDomainChipChecks() {
        let app = keepTheMemory()
        chip(app, "Family?").tap()
        XCTAssertTrue(chip(app, "Family, done").waitForExistence(timeout: 5), "a checked chip reads its text, then done")
        XCTAssertFalse(chip(app, "Family?").exists)
        XCTAssertTrue(app.any("card.kept").exists, "the card stays while other chips are open")
    }

    @MainActor
    func testCheckedChipStaysOnSession() {
        let app = keepTheMemory()
        chip(app, "Family?").tap()
        XCTAssertTrue(chip(app, "Family, done").waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(app.staticTexts["entity.title"].exists, "no page opens in the live session")
        XCTAssertTrue(app.buttons["session.finish"].exists, "still on the session screen")
        XCTAssertTrue(app.any("card.kept").exists)
        chip(app, "Family, done").tap()
        XCTAssertTrue(app.buttons["session.finish"].exists, "tapping a checked chip changes nothing in the live session")
    }

    @MainActor
    func testDoneClosesTheKeptCard() {
        let app = keepTheMemory()
        chip(app, "Family?").tap()
        app.buttons["card.keptDone"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.any("card.kept"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "Done closes the kept card")
        XCTAssertEqual(app.buttons.matching(identifier: "card.followUp").count, 0, "no chip is left on the session")
        // The name nobody answered is not lost: it waits in the People queue.
        app.finishSession()
        XCTAssertTrue(app.waitHittable(app.buttons["home.people"], timeout: 5))
        app.buttons["home.people"].tap()
        let who = app.any("card.whoIsThis")
        XCTAssertTrue(who.waitForExistence(timeout: 5), "an open mention waits in the People queue")
        XCTAssertTrue(who.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Dara")).firstMatch.exists, "the unanswered name is Dara")
    }

    @MainActor
    func testPersonChipOpensWhoIsThis() {
        let app = keepTheMemory()
        chip(app, "Dara: who's this?").tap()
        XCTAssertTrue(app.any("card.whoIsThis").waitForExistence(timeout: 5), "the Who's this? choices open in a sheet")
        let new = app.buttons["card.newPerson"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        XCTAssertTrue(chip(app, "Dara, done").waitForExistence(timeout: 5), "the answered person chip is checked")
        XCTAssertFalse(chip(app, "Dara: who's this?").exists)
        XCTAssertTrue(app.any("card.kept").exists, "the card stays while the domain chip is open")
    }
}
