import XCTest

/// PC-b: a person can be linked to a contact. The person's page contact row (link, change, unlink, the suggestion, no
/// access), the "Who is this?" sheet's contact rows and search, the chip line for a person Keep made from a contact,
/// and the prompt on the landing. The scripted contacts are invented (`UITestSeed.contactCards`): "Robyn Vale" (with
/// a picture), "Tomas Reyes", "Robyn Okafor" (goes by "Robin") and "Dara Quinn".
@MainActor
final class PeopleContactsUITests: XCTestCase {
    private let robinAssumed = "Robin Okafor, assumed, you said Robin. Change who this is."
    private let daraFromContacts = "Dara Quinn, assumed, new, from your contacts. Change who this is."

    // MARK: - Helpers

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func waitCount(_ query: XCUIElementQuery, _ count: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count == count { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return query.count == count
    }

    /// The contact row's text that starts with `heading` (the heading and its line read as one element).
    private func rowText(_ app: XCUIApplication, _ heading: String) -> XCUIElement {
        app.any("entity.contact.row").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", heading)).firstMatch
    }

    /// Any element on screen whose label contains `text`.
    private func text(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func chip(_ app: XCUIApplication, _ label: String, in scope: XCUIElement? = nil) -> XCUIElement {
        let buttons = scope?.buttons ?? app.buttons
        return buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.chip' AND label == %@", label)).firstMatch
    }

    private func chips(_ app: XCUIApplication, _ label: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.chip' AND label == %@", label))
    }

    private func revealInSheet(_ app: XCUIApplication, _ element: XCUIElement, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists, app.waitHittable(element, timeout: 1) { return true }
            app.any("who.sheet").swipeUp()
        }
        return app.waitHittable(element, timeout: 2)
    }

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

    /// The person's page's contact row, once its state is read.
    private func openPage(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        app.openEntityPage(name)
        XCTAssertTrue(app.any("entity.contact.row").waitForExistence(timeout: 10), "\(name)'s page has a contact row", file: file, line: line)
    }

    /// "Link to a contact", then the search sheet with `query` typed in it.
    private func searchFromThePage(_ app: XCUIApplication, _ query: String, file: StaticString = #filePath, line: UInt = #line) {
        let link = app.buttons["entity.contact.link"]
        XCTAssertTrue(app.waitHittable(link, timeout: 10), "Link to a contact is on screen", file: file, line: line)
        link.tap()
        type(app, query, file: file, line: line)
    }

    private func type(_ app: XCUIApplication, _ query: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["contacts.search"]
        XCTAssertTrue(app.waitHittable(field, timeout: 10), "the contacts search field is on screen", file: file, line: line)
        field.tap()
        field.typeText(query)
    }

    private func result(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(identifier: "contacts.result").matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Maya (no contact, no photo) linked to "Robyn Vale" from her page.
    private func linkMayaToRobynVale(_ app: XCUIApplication) {
        openPage(app, "Maya")
        XCTAssertTrue(rowText(app, "Not linked to a contact").exists, "Maya starts with no contact")
        XCTAssertFalse(app.buttons["photo.header"].exists, "Maya has no picture yet")
        searchFromThePage(app, "rob")
        let results = app.buttons.matching(identifier: "contacts.result")
        XCTAssertTrue(waitCount(results, 2), "\"rob\" finds the two Robyns")
        XCTAssertEqual(results.allElementsBoundByIndex.map(\.label), ["Robyn Okafor", "Robyn Vale"], "by full name")
        result(app, "Robyn Vale").tap()
        XCTAssertTrue(rowText(app, "Linked to Robyn Vale in your contacts").waitForExistence(timeout: 10), "the row names the contact")
    }

    // MARK: - A person's page (full access)

    /// 1 and 11: link from the page; the contact's picture becomes the page's picture, with its caption.
    func testLinkFromThePageShowsTheContactAndItsPicture() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-contacts", "full"])
        linkMayaToRobynVale(app)
        XCTAssertTrue(rowText(app, "Linked to Robyn Vale in your contacts").label.contains("The app reads the name and picture only."))
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10), "the page shows the contact's picture")
        XCTAssertTrue(app.staticTexts["picture from your contacts"].waitForExistence(timeout: 5), "the copy is captioned")
        XCTAssertEqual(app.staticTexts["entity.title"].label, "Maya", "the person keeps the name the owner gave")
    }

    /// 2 and 11: "Change", "Unlink": the link goes, the picture stays as an ordinary picture.
    func testUnlinkKeepsThePicture() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-contacts", "full"])
        linkMayaToRobynVale(app)
        XCTAssertTrue(app.staticTexts["picture from your contacts"].waitForExistence(timeout: 10))
        let change = app.buttons["entity.contact.change"]
        XCTAssertTrue(app.waitHittable(change, timeout: 5))
        XCTAssertEqual(change.label, "Change")
        change.tap()
        let unlink = app.buttons["entity.contact.unlink"]
        XCTAssertTrue(unlink.waitForExistence(timeout: 5), "the menu offers Unlink")
        XCTAssertTrue(app.buttons["Link to another contact"].exists, "the menu offers another contact")
        unlink.tap()
        XCTAssertTrue(rowText(app, "Not linked to a contact").waitForExistence(timeout: 5), "the row is back to not linked")
        XCTAssertTrue(app.buttons["photo.header"].exists, "the picture stays")
        XCTAssertTrue(waitGone(app.staticTexts["picture from your contacts"], timeout: 5), "it is no longer the contact's copy")
    }

    /// 3: "No, someone else" removes the suggestion, and it stays gone.
    func testNoSomeoneElseRemovesTheSuggestionForGood() {
        let app = XCUIApplication.launchWithGuesses(["-uiTesting-contacts", "full"])
        openPage(app, "Tomas")
        let card = app.any("entity.contact.suggestion")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Tomas fits one contact")
        XCTAssertTrue(card.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Tomas Reyes is in your contacts")).firstMatch.exists)
        let no = app.buttons["entity.contact.suggestion.no"]
        XCTAssertTrue(app.scrollIntoView(no))
        XCTAssertEqual(no.label, "No, someone else")
        no.tap()
        XCTAssertTrue(waitGone(card, timeout: 5), "the suggestion goes")
        XCTAssertTrue(rowText(app, "Not linked to a contact").exists, "nothing was linked")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        openPage(app, "Tomas")
        XCTAssertTrue(rowText(app, "Not linked to a contact").exists)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(app.any("entity.contact.suggestion").exists, "the declined contact is not offered again")
    }

    /// 4: "Yes, link them" links.
    func testYesLinkThemLinks() {
        let app = XCUIApplication.launchWithGuesses(["-uiTesting-contacts", "full"])
        linkTomasFromTheSuggestion(app)
        XCTAssertEqual(app.staticTexts["entity.title"].label, "Tomas", "the said name stays")
    }

    private func linkTomasFromTheSuggestion(_ app: XCUIApplication) {
        openPage(app, "Tomas")
        let yes = app.buttons["entity.contact.suggestion.yes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 10), "the suggestion shows")
        XCTAssertTrue(app.scrollIntoView(yes))
        XCTAssertEqual(yes.label, "Yes, link them")
        yes.tap()
        XCTAssertTrue(rowText(app, "Linked to Tomas Reyes in your contacts").waitForExistence(timeout: 10), "Tomas is linked")
        XCTAssertTrue(waitGone(app.any("entity.contact.suggestion"), timeout: 5), "the suggestion goes")
    }

    /// 7: one contact belongs to one person; the refusal names who holds it, and nothing changes.
    func testAContactAnotherPersonHoldsIsRefused() {
        let app = XCUIApplication.launchWithGuesses(["-uiTesting-contacts", "full"])
        linkTomasFromTheSuggestion(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openPage(app, "Danielle")
        searchFromThePage(app, "tom")
        let held = result(app, "Tomas Reyes. In a story as Tomas")
        XCTAssertTrue(held.waitForExistence(timeout: 5), "the search says who holds the contact")
        held.tap()
        XCTAssertTrue(text(app, containing: "Tomas is already linked to this contact.").waitForExistence(timeout: 10), "the refusal sentence shows")
        XCTAssertTrue(rowText(app, "Not linked to a contact").exists, "Danielle is still not linked")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        openPage(app, "Tomas")
        XCTAssertTrue(rowText(app, "Linked to Tomas Reyes in your contacts").exists, "Tomas keeps the contact")
    }

    // MARK: - The sheet and the chips (full access)

    /// 5: a contact that fits the guessed "Robin" is a row; choosing it moves the name, and Undo restores the guess.
    func testTheSheetListsAFittingContact() {
        let app = XCUIApplication.launchWithGuesses(landing: true, ["-uiTesting-contacts", "full"])
        let marked = app.buttons.matching(identifier: "person.chip.assumed")
        XCTAssertTrue(waitCount(marked, 2))
        openSheet(app, from: marked.firstMatch)
        let contact = app.buttons.matching(identifier: "who.contact")
        XCTAssertTrue(waitCount(contact, 1), "one contact fits \"Robin\"")
        XCTAssertEqual(contact.firstMatch.label, "Robyn Okafor. In your contacts \u{00B7} not in a story yet")
        XCTAssertTrue(revealInSheet(app, contact.firstMatch))
        contact.firstMatch.tap()
        XCTAssertTrue(contact.firstMatch.isSelected)
        tapDone(app)
        moveNoticeAndUndo(app, "Changed to Robyn Okafor.")
    }

    /// 12: "Search your contacts" in the sheet: the pick is the selected row; Done moves; Undo restores.
    func testTheSheetsSearchPicksAContact() {
        let app = XCUIApplication.launchWithGuesses(landing: true, ["-uiTesting-contacts", "full"])
        let marked = app.buttons.matching(identifier: "person.chip.assumed")
        XCTAssertTrue(waitCount(marked, 2))
        openSheet(app, from: marked.firstMatch)
        let search = app.buttons["who.search"]
        XCTAssertTrue(revealInSheet(app, search))
        XCTAssertEqual(search.label, "Search your contacts")
        search.tap()
        type(app, "vale")
        let vale = result(app, "Robyn Vale")
        XCTAssertTrue(vale.waitForExistence(timeout: 5))
        vale.tap()
        let picked = app.buttons.matching(identifier: "who.contact").matching(NSPredicate(format: "label BEGINSWITH %@", "Robyn Vale.")).firstMatch
        XCTAssertTrue(picked.waitForExistence(timeout: 5), "the picked contact is a row of the sheet")
        XCTAssertTrue(picked.isSelected, "and it is the choice")
        tapDone(app)
        moveNoticeAndUndo(app, "Changed to Robyn Vale.")
    }

    private func moveNoticeAndUndo(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let notice = app.staticTexts["person.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(notice.label, text, file: file, line: line)
        XCTAssertTrue(waitCount(app.buttons.matching(identifier: "person.chip.assumed"), 0), "both moments moved", file: file, line: line)
        app.buttons["notice.undo"].tap()
        XCTAssertTrue(waitCount(chips(app, robinAssumed), 2), "Undo puts both moments back on Robin Okafor, still a guess", file: file, line: line)
        XCTAssertTrue(waitGone(notice, timeout: 3), file: file, line: line)
    }

    /// 6: Keep makes a person from the one contact that fits a new name, and the chip says so.
    func testAKeptNewNameThatFitsOneContactIsFromYourContacts() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-followUps", "-uiTesting-contacts", "full"])
        app.startSession()
        let card = app.any("card.memory")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the memory card arrives")
        card.buttons["card.add"].firstMatch.tap()
        let kept = app.any("card.kept")
        XCTAssertTrue(kept.waitForExistence(timeout: 5))
        let dara = chip(app, daraFromContacts, in: kept)
        XCTAssertTrue(dara.waitForExistence(timeout: 5), "the chip reads \"Assumed \u{00B7} new, from your contacts\"")
        XCTAssertEqual(dara.identifier, "person.chip.assumed", "a person made from a contact is a guess")
        // I-2: the contact's picture is copied after Keep, not at the next launch.
        app.buttons["session.finish"].tap()
        let done = app.buttons["landing.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "the landing appears")
        done.tap()
        openPage(app, "Dara Quinn")
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10), "the page shows the contact's picture")
        XCTAssertTrue(app.staticTexts["picture from your contacts"].waitForExistence(timeout: 5), "the copy is captioned")
    }

    /// I-1: the sheet opened on a waiting card's "new, from your contacts" chip opens on that contact. "Done" with
    /// nothing changed keeps it: Keep makes the person from the contact, now the owner's answer, with no mark.
    func testTheSheetOnAContactGuessOpensOnThatContact() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-followUps", "-uiTesting-contacts", "full"])
        app.startSession()
        let card = app.any("card.memory")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the memory card arrives")
        let dara = chip(app, daraFromContacts, in: card)
        XCTAssertTrue(dara.waitForExistence(timeout: 5), "the waiting card shows the person Keep would make from the contact")
        openSheet(app, from: dara)
        let contact = app.buttons.matching(identifier: "who.contact")
        XCTAssertTrue(waitCount(contact, 1), "the contact is listed once")
        XCTAssertEqual(contact.firstMatch.label, "Dara Quinn. In your contacts \u{00B7} my guess")
        XCTAssertTrue(contact.firstMatch.isSelected, "the app's guess is the selected choice")
        XCTAssertFalse(app.buttons["who.new"].isSelected, "not Someone new")
        tapDone(app)
        let chosen = chip(app, "Dara Quinn. Change who this is.", in: card)
        XCTAssertTrue(chosen.waitForExistence(timeout: 5), "the card still shows Dara Quinn, now with no mark")
        XCTAssertEqual(chosen.identifier, "person.chip")

        card.buttons["card.add"].firstMatch.tap()
        let kept = app.any("card.kept")
        XCTAssertTrue(kept.waitForExistence(timeout: 5))
        let keptDara = chip(app, "Dara Quinn. Change who this is.", in: kept)
        XCTAssertTrue(keptDara.waitForExistence(timeout: 5), "Keep made the person from the contact, not a plain \"Dara\"")
        XCTAssertEqual(keptDara.identifier, "person.chip")
        XCTAssertFalse(chip(app, "Dara. Change who this is.", in: kept).exists)
    }

    // MARK: - The prompt on the landing

    /// 10: with access not asked, a recording whose kept moment names a person asks on its landing (the script answers
    /// yes), and the look again links the new name to the one contact that fits it.
    func testTheLandingAsksAndLinksTheNewName() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-followUps", "-uiTesting-contacts", "notAsked"])
        app.startSession()
        let card = app.any("card.memory")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the memory card arrives")
        card.buttons["card.add"].firstMatch.tap()
        let kept = app.any("card.kept")
        XCTAssertTrue(kept.waitForExistence(timeout: 5))
        XCTAssertTrue(chip(app, "Dara. Change who this is.", in: kept).waitForExistence(timeout: 5),
                      "before access the app sees no contacts: Dara is a new person, not a guess")
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.buttons["landing.done"].waitForExistence(timeout: 15), "the landing appears")
        let dara = chip(app, daraFromContacts)
        XCTAssertTrue(dara.waitForExistence(timeout: 30), "after the yes, Dara is linked to Dara Quinn and reads \"Assumed \u{00B7} new, from your contacts\"")
        XCTAssertEqual(dara.identifier, "person.chip.assumed", "the look again made the new link a guess")
        // The session's kept card still exists under the landing's cover, so the old chip is not asserted gone here.
    }

    // MARK: - Without access

    /// 8: access denied: the page shows the no-access card; the sheet has no contact row and offers Settings.
    func testDeniedShowsTheNoAccessCardAndNoContactRow() {
        let app = XCUIApplication.launchWithGuesses(landing: true, ["-uiTesting-contacts", "denied"])
        let marked = app.buttons.matching(identifier: "person.chip.assumed")
        XCTAssertTrue(waitCount(marked, 2))
        openSheet(app, from: marked.firstMatch)
        XCTAssertTrue(revealInSheet(app, app.buttons["who.settings"]), "the sheet offers Settings")
        XCTAssertEqual(app.buttons.matching(identifier: "who.contact").count, 0, "no contact row")
        XCTAssertFalse(app.buttons["who.search"].exists, "no search without access")
        tapDone(app)
        app.buttons["landing.done"].tap()

        openPage(app, "Danielle")
        XCTAssertTrue(rowText(app, "If the app cannot see your contacts").exists, "the no-access card")
        XCTAssertTrue(text(app, containing: "People still work.").exists)
        XCTAssertTrue(app.buttons["entity.contact.settings"].exists)
        XCTAssertEqual(app.buttons["entity.contact.settings"].label, "Allow contacts in Settings")
        XCTAssertFalse(app.buttons["entity.contact.link"].exists)
    }

    /// PB51: a person who has a contact while access was never asked (after a restore to a new phone). The button
    /// reads "Allow contacts" and asks; the script answers yes, and the row shows the link. No landing is opened (PB53).
    func testNotAskedWithAContactOffersAllowContacts() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-seedContactLink", "-uiTesting-contacts", "notAsked"])
        openPage(app, "Lena")
        XCTAssertTrue(rowText(app, "Robyn Okafor").exists, "the row names the contact it cannot see yet")
        XCTAssertTrue(text(app, containing: "If the app cannot see your contacts").exists)
        let allow = app.buttons["entity.contact.settings"]
        XCTAssertTrue(app.waitHittable(allow, timeout: 5))
        XCTAssertEqual(allow.label, "Allow contacts", "not \"in Settings\": the app has not asked yet")
        allow.tap()
        XCTAssertTrue(rowText(app, "Linked to Robyn Okafor in your contacts").waitForExistence(timeout: 10),
                      "after the yes, the row shows the link")
        XCTAssertFalse(app.buttons["entity.contact.settings"].exists)
    }

    /// Review Focus 4 (fix wave): a linked person under denied access keeps the contact's name on the row, and the
    /// button sends the owner to Settings. Nothing about the link changes.
    func testALinkedPersonUnderDeniedAccessKeepsTheContactAndOffersSettings() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-seedContactLink", "-uiTesting-contacts", "denied"])
        openPage(app, "Lena")
        XCTAssertTrue(rowText(app, "Robyn Okafor").exists, "the row names the contact the app cannot see")
        XCTAssertTrue(text(app, containing: "If the app cannot see your contacts").exists)
        let settings = app.buttons["entity.contact.settings"]
        XCTAssertTrue(app.waitHittable(settings, timeout: 5))
        XCTAssertEqual(settings.label, "Allow contacts in Settings")
        XCTAssertFalse(app.buttons["entity.contact.link"].exists)
    }

    /// 9: limited access: the search offers the system's button to share another contact.
    func testLimitedAccessOffersTheAccessButton() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-contacts", "limited"])
        openPage(app, "Maya")
        searchFromThePage(app, "rob")
        XCTAssertTrue(app.buttons["contacts.accessButton"].waitForExistence(timeout: 5), "the access button is offered")
    }

    /// 13: no `-uiTesting-contacts` (the default every other test runs under): no contact is seen anywhere. It opens no
    /// landing: a landing with a kept person asks, and in this mode the script answers no (PB29).
    func testByDefaultNothingIsLinkedAndTheSheetHasNoContactRow() {
        let app = XCUIApplication.launchWithGuesses()
        openPage(app, "Tomas")
        XCTAssertTrue(rowText(app, "Not linked to a contact").exists)
        XCTAssertTrue(app.buttons["entity.contact.link"].exists)
        XCTAssertFalse(app.any("entity.contact.suggestion").exists, "no contacts, so no suggestion")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openPage(app, "Robin Okafor")
        let someoneElse = app.buttons["entity.moment.someoneElse"].firstMatch
        XCTAssertTrue(app.reveal(someoneElse))
        openSheet(app, from: someoneElse)
        XCTAssertTrue(revealInSheet(app, app.buttons["who.search"]), "the search is offered: access was never asked")
        XCTAssertEqual(app.buttons.matching(identifier: "who.contact").count, 0, "no contact row")
    }
}
