import XCTest

/// PC1–PC3: a guessed person link is marked "Assumed"; the "Who is this?" sheet changes who a name means, with
/// Undo; "Done" with the same choice settles the guess; a person's page confirms or changes a guess. Most tests use
/// the `-uiTesting-seedGuesses` fixture; the waiting-card tests use the scripted sessions.
@MainActor
final class PeopleGuessUITests: XCTestCase {
    private let robinAssumed = "Robin Okafor, assumed, you said Robin. Change who this is."

    /// The VoiceOver label of a chip with no mark.
    private func plain(_ name: String) -> String { "\(name). Change who this is." }

    private func chips(_ app: XCUIApplication, marked: Bool) -> XCUIElementQuery {
        app.buttons.matching(identifier: marked ? "person.chip.assumed" : "person.chip")
    }

    private func chip(_ app: XCUIApplication, _ label: String, in scope: XCUIElement? = nil) -> XCUIElement {
        let buttons = scope?.buttons ?? app.buttons
        return buttons.matching(NSPredicate(format: "(identifier == 'person.chip' OR identifier == 'person.chip.assumed') AND label == %@", label)).firstMatch
    }

    /// Polls a query until it holds `count` elements: a refresh redraws the chips a moment after the sheet closes.
    private func waitCount(_ query: XCUIElementQuery, _ count: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count == count { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return query.count == count
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Taps a chip once it is on screen, then waits for the sheet.
    private func openSheet(_ app: XCUIApplication, from chip: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.scrollIntoView(chip), "the chip is on screen", file: file, line: line)
        chip.tap()
        XCTAssertTrue(app.any("who.sheet").waitForExistence(timeout: 5), "the Who is this? sheet opens", file: file, line: line)
    }

    private func tapDone(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let done = app.buttons["who.done"]
        XCTAssertTrue(revealInSheet(app, done), "Done is on screen", file: file, line: line)
        done.tap()
        XCTAssertTrue(waitGone(app.any("who.sheet"), timeout: 5), "Done closes the sheet", file: file, line: line)
    }

    /// The sheet opens at the medium detent; a swipe on it scrolls it (or raises it first).
    private func revealInSheet(_ app: XCUIApplication, _ element: XCUIElement, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists, app.waitHittable(element, timeout: 1) { return true }
            app.any("who.sheet").swipeUp()
        }
        return app.waitHittable(element, timeout: 2)
    }

    private func notice(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["person.notice"] }

    /// A moment row on a person's page, by its title. A guessed row's label also carries its "Assumed" line.
    private func momentRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "entity.moment").matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Robin Okafor's page, with all four moments in the tree (the page is a lazy List).
    private func openRobinsPage(_ app: XCUIApplication) {
        app.openEntityPage("Robin Okafor")
        XCTAssertTrue(app.reveal(momentRow(app, "The night the boiler went")), "the last moment is in the list")
    }

    // MARK: - The landing and the marks

    @MainActor
    func testTheLandingStatesTheGuesses() {
        let app = XCUIApplication.launchWithGuesses(landing: true)
        XCTAssertEqual(app.staticTexts["landing.guesses"].label, "I made 2 guesses about who you meant.",
                       "two assumed links in this session; the new person and the said name are not guesses")
    }

    @MainActor
    func testAnAssumedChipIsMarkedAndASaidOneIsNot() {
        let app = XCUIApplication.launchWithGuesses(landing: true)
        let marked = chips(app, marked: true)
        XCTAssertTrue(waitCount(marked, 2), "both of Robin's moments carry the mark")
        XCTAssertEqual(marked.allElementsBoundByIndex.map(\.label), [robinAssumed, robinAssumed])
        let danielle = chip(app, plain("Danielle"))
        XCTAssertTrue(danielle.exists, "a said name reads as the name alone")
        XCTAssertEqual(danielle.identifier, "person.chip", "a said link has no mark")
        XCTAssertEqual(chip(app, plain("Tomas")).identifier, "person.chip", "a new person is not a guess about someone on file")
        for one in marked.allElementsBoundByIndex { XCTAssertGreaterThanOrEqual(one.frame.height, 44) }
    }

    @MainActor
    func testAnOlderLinkHasNoMark() {
        let app = XCUIApplication.launchWithGuesses()
        openRobinsPage(app)
        let older = momentRow(app, "Robin's first car")
        XCTAssertTrue(app.reveal(older))
        // The contact row makes the page longer: after the reveal of the last moment, the first can sit above the
        // fold, and a tap while the list still glides only stops it. Swipe back until it is on screen and still.
        for _ in 0..<4 where !app.waitHittable(older, timeout: 1) { app.swipeDown() }
        XCTAssertTrue(app.waitHittable(older, timeout: 5), "the row is on screen and still")
        older.tap()
        // Under load the first tap after the scroll is sometimes swallowed (the page stays up): tap once more.
        if !app.buttons["memory.range"].waitForExistence(timeout: 3), older.exists { older.tap() }
        let robin = chip(app, plain("Robin Okafor"))
        XCTAssertTrue(robin.waitForExistence(timeout: 5), "the memory page shows Robin Okafor")
        XCTAssertEqual(robin.identifier, "person.chip", "a link older than the guess has no origin, so no mark")
        XCTAssertEqual(chips(app, marked: true).count, 0)
    }

    // MARK: - The sheet

    @MainActor
    func testTheSheetMovesANameAndUndoRestoresIt() {
        let app = XCUIApplication.launchWithGuesses(landing: true)
        XCTAssertTrue(waitCount(chips(app, marked: true), 2))
        openSheet(app, from: chips(app, marked: true).firstMatch)
        XCTAssertTrue(app.staticTexts["Who is \u{201C}Robin\u{201D} here?"].exists)
        app.buttons["who.new"].tap()
        XCTAssertTrue(app.buttons["who.new"].isSelected, "Someone new is the choice now")
        let group = app.buttons["who.group"]
        XCTAssertTrue(revealInSheet(app, group))
        XCTAssertEqual(group.label, "Also change the 1 other moment from this recording")
        XCTAssertTrue(group.isSelected, "the other moment changes too by default")
        tapDone(app)

        XCTAssertTrue(waitCount(app.buttons.matching(NSPredicate(format: "label == %@", plain("Robin"))), 2),
                      "both moments now show the new person, Robin, with no mark")
        XCTAssertEqual(chips(app, marked: true).count, 0)
        XCTAssertTrue(notice(app).waitForExistence(timeout: 5))
        XCTAssertEqual(notice(app).label, "Changed to Robin.")

        app.buttons["notice.undo"].tap()
        XCTAssertTrue(waitCount(chips(app, marked: true), 2), "Undo puts both moments back on Robin Okafor, still a guess")
        XCTAssertEqual(chips(app, marked: true).allElementsBoundByIndex.map(\.label), [robinAssumed, robinAssumed])
        XCTAssertFalse(chip(app, plain("Robin")).exists, "the person the move made is gone")
        XCTAssertTrue(waitGone(notice(app), timeout: 3), "the notice leaves with Undo")
    }

    @MainActor
    func testDoneWithTheSameChoiceSettlesTheGuess() {
        let app = XCUIApplication.launchWithGuesses(landing: true)
        XCTAssertTrue(waitCount(chips(app, marked: true), 2))
        openSheet(app, from: chips(app, marked: true).firstMatch)
        let current = app.buttons.matching(identifier: "who.option").firstMatch
        XCTAssertEqual(current.label, "Robin Okafor. In 4 of your stories \u{00B7} my guess", "the guess is listed first and chosen")
        XCTAssertTrue(current.isSelected)
        tapDone(app)
        XCTAssertTrue(waitCount(chips(app, marked: true), 0), "the mark is gone on this moment and, with the group on, on the other")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", plain("Robin Okafor"))).count, 2)
        XCTAssertFalse(notice(app).exists, "settling moves nothing, so there is nothing to undo")
    }

    @MainActor
    func testNotAPersonRemovesTheChip() {
        let app = XCUIApplication.launchWithGuesses(landing: true)
        XCTAssertTrue(waitCount(chips(app, marked: true), 2))
        openSheet(app, from: chips(app, marked: true).firstMatch)
        let notAPerson = app.buttons["who.notAPerson"]
        XCTAssertTrue(revealInSheet(app, notAPerson))
        notAPerson.tap()
        tapDone(app)
        XCTAssertTrue(waitCount(chips(app, marked: true), 0), "both of Robin's chips go")
        XCTAssertFalse(chip(app, plain("Robin Okafor")).exists)
        XCTAssertTrue(chip(app, plain("Danielle")).exists, "another moment's people stay")
        XCTAssertTrue(notice(app).waitForExistence(timeout: 5))
        XCTAssertEqual(notice(app).label, "Not a person.")
        XCTAssertTrue(app.buttons["notice.undo"].exists, "Not a person can be undone too")
    }

    @MainActor
    func testTheSheetAtTheLargestTextSize() {
        let app = XCUIApplication.launchWithGuesses(landing: true, ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(waitCount(chips(app, marked: true), 2))
        openSheet(app, from: chips(app, marked: true).firstMatch)
        XCTAssertGreaterThanOrEqual(app.buttons["who.new"].frame.height, 44)
        let done = app.buttons["who.done"]
        XCTAssertTrue(revealInSheet(app, done, swipes: 12), "Done is reachable after a scroll")
        XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        done.tap()
        XCTAssertTrue(waitGone(app.any("who.sheet"), timeout: 5))
    }

    // MARK: - The story's photo follows the name

    /// The first photo story's landing, with "The ferry" kept from it: Sam, assumed, said "Sammy". Keep put the photo on
    /// Sam's page. "Someone new" moves the name and the photo with it; Undo puts both back. The notice's Undo lasts six
    /// seconds, so the first move is undone at once and the card is read after; the second move is read after. A card
    /// that misses the refresh after a move or after its Undo shows the wrong chips.
    @MainActor
    func testMovingANameMovesThePhoto() {
        let app = XCUIApplication.launchWithPhotoStory(opening: "first", ["-uiTesting-photoStoryAssumedName"])
        let page = { (title: String) in
            app.buttons.matching(identifier: "photoCard.page").matching(NSPredicate(format: "label == %@", title)).firstMatch
        }
        XCTAssertTrue(page("Sam").waitForExistence(timeout: 10), "the card lists Sam")
        XCTAssertEqual(page("Sam").value as? String, "added by this story", "Keep followed the guess")
        let sam = chip(app, "Sam, assumed, you said Sammy. Change who this is.")

        openSheet(app, from: sam)
        app.buttons["who.new"].tap()
        tapDone(app)
        XCTAssertTrue(notice(app).waitForExistence(timeout: 5))
        XCTAssertEqual(notice(app).label, "Changed to Sammy.")
        let undo = app.buttons["notice.undo"]
        XCTAssertTrue(app.waitHittable(undo, timeout: 3), "Undo is on screen")
        undo.tap()
        XCTAssertTrue(waitGone(notice(app), timeout: 3), "the notice leaves with Undo")
        XCTAssertTrue(waitGone(page("Sammy"), timeout: 5), "the new person is gone from the card")
        XCTAssertTrue(page("Sam").waitForExistence(timeout: 5))
        XCTAssertEqual(page("Sam").value as? String, "added by this story", "Undo put the photo back on Sam's page")

        openSheet(app, from: sam)
        app.buttons["who.new"].tap()
        tapDone(app)
        XCTAssertTrue(page("Sammy").waitForExistence(timeout: 5), "the card lists the new person")
        XCTAssertEqual(page("Sammy").value as? String, "added by this story", "the photo moved with the name")
        XCTAssertTrue(!page("Sam").exists || page("Sam").value as? String == "not added", "the photo left Sam's page")
    }

    // MARK: - A person's page

    @MainActor
    func testYesThisRobinClearsOneMark() {
        let app = XCUIApplication.launchWithGuesses()
        openRobinsPage(app)
        let guessed = app.descendants(matching: .any).matching(identifier: "entity.moment.assumed")
        XCTAssertEqual(guessed.count, 2, "both guessed moments are outlined cards")
        let confirm = app.buttons["entity.moment.confirm"].firstMatch
        XCTAssertEqual(confirm.label, "Yes, this Robin")
        XCTAssertTrue(app.scrollIntoView(confirm))
        confirm.tap()
        XCTAssertTrue(waitCount(guessed, 1), "only the confirmed moment loses its mark")
        XCTAssertEqual(app.buttons.matching(identifier: "entity.moment").count, 4, "the moment stays on Robin's page")
    }

    @MainActor
    func testSomeoneElseFromThePageRemovesTheMoment() {
        let app = XCUIApplication.launchWithGuesses()
        openRobinsPage(app)
        XCTAssertEqual(app.buttons.matching(identifier: "entity.moment").count, 4)
        let someoneElse = app.buttons["entity.moment.someoneElse"].firstMatch
        XCTAssertEqual(someoneElse.label, "Someone else\u{2026}")
        openSheet(app, from: someoneElse)
        let group = app.buttons["who.group"]
        XCTAssertTrue(revealInSheet(app, group))
        group.tap()
        XCTAssertFalse(group.isSelected, "only this moment changes")
        app.buttons["who.new"].tap()
        tapDone(app)
        XCTAssertTrue(waitCount(app.buttons.matching(identifier: "entity.moment"), 3), "the moved moment leaves Robin's page")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "entity.moment.assumed").count, 1, "the other guess stays")
        XCTAssertTrue(notice(app).waitForExistence(timeout: 5))
        XCTAssertEqual(notice(app).label, "Changed to Robin.")
        // The page is a lazy List and the contact row (PC-b) makes it longer: the title is out of the tree until it
        // scrolls back into view.
        let title = app.staticTexts["entity.title"]
        for _ in 0..<6 where !title.exists { app.swipeDown() }
        XCTAssertEqual(title.label, "Robin Okafor", "the page stays on Robin Okafor")
    }

    /// R34: the move empties Priya, whom the guess made, so it removes her. Her page stays up with the notice and
    /// Undo; Undo brings her and her moment back, and the page carries on.
    @MainActor
    func testAMoveThatRemovesAGuessedPersonKeepsThePageForUndo() {
        let app = XCUIApplication.launchWithGuesses()
        moveTheOnlyMomentOfPriyaToDanielle(app)
        XCTAssertEqual(app.staticTexts["entity.title"].label, "Priya", "the page stays while Undo is offered")
        let undo = app.buttons["notice.undo"]
        XCTAssertTrue(app.waitHittable(undo, timeout: 5), "Undo is offered on the page")
        undo.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "entity.moment.assumed").firstMatch.waitForExistence(timeout: 5),
                      "Undo brings the moment back, still a guess")
        XCTAssertTrue(waitGone(notice(app), timeout: 3))
        // Past the notice's six seconds: a page whose person came back does not close.
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        XCTAssertTrue(app.staticTexts["entity.title"].exists, "the page carries on after Undo")
        XCTAssertEqual(app.staticTexts["entity.title"].label, "Priya")
    }

    /// R34: with no Undo, the held page closes when the notice ends, and Priya is no longer in People.
    @MainActor
    func testWithoutUndoTheEmptiedPageClosesWhenTheNoticeEnds() {
        let app = XCUIApplication.launchWithGuesses()
        moveTheOnlyMomentOfPriyaToDanielle(app)
        XCTAssertTrue(app.staticTexts["entity.title"].exists, "the page is held while the notice is up")
        XCTAssertTrue(waitGone(app.staticTexts["entity.title"], timeout: 12), "the page closes when the notice ends")
        XCTAssertTrue(app.buttons.matching(identifier: "entities.row").firstMatch.waitForExistence(timeout: 5), "back on People")
        XCTAssertFalse(app.entityRowLabels().contains("Priya"), "the empty guess is gone: \(app.entityRowLabels())")
        XCTAssertTrue(app.entityRowLabels().contains("Danielle"))
    }

    /// Priya's page, "Someone else…", then Danielle from behind "Someone else" in the sheet. Checks that
    /// `who.else` is the disclosure toggle and that it lists the other people on file.
    private func moveTheOnlyMomentOfPriyaToDanielle(_ app: XCUIApplication) {
        app.openEntityPage("Priya")
        let someoneElse = app.buttons["entity.moment.someoneElse"]
        XCTAssertTrue(app.reveal(someoneElse))
        openSheet(app, from: someoneElse)
        let options = app.buttons.matching(identifier: "who.option")
        XCTAssertEqual(options.allElementsBoundByIndex.map(\.label), ["Priya. In 1 of your stories \u{00B7} my guess"],
                       "the others wait behind Someone else")
        let others = app.any("who.else")
        XCTAssertTrue(revealInSheet(app, others))
        others.tap()
        XCTAssertTrue(waitCount(options, 4), "Someone else lists the other people on file")
        XCTAssertEqual(Array(options.allElementsBoundByIndex.map(\.label).dropFirst()),
                       ["Danielle. In 1 of your stories", "Robin Okafor. In 4 of your stories", "Tomas. In 1 of your stories"],
                       "by name; never the owner")
        let danielle = options.matching(NSPredicate(format: "label BEGINSWITH %@", "Danielle.")).firstMatch
        XCTAssertTrue(revealInSheet(app, danielle))
        danielle.tap()
        tapDone(app)
        XCTAssertTrue(notice(app).waitForExistence(timeout: 5))
        XCTAssertEqual(notice(app).label, "Changed to Danielle.")
    }

    // MARK: - Cards in a live session

    /// A card that waits shows what Keep will link, from a preview. Choosing someone else there shows them with
    /// no mark, and Keep links that person. The invented family is on file; the follow-up script names Dara.
    @MainActor
    func testAChoiceOnAWaitingCardIsWhatKeepLinks() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-followUps"])
        app.startSession()
        let card = app.any("card.memory")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the memory card arrives")
        let dara = chip(app, plain("Dara"), in: card)
        XCTAssertTrue(dara.waitForExistence(timeout: 5), "the card shows the person Keep would make for Dara")
        openSheet(app, from: dara)
        XCTAssertTrue(app.staticTexts["Who is \u{201C}Dara\u{201D} here?"].exists)
        let others = app.any("who.else")
        XCTAssertTrue(revealInSheet(app, others))
        others.tap()
        XCTAssertTrue(waitCount(app.buttons.matching(identifier: "who.option"), 4), "every person on file but the owner")
        XCTAssertEqual(app.buttons.matching(identifier: "who.option").allElementsBoundByIndex.map(\.label),
                       ["Dad. In 3 of your stories", "Lena. Not in a story yet", "Maya. In 4 of your stories", "Sam. In 1 of your stories"])
        let sam = app.buttons.matching(identifier: "who.option").matching(NSPredicate(format: "label BEGINSWITH %@", "Sam.")).firstMatch
        XCTAssertTrue(revealInSheet(app, sam), "Someone else lists Sam")
        sam.tap()
        tapDone(app)
        let samChip = chip(app, plain("Sam"), in: card)
        XCTAssertTrue(samChip.waitForExistence(timeout: 5), "the card shows the chosen person")
        XCTAssertEqual(samChip.identifier, "person.chip", "the owner's choice has no mark")
        XCTAssertFalse(chip(app, plain("Dara"), in: card).exists)

        card.buttons["card.add"].firstMatch.tap()
        let kept = app.any("card.kept")
        XCTAssertTrue(kept.waitForExistence(timeout: 5), "Keep turns the card into a kept card")
        let keptSam = chip(app, plain("Sam"), in: kept)
        XCTAssertTrue(keptSam.waitForExistence(timeout: 5), "Keep linked the person chosen on the card")
        XCTAssertEqual(keptSam.identifier, "person.chip")
        XCTAssertEqual(kept.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.chip'")).count, 1)
    }

    /// R37: "Not a person" on a waiting card leaves a quiet chip with the said name. A tap opens the sheet on that
    /// answer, and "Someone new" there makes the name a person again.
    @MainActor
    func testNotAPersonOnAWaitingCardHasAWayBack() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-followUps"])
        app.startSession()
        let card = app.any("card.memory")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the memory card arrives")
        let dara = chip(app, plain("Dara"), in: card)
        XCTAssertTrue(dara.waitForExistence(timeout: 5))
        openSheet(app, from: dara)
        let notAPerson = app.buttons["who.notAPerson"]
        XCTAssertTrue(revealInSheet(app, notAPerson))
        notAPerson.tap()
        tapDone(app)

        let quiet = card.buttons["person.chip.notPerson"]
        XCTAssertTrue(quiet.waitForExistence(timeout: 5), "the name keeps a quiet chip")
        XCTAssertEqual(quiet.label, "Dara, not a person. Change who this is.")
        XCTAssertFalse(chip(app, plain("Dara"), in: card).exists)
        openSheet(app, from: quiet)
        XCTAssertTrue(revealInSheet(app, notAPerson))
        XCTAssertTrue(notAPerson.isSelected, "the sheet opens on the answer the owner gave")
        let someoneNew = app.buttons["who.new"]
        XCTAssertTrue(revealInSheet(app, someoneNew))
        someoneNew.tap()
        tapDone(app)
        XCTAssertTrue(chip(app, plain("Dara"), in: card).waitForExistence(timeout: 5), "Dara is a person again")
        XCTAssertFalse(card.buttons["person.chip.notPerson"].exists)
    }

    /// PC-d: one line names "Robyn from work" and "my cousin Robyn". The extractor gives them two handles, so the card
    /// shows two chips "Robyn"; the sheet of one chip changes that person only; Keep makes two people named Robyn.
    @MainActor
    func testTwoPeopleWithOneNameGetTwoChips() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-twoRobyns"]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        let card = app.any("card.memory")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the memory card arrives")
        let robyns = card.buttons.matching(NSPredicate(format: "label == %@", plain("Robyn")))
        XCTAssertTrue(waitCount(robyns, 2), "one chip for each Robyn")

        openSheet(app, from: robyns.element(boundBy: 0))
        XCTAssertTrue(app.staticTexts["Who is \u{201C}Robyn\u{201D} here?"].exists)
        let notAPerson = app.buttons["who.notAPerson"]
        XCTAssertTrue(revealInSheet(app, notAPerson))
        notAPerson.tap()
        tapDone(app)
        let quiet = card.buttons["person.chip.notPerson"]
        XCTAssertTrue(quiet.waitForExistence(timeout: 5), "the changed Robyn has a quiet chip")
        XCTAssertTrue(waitCount(robyns, 1), "the other Robyn keeps her chip: the sheet changed one person only")
        openSheet(app, from: quiet)
        let someoneNew = app.buttons["who.new"]
        XCTAssertTrue(revealInSheet(app, someoneNew))
        someoneNew.tap()
        tapDone(app)
        XCTAssertTrue(waitCount(robyns, 2), "both Robyns are people again")

        card.buttons["card.add"].firstMatch.tap()
        let kept = app.any("card.kept")
        XCTAssertTrue(kept.waitForExistence(timeout: 5), "Keep turns the card into a kept card")
        XCTAssertTrue(waitCount(kept.buttons.matching(NSPredicate(format: "label == %@", plain("Robyn"))), 2), "the kept card names both")
        app.finishSession()
        app.openTab("People")
        let tiles = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "Robyn"))
        XCTAssertTrue(waitCount(tiles, 2, timeout: 10), "two people named Robyn: \(app.entityRowLabels())")
    }

    /// Regression (task 7): "Change…" keeps the memory and edits its people in its own sheet; the kept card it
    /// leaves must show those people, not the ones read before the sheet opened.
    @MainActor
    func testTheKeptCardShowsPeopleChangedInChange() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-followUps"]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        let change = app.buttons["card.change"].firstMatch
        XCTAssertTrue(change.waitForExistence(timeout: 20), "the memory card arrives")
        change.tap()
        let remove = app.buttons["change.removePerson"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "Change lists Dara, whom Keep linked")
        remove.tap()
        XCTAssertTrue(waitGone(remove, timeout: 5))
        let name = app.textFields["change.personName"]
        name.tap()
        name.typeText("Ines")
        app.buttons["change.addName"].tap()
        XCTAssertTrue(app.buttons["change.removePerson"].waitForExistence(timeout: 5), "Ines is on the memory")
        app.buttons["change.done"].tap()

        let kept = app.any("card.kept")
        XCTAssertTrue(kept.waitForExistence(timeout: 5))
        XCTAssertTrue(chip(app, plain("Ines"), in: kept).waitForExistence(timeout: 5), "the added person shows on the kept card")
        XCTAssertFalse(chip(app, plain("Dara"), in: kept).exists, "the removed person is gone from it")
    }
}
