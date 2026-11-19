import XCTest

/// Follow-ups are chips on the kept memory card: one memory with a domain hint, a thing, a person and a
/// group phrase, all referring to it (the `-uiTesting-followUps` fixture). Keep links the thing and the
/// person (Dara shows as a person chip); the domain and the group ("our parents") stay follow-ups.
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

    /// Dara as Keep linked them: a new person, so a chip with no mark.
    private func daraChip(_ app: XCUIApplication) -> XCUIElement {
        app.any("card.kept").buttons.matching(identifier: "person.chip").matching(NSPredicate(format: "label == %@", "Dara. Change who this is.")).firstMatch
    }

    @MainActor
    func testKeepShowsChipsOnTheSameCard() {
        let app = keepTheMemory()
        XCTAssertTrue(app.staticTexts["Mending the garden gate"].exists, "the kept card holds the memory's title")
        XCTAssertEqual(app.buttons.matching(identifier: "card.followUp").count, 2,
                       "a domain and a group; the gate the memory is about and Dara, whom it names, are linked, not asked")
        XCTAssertTrue(chip(app, "Family?").exists)
        XCTAssertTrue(chip(app, "our parents: who's this?").exists, "a group phrase keeps its question")
        XCTAssertTrue(daraChip(app).exists, "Dara shows as a person on the same card")
        XCTAssertFalse(chip(app, "Dara: who's this?").exists, "a name the memory carries is not asked")
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
        app.openNamesQueue()
        let who = app.any("card.whoIsThis")
        XCTAssertTrue(who.waitForExistence(timeout: 5), "an open mention waits in the People queue")
        XCTAssertTrue(who.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "our parents")).firstMatch.exists,
                      "the unanswered name is the group phrase")
    }

    @MainActor
    func testUndoAfterDoneBringsTheChipsBack() {
        let app = keepTheMemory()
        app.buttons["card.keptDone"].tap()
        // Done let the domain suggestion go; the notice says so and offers Undo.
        let notice = app.staticTexts["card.keptClosedNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "closing with an unanswered suggestion shows a notice")
        XCTAssertEqual(notice.label, "1 suggestion dismissed.")
        XCTAssertFalse(app.any("card.kept").exists)
        app.buttons["card.undoKeptClose"].tap()
        XCTAssertTrue(app.any("card.kept").waitForExistence(timeout: 5), "Undo brings the kept card back")
        XCTAssertTrue(chip(app, "Family?").exists, "the suggestion is open again")
        XCTAssertTrue(chip(app, "our parents: who's this?").exists)
        XCTAssertTrue(daraChip(app).exists, "the person chip comes back with the card")
        XCTAssertFalse(notice.exists, "the notice leaves with Undo")
        // The suggestion is pending again, not dismissed: it can be answered.
        chip(app, "Family?").tap()
        XCTAssertTrue(chip(app, "Family, done").waitForExistence(timeout: 5))
    }

    @MainActor
    func testDoneWithEverySuggestionAnsweredShowsNoNotice() {
        let app = keepTheMemory()
        chip(app, "Family?").tap()
        XCTAssertTrue(chip(app, "Family, done").waitForExistence(timeout: 5))
        app.buttons["card.keptDone"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.any("card.kept"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["card.keptClosedNotice"].exists, "only a name was left; nothing was dismissed, so nothing to undo")
    }

    /// The person chip opens the "Who is this?" sheet. Done with the person Keep made settles the link:
    /// the relation said with the name ("my cousin") becomes theirs, as an answer did before.
    @MainActor
    func testPersonChipOpensWhoIsThis() {
        let app = keepTheMemory()
        daraChip(app).tap()
        XCTAssertTrue(app.any("who.sheet").waitForExistence(timeout: 5), "the Who is this? choices open in a sheet")
        XCTAssertTrue(app.staticTexts["Who is \u{201C}Dara\u{201D} here?"].exists)
        let done = app.buttons["who.done"]
        if !app.waitHittable(done, timeout: 2) { app.any("who.sheet").swipeUp() }
        XCTAssertTrue(app.waitHittable(done, timeout: 5), "Done is on screen")
        done.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.any("who.sheet"))
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "Done closes the sheet")
        XCTAssertTrue(daraChip(app).exists, "Dara stays on the card")
        XCTAssertTrue(app.any("card.kept").exists, "the card stays while the domain chip is open")
        app.finishSession()
        app.openNamesQueue()
        let person = app.buttons.matching(identifier: "people.row").matching(NSPredicate(format: "label CONTAINS %@", "Dara")).firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        XCTAssertTrue(person.label.contains("my cousin"), "settling saved the relation said with the name: \(person.label)")
    }
}
