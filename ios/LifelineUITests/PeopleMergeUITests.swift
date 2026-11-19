import XCTest

/// PC-c: two people can be merged. On a person's page "Same as another person…" opens a picker, then "Same person?";
/// the person picked stays (plan decision 2). A contact another person holds asks the same question (decision 4). On
/// the People grid one face dragged onto another asks it too. All tests use the invented family of
/// `-uiTesting-seedPeople`: the owner Jordan with Maya, Dad, Sam ("Moving into Hemenway Street") and Lena (no moment).
@MainActor
final class PeopleMergeUITests: XCTestCase {
    private let twoContacts = "They are linked to two different contacts."

    // MARK: - Helpers

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func notice(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["person.notice"] }

    /// A tile on the grid (or a row of the list at the largest text sizes), by name.
    private func gridRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func pickerRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "merge.picker.person").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// The contact row's text that starts with `heading` (the heading and its line read as one element).
    private func contactRowText(_ app: XCUIApplication, _ heading: String) -> XCUIElement {
        app.any("entity.contact.row").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", heading)).firstMatch
    }

    /// A moment row on a person's page, by its title.
    private func momentRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "entity.moment").matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// The merge sheet opens at the medium detent: a swipe on it raises it, then scrolls it.
    private func revealInSheet(_ app: XCUIApplication, _ sheet: String, _ element: XCUIElement, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists, app.waitHittable(element, timeout: 1) { return true }
            app.any(sheet).swipeUp()
        }
        return app.waitHittable(element, timeout: 2)
    }

    /// The page is a lazy List: the title leaves the tree when the page is scrolled down.
    private func scrollToTitle(_ app: XCUIApplication) -> XCUIElement {
        let title = app.staticTexts["entity.title"]
        for _ in 0..<6 where !title.exists { app.swipeDown() }
        return title
    }

    /// On the open person's page: "Same as another person…", then the picker.
    private func openPicker(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons["entity.merge"]
        XCTAssertTrue(app.reveal(row), "the page has the merge row", file: file, line: line)
        XCTAssertTrue(app.scrollIntoView(row), "the merge row is on screen", file: file, line: line)
        XCTAssertEqual(row.label, "Same as another person\u{2026}", file: file, line: line)
        row.tap()
        XCTAssertTrue(app.any("merge.picker").waitForExistence(timeout: 5), "the picker opens", file: file, line: line)
    }

    /// In the picker: the person that stays. The confirm is pushed.
    private func pick(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = pickerRow(app, name)
        XCTAssertTrue(revealInSheet(app, "merge.picker", row), "\(name) is in the picker", file: file, line: line)
        row.tap()
    }

    /// The confirm is up and names who goes and who stays.
    private func expectConfirm(_ app: XCUIApplication, leaving: String, staying: String, file: StaticString = #filePath, line: UInt = #line) {
        let confirm = app.any("merge.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Same person? opens", file: file, line: line)
        XCTAssertTrue(app.staticTexts["Same person?"].exists, file: file, line: line)
        XCTAssertEqual(app.staticTexts["merge.confirm.text"].label,
                       "\(leaving) joins \(staying). Every story, name and photo moves to \(staying).", file: file, line: line)
        for name in [leaving, staying] {
            let picture = confirm.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(picture.exists, "the confirm shows \(name)'s picture", file: file, line: line)
        }
        XCTAssertTrue(app.staticTexts["You can undo this for a few seconds only."].exists, file: file, line: line)
    }

    /// "Merge" on the confirm: the sheet closes and the slot says who stays, with Undo.
    private func tapMerge(_ app: XCUIApplication, into staying: String, file: StaticString = #filePath, line: UInt = #line) {
        let merge = app.buttons["merge.confirm.merge"]
        XCTAssertTrue(revealInSheet(app, "merge.confirm", merge), "Merge is on screen", file: file, line: line)
        XCTAssertEqual(merge.label, "Merge", file: file, line: line)
        merge.tap()
        XCTAssertTrue(waitGone(app.any("merge.confirm"), timeout: 5), "Merge closes the sheet", file: file, line: line)
        XCTAssertTrue(notice(app).waitForExistence(timeout: 3), "the slot says what happened", file: file, line: line)
        XCTAssertEqual(notice(app).label, "Merged into \(staying).", file: file, line: line)
        XCTAssertTrue(app.buttons["notice.undo"].exists, "with Undo", file: file, line: line)
    }

    /// Sam's page, the picker, Maya, the confirm, "Merge".
    private func mergeSamIntoMaya(_ app: XCUIApplication) {
        app.openEntityPage("Sam")
        openPicker(app)
        pick(app, "Maya")
        expectConfirm(app, leaving: "Sam", staying: "Maya")
        tapMerge(app, into: "Maya")
    }

    /// After the notice ends the held page closes to People (decision 2).
    private func expectThePageClosesToTheGrid(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitGone(notice(app), timeout: 10), "the notice ends", file: file, line: line)
        XCTAssertTrue(waitGone(app.buttons["entity.merge"], timeout: 5), "the page closes when the notice ends", file: file, line: line)
        XCTAssertTrue(app.buttons.matching(identifier: "entities.row").firstMatch.waitForExistence(timeout: 5), "back on People", file: file, line: line)
    }

    /// Sam's page, "Link to a contact", then the search with `query`, then the result with `label`.
    private func linkFromThePage(_ app: XCUIApplication, query: String, result label: String, file: StaticString = #filePath, line: UInt = #line) {
        let link = app.buttons["entity.contact.link"]
        XCTAssertTrue(app.waitHittable(link, timeout: 10), "Link to a contact is on screen", file: file, line: line)
        link.tap()
        search(app, query, pick: label, file: file, line: line)
    }

    private func search(_ app: XCUIApplication, _ query: String, pick label: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["contacts.search"]
        XCTAssertTrue(app.waitHittable(field, timeout: 10), "the contacts search field is on screen", file: file, line: line)
        field.tap()
        field.typeText(query)
        let result = app.buttons.matching(identifier: "contacts.result").matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "the search finds \(label)", file: file, line: line)
        // The keyboard is still moving the sheet: tap only once the row holds still.
        XCTAssertTrue(app.waitHittable(result, timeout: 5), "the result is on screen and still", file: file, line: line)
        result.tap()
    }

    /// Sam linked to "Dara Quinn" from his page.
    private func linkSamToDaraQuinn(_ app: XCUIApplication) {
        XCTAssertTrue(app.any("entity.contact.row").waitForExistence(timeout: 10), "Sam's page has a contact row")
        linkFromThePage(app, query: "dara", result: "Dara Quinn")
        XCTAssertTrue(contactRowText(app, "Linked to Dara Quinn in your contacts").waitForExistence(timeout: 10), "Sam is linked to Dara Quinn")
    }

    // MARK: - The button on a person's page

    /// Sam joins Maya: the notice, then the page closes; the grid has Maya and no Sam; Maya's page has Sam's moment.
    func testSameAsAnotherPersonMergesByTheButton() {
        let app = XCUIApplication.launchWithPeople()
        mergeSamIntoMaya(app)
        XCTAssertFalse(app.buttons["entity.merge"].isEnabled, "the page of Sam reads only while the notice is up")
        expectThePageClosesToTheGrid(app)
        let names = app.entityRowLabels()
        XCTAssertTrue(names.contains("Maya"), "Maya stays: \(names)")
        XCTAssertFalse(names.contains("Sam"), "Sam is gone: \(names)")

        app.openEntityPage("Maya")
        XCTAssertTrue(app.reveal(momentRow(app, "Moving into Hemenway Street"), swipes: 10), "Maya's page has Sam's moment")
    }

    /// Undo brings Sam back: his page is live again and stays after the window; the grid has both.
    func testUndoBringsBothPeopleBack() {
        let app = XCUIApplication.launchWithPeople()
        mergeSamIntoMaya(app)
        let undo = app.buttons["notice.undo"]
        XCTAssertTrue(app.waitHittable(undo, timeout: 3), "Undo is on screen")
        undo.tap()
        XCTAssertTrue(waitGone(notice(app), timeout: 3), "Undo ends the notice")
        XCTAssertTrue(app.buttons["entity.merge"].isEnabled, "the page of Sam is live again")
        // Past the notice's six seconds: a page whose person came back does not close.
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        XCTAssertEqual(scrollToTitle(app).label, "Sam", "the page carries on after Undo")
        XCTAssertTrue(momentRow(app, "Moving into Hemenway Street").exists, "Sam keeps his moment")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(gridRow(app, "Sam").waitForExistence(timeout: 5), "Sam is back on the grid")
        XCTAssertTrue(gridRow(app, "Maya").exists, "Maya is still there")
        app.openEntityPage("Maya")
        XCTAssertFalse(app.reveal(momentRow(app, "Moving into Hemenway Street"), swipes: 10), "Sam's moment left Maya's page")
    }

    func testCancelOnTheConfirmChangesNothing() {
        let app = XCUIApplication.launchWithPeople()
        app.openEntityPage("Sam")
        openPicker(app)
        pick(app, "Maya")
        expectConfirm(app, leaving: "Sam", staying: "Maya")
        let cancel = app.buttons["merge.confirm.cancel"]
        XCTAssertTrue(revealInSheet(app, "merge.confirm", cancel), "Cancel is on screen")
        XCTAssertEqual(cancel.label, "Cancel")
        cancel.tap()
        XCTAssertTrue(waitGone(app.any("merge.confirm"), timeout: 5), "Cancel closes the sheet")
        XCTAssertFalse(app.any("merge.picker").exists, "the whole sheet closes")
        XCTAssertFalse(notice(app).waitForExistence(timeout: 2), "nothing merged, so nothing is said")
        XCTAssertTrue(app.buttons["entity.merge"].isEnabled, "the page stays live")
        XCTAssertEqual(scrollToTitle(app).label, "Sam")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(gridRow(app, "Sam").waitForExistence(timeout: 5), "Sam is still on the grid")
        XCTAssertTrue(gridRow(app, "Maya").exists, "and Maya")
    }

    func testThePickerLeavesOutThisPersonAndTheOwner() {
        let app = XCUIApplication.launchWithPeople()
        app.openEntityPage("Sam")
        openPicker(app)
        XCTAssertTrue(app.staticTexts["Who is Sam the same as?"].exists, "the picker's title names Sam")
        let rows = app.buttons.matching(identifier: "merge.picker.person")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let names = rows.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Set(names), ["Maya", "Dad", "Lena"], "every other person, once: \(names)")
        XCTAssertFalse(names.contains("Sam"), "not the page's own person")
        XCTAssertFalse(names.contains("Jordan"), "never the owner")
    }

    /// Sam holds "Dara Quinn" and Lena "Robyn Okafor": the merge is refused, no confirm opens, both stay.
    func testTwoDifferentContactsRefuse() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-seedContactLink", "-uiTesting-contacts", "full"])
        app.openEntityPage("Sam")
        linkSamToDaraQuinn(app)
        openPicker(app)
        pick(app, "Lena")
        XCTAssertTrue(waitGone(app.any("merge.picker"), timeout: 5), "the refused pick closes the sheet")
        XCTAssertTrue(notice(app).waitForExistence(timeout: 3), "the page says why")
        XCTAssertEqual(notice(app).label, twoContacts)
        XCTAssertFalse(app.buttons["notice.undo"].exists, "nothing to undo")
        XCTAssertFalse(app.any("merge.confirm").exists, "no confirm opens")
        XCTAssertTrue(contactRowText(app, "Linked to Dara Quinn in your contacts").exists, "Sam keeps his contact")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(gridRow(app, "Sam").waitForExistence(timeout: 5), "Sam stays")
        XCTAssertTrue(gridRow(app, "Lena").exists, "Lena stays")
    }

    /// At the largest text size the confirm scrolls, and "Merge" can be reached and works.
    func testTheConfirmScrollsAtTheLargestTextSize() {
        let app = XCUIApplication.launchWithPeople(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.openEntityPage("Sam")
        openPicker(app)
        pick(app, "Maya")
        let confirm = app.any("merge.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Same person? opens")
        let merge = app.buttons["merge.confirm.merge"]
        XCTAssertTrue(app.reveal(merge), "Merge is in the confirm")
        XCTAssertTrue(revealInSheet(app, "merge.confirm", merge), "a swipe brings Merge on screen")
        merge.tap()
        XCTAssertTrue(waitGone(confirm, timeout: 5), "Merge closes the sheet")
        XCTAssertTrue(notice(app).waitForExistence(timeout: 3))
        XCTAssertEqual(notice(app).label, "Merged into Maya.")
    }

    // MARK: - A contact another person holds (plan decision 4)

    /// Sam has no contact and picks the one Lena holds: "Merge" moves Sam into Lena, and Lena keeps the contact.
    func testAContactAnotherPersonHoldsMergesIntoTheHolder() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-seedContactLink", "-uiTesting-contacts", "full"])
        app.openEntityPage("Sam")
        XCTAssertTrue(contactRowText(app, "Not linked to a contact").waitForExistence(timeout: 10), "Sam starts with no contact")
        linkFromThePage(app, query: "okafor", result: "Robyn Okafor. In a story as Lena")
        expectConfirm(app, leaving: "Sam", staying: "Lena")
        tapMerge(app, into: "Lena")
        expectThePageClosesToTheGrid(app)
        let names = app.entityRowLabels()
        XCTAssertTrue(names.contains("Lena"), "the holder stays: \(names)")
        XCTAssertFalse(names.contains("Sam"), "Sam is gone: \(names)")

        app.openEntityPage("Lena")
        XCTAssertTrue(contactRowText(app, "Linked to Robyn Okafor in your contacts").waitForExistence(timeout: 10), "Lena keeps the contact")
        XCTAssertTrue(app.reveal(momentRow(app, "Moving into Hemenway Street")), "Lena has Sam's moment")
    }

    /// Sam holds "Dara Quinn" and picks "Robyn Okafor", which Lena holds: refused, no confirm, both stay.
    func testAContactAnotherPersonHoldsWithTwoContactsRefuses() {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-seedContactLink", "-uiTesting-contacts", "full"])
        app.openEntityPage("Sam")
        linkSamToDaraQuinn(app)
        let change = app.buttons["entity.contact.change"]
        XCTAssertTrue(app.waitHittable(change, timeout: 5), "Change is on screen")
        change.tap()
        let another = app.buttons["Link to another contact"]
        XCTAssertTrue(app.waitHittable(another, timeout: 5), "the menu offers another contact")
        another.tap()
        search(app, "okafor", pick: "Robyn Okafor. In a story as Lena")
        XCTAssertTrue(notice(app).waitForExistence(timeout: 5), "the page says why")
        XCTAssertEqual(notice(app).label, twoContacts)
        XCTAssertFalse(app.any("merge.confirm").exists, "no confirm opens")
        XCTAssertTrue(contactRowText(app, "Linked to Dara Quinn in your contacts").exists, "Sam keeps his own contact")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(gridRow(app, "Sam").waitForExistence(timeout: 5), "Sam stays")
        XCTAssertTrue(gridRow(app, "Lena").exists, "Lena stays")
    }

    // MARK: - The drag on the People grid

    /// A long press on Sam's face, dragged onto Maya's: Maya stays (the person dropped onto). Undo brings Sam back.
    func testDraggingOneFaceOntoAnotherAsksSamePerson() {
        let app = XCUIApplication.launchWithPeople()
        app.openTab("People")
        let sam = gridRow(app, "Sam"), maya = gridRow(app, "Maya")
        XCTAssertTrue(app.waitHittable(sam, timeout: 10), "Sam's tile is on screen")
        XCTAssertTrue(app.waitHittable(maya, timeout: 5), "Maya's tile is on screen")
        sam.press(forDuration: 1.5, thenDragTo: maya, withVelocity: .slow, thenHoldForDuration: 1.0)
        expectConfirm(app, leaving: "Sam", staying: "Maya")
        tapMerge(app, into: "Maya")
        XCTAssertTrue(waitGone(sam, timeout: 3), "Sam's tile leaves the grid")
        app.buttons["notice.undo"].tap()
        XCTAssertTrue(gridRow(app, "Sam").waitForExistence(timeout: 5), "Undo brings Sam back")
        XCTAssertTrue(gridRow(app, "Maya").exists)
    }
}
