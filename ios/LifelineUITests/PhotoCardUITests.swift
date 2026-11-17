import XCTest

/// Photo story: the photo card on the landing and on a session's page. It shows the photo, the kept memories that hold it,
/// one-tap offers (a page, the photo's date) and removals. The seed `-uiTesting-seedPhotoStory` holds two photo sessions:
/// the first (two moments) has "The beach" (unplaced; Maya, Dad) and "The drive home" (stated 2012; Dad), both holding a photo
/// dated 14 June 2012, which Maya's page holds and Dad's does not. The second has no kept memory and a photo nothing else holds.
final class PhotoCardUITests: XCTestCase {
    private static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    // MARK: - Routes

    /// Timeline, Sessions, then the first photo story: the older of the two rows that say "A story about a photo".
    /// Sessions is a lazy list, so it scrolls until both rows are in the tree.
    @MainActor
    private func openFirstStory(_ app: XCUIApplication) {
        app.openSessions()
        let stories = app.buttons.matching(identifier: "home.sessionRow").containing(.staticText, identifier: "sessions.photoStory")
        for _ in 0..<6 where stories.count < 2 { app.swipeUp() }
        XCTAssertEqual(stories.count, 2, "both photo stories are in Sessions")
        let row = stories.element(boundBy: 1)
        XCTAssertTrue(app.scrollIntoView(row), "the first story's row is on screen")
        row.tap()
        XCTAssertTrue(app.any("photoCard").waitForExistence(timeout: 10), "its page shows the photo card")
    }

    @MainActor
    private func cardMemoryTitles(_ app: XCUIApplication) -> [String] {
        app.staticTexts.matching(identifier: "photoCard.memory").allElementsBoundByIndex.filter { $0.exists }.map { $0.label }
    }

    @MainActor
    private func useDateBlocks(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(identifier: "photoCard.useDate").allElementsBoundByIndex.filter { $0.exists }
    }

    /// Opens a memory on the session's page by its title, and waits for the memory's own page.
    @MainActor
    private func openMemory(_ title: String, in app: XCUIApplication) {
        let row = app.buttons.matching(identifier: "detail.memory").matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(app.reveal(row), "\(title) is listed on the session's page")
        row.tap()
        XCTAssertTrue(app.buttons["memory.range"].waitForExistence(timeout: 10), "the memory's page for \(title) is up")
    }

    @MainActor
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }

    // MARK: - The landing

    @MainActor
    func testTheLandingSaysThePhotoGoesOnWhatYouKeep() {
        let app = XCUIApplication.launchWithPhotos()
        app.tellMayasCoversStory()
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15), "the scripted segments arrived")
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.any("photoCard").waitForExistence(timeout: 15), "the landing shows the photo card")
        let pending = app.staticTexts["photoCard.pending"]
        XCTAssertTrue(app.scrollIntoView(pending), "the pending line is on screen")
        XCTAssertEqual(pending.label, "This photo goes on each moment you keep.")
        XCTAssertFalse(app.any("photoCard.removeFromStory").exists, "a landing cannot let the story go of its photo")
        let done = app.buttons["landing.done"]
        XCTAssertTrue(app.scrollIntoView(done), "Done for now is still there")
        done.tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10), "Done for now closes the landing with no tap on the card")
    }

    @MainActor
    func testAKeptMomentHoldsThePhoto() {
        let app = XCUIApplication.launchWithPhotos()
        app.tellMayasCoversStory()
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15))
        app.buttons["session.finish"].tap()
        let review = app.buttons["landing.review"]
        XCTAssertTrue(app.scrollIntoView(review), "Review these moments is on the landing")
        review.tap()
        let title = app.staticTexts["card.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), "a card is waiting")
        let kept = title.label
        app.buttons["card.add"].firstMatch.tap()
        openMemory(kept, in: app)
        XCTAssertTrue(app.buttons["photo.thumb"].waitForExistence(timeout: 5), "the memory's page shows the photo")
        back(app)
        back(app)
        let listed = app.staticTexts["photoCard.memory"]
        XCTAssertTrue(app.scrollIntoView(listed), "the landing's card lists the kept memory")
        XCTAssertEqual(listed.label, kept)
    }

    /// Inside a landing's review no session can start, so the viewer there does not offer "Tell its story".
    @MainActor
    func testTellItsStoryIsNotOfferedInsideALandingsReview() {
        let app = XCUIApplication.launchWithPhotoStory(opening: "first")
        let review = app.buttons["landing.review"]
        XCTAssertTrue(app.scrollIntoView(review), "Review these moments is on the landing")
        review.tap()
        openMemory("The beach", in: app)
        let thumb = app.buttons["photo.thumb"]
        XCTAssertTrue(app.waitHittable(thumb, timeout: 5), "the memory's page shows the photo")
        thumb.tap()
        XCTAssertTrue(app.any("photo.viewer").waitForExistence(timeout: 5), "the viewer is up")
        XCTAssertTrue(app.buttons["photo.remove"].exists, "the viewer's other controls are there")
        XCTAssertFalse(app.buttons["photo.tellStory"].exists, "no session can start under a landing")
    }

    // MARK: - The session's page

    @MainActor
    func testTheCardOnTheSessionsPage() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        XCTAssertEqual(cardMemoryTitles(app), ["The beach", "The drive home"])
        let pages = app.buttons.matching(identifier: "photoCard.addToPage")
        XCTAssertEqual(pages.count, 1, "Dad is offered; Maya's page holds the photo already")
        XCTAssertEqual(pages.firstMatch.label, "Add to Dad's page")
    }

    @MainActor
    func testAddToAPagePutsThePhotoThere() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let add = app.buttons["photoCard.addToPage"]
        XCTAssertTrue(app.waitHittable(add, timeout: 5))
        add.tap()
        XCTAssertTrue(add.waitForNonExistence(timeout: 5), "the offer goes")
        app.openEntityPage("Dad")
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10), "Dad's first photo is his cover")
    }

    @MainActor
    func testTheDateIsOfferedOnlyWhereItHelps() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let blocks = useDateBlocks(app)
        XCTAssertEqual(blocks.count, 1, "one offer: The beach is unplaced; 2012 holds the photo's date for The drive home")
        let block = blocks.first
        XCTAssertTrue(block?.staticTexts["The beach"].exists == true, "the offer names the memory")
        XCTAssertTrue(block?.staticTexts["The photo is dated 14 June 2012. Use that for when this happened?"].exists == true)
        let use = block?.buttons["Use this date for The beach"]
        XCTAssertTrue(use?.exists == true, "the button's spoken name starts with its text and names the memory")
    }

    @MainActor
    func testUseThisDateDatesTheMemory() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let use = app.buttons["Use this date for The beach"]
        XCTAssertTrue(app.waitHittable(use, timeout: 5))
        use.tap()
        XCTAssertTrue(use.waitForNonExistence(timeout: 5), "the offer goes")
        XCTAssertTrue(useDateBlocks(app).isEmpty)
        openMemory("The beach", in: app)
        let range = app.buttons["memory.range"]
        XCTAssertTrue(range.label.contains("14 June 2012"), "the day is shown: \(range.label)")
        XCTAssertTrue(range.label.contains("from a photo"), "and its source: \(range.label)")
        XCTAssertFalse(app.staticTexts["memory.evidence"].exists, "the person did not say the date: no \"you said\" line")
    }

    @MainActor
    func testRemoveTakesThePhotoOffOneMemory() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let remove = app.buttons.matching(identifier: "photoCard.removeFromMemory").matching(NSPredicate(format: "label == %@", "Remove from The drive home")).firstMatch
        XCTAssertTrue(app.waitHittable(remove, timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "photoCard.removeFromMemory").count, 2, "one Remove for each memory")
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertEqual(cardMemoryTitles(app), ["The beach"], "the card no longer lists The drive home")
        XCTAssertEqual(app.buttons.matching(identifier: "photoCard.addToPage").count, 1, "Dad is still offered through The beach")
        XCTAssertFalse(useDateBlocks(app).contains { $0.staticTexts["The drive home"].exists }, "and nothing is offered for The drive home")
        openMemory("The drive home", in: app)
        XCTAssertFalse(app.buttons["photo.thumb"].waitForExistence(timeout: 2), "The drive home has no photo")
        back(app)
        openMemory("The beach", in: app)
        XCTAssertTrue(app.buttons["photo.thumb"].waitForExistence(timeout: 5), "The beach keeps it")
    }

    @MainActor
    func testRemoveThePhotoFromThisStory() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let remove = app.buttons["photoCard.removeFromStory"]
        XCTAssertTrue(app.reveal(remove), "the session's page can let the story go of its photo")
        XCTAssertEqual(remove.label, "Remove the photo from this story")
        remove.tap()
        // The iOS 26 dialog can list its button twice in the tree (as `row.confirmDelete` in YouUITests): take the first.
        let confirm = app.buttons["photoCard.confirmRemoveFromStory"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "it asks first")
        XCTAssertTrue(app.staticTexts["Remove this photo?"].exists)
        XCTAssertTrue(app.staticTexts["It leaves this story. The original stays in your photo library."].exists)
        XCTAssertEqual(confirm.label, "Remove photo")
        confirm.tap()
        XCTAssertTrue(app.any("photoCard").waitForNonExistence(timeout: 5), "the card is gone")
        openMemory("The beach", in: app)
        XCTAssertTrue(app.buttons["photo.thumb"].waitForExistence(timeout: 5), "The beach still shows the photo")
    }

    @MainActor
    func testKeepItLeavesThePhotoOnTheStory() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let remove = app.buttons["photoCard.removeFromStory"]
        XCTAssertTrue(app.reveal(remove))
        remove.tap()
        XCTAssertTrue(app.buttons["photoCard.confirmRemoveFromStory"].firstMatch.waitForExistence(timeout: 5), "it asks first")
        // The iOS 26 dialog can be a popover: its "Keep it" is then a tap outside it (the dismiss region); a sheet has the button.
        let keep = app.buttons["Keep it"].firstMatch, outside = app.otherElements["PopoverDismissRegion"].firstMatch
        if keep.exists { keep.tap() } else { outside.tap() }
        XCTAssertTrue(app.buttons["photoCard.confirmRemoveFromStory"].firstMatch.waitForNonExistence(timeout: 5), "the question is gone")
        XCTAssertTrue(app.any("photoCard").exists, "the card stays")
        XCTAssertTrue(remove.exists, "and so does its remove control")
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertEqual(cardMemoryTitles(app), ["The beach", "The drive home"], "nothing changed")
    }

    // MARK: - The delete dialog

    @MainActor
    func testDeletingAStorySaysWhenItsPhotoGoes() {
        let second = XCUIApplication.launchWithPhotoStory(opening: "second")
        XCTAssertTrue(second.any("photoCard").waitForExistence(timeout: 10))
        XCTAssertFalse(second.any("photoCard.removeFromStory").exists, "a landing has no remove-from-story")
        let delete = second.buttons["landing.delete"]
        XCTAssertTrue(second.scrollIntoView(delete))
        delete.tap()
        let message = second.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The audio")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "the dialog has its message")
        XCTAssertTrue(message.label.hasSuffix("This cannot be undone. Its photo goes too."), message.label)
        second.buttons["Delete the recording and everything from it"].firstMatch.tap()
        XCTAssertTrue(second.staticTexts["landing.headline"].waitForNonExistence(timeout: 10), "the delete closes the landing")
        XCTAssertTrue(second.waitHittable(second.buttons["home.start"], timeout: 10), "and the timeline is back")
        second.openSessions()
        XCTAssertEqual(second.staticTexts.matching(identifier: "sessions.photoStory").count, 1, "only the first story is left")
        second.terminate()

        let first = XCUIApplication.launchWithPhotoStory(opening: "first")
        XCTAssertTrue(first.any("photoCard").waitForExistence(timeout: 10))
        let firstDelete = first.buttons["landing.delete"]
        XCTAssertTrue(first.scrollIntoView(firstDelete))
        firstDelete.tap()
        let firstMessage = first.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The audio")).firstMatch
        XCTAssertTrue(firstMessage.waitForExistence(timeout: 5))
        XCTAssertFalse(firstMessage.label.contains("Its photo goes too."), "Maya's page holds that photo: \(firstMessage.label)")
    }

    // MARK: - No photo, no card

    @MainActor
    func testAnOrdinarySessionHasNoCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.staticTexts["landing.headline"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.any("landing.row").waitForExistence(timeout: 10), "the landing has filled in")
        XCTAssertFalse(app.any("photoCard").exists, "the landing of an ordinary session has no card")
        let review = app.buttons["landing.review"]
        XCTAssertTrue(app.scrollIntoView(review))
        review.tap()
        XCTAssertTrue(app.buttons["card.add"].firstMatch.waitForExistence(timeout: 15), "its page is up, with its waiting cards")
        XCTAssertFalse(app.any("photoCard").exists, "nor has its page")
    }

    // MARK: - The largest text

    @MainActor
    func testTheCardHoldsAtTheLargestText() {
        let landing = XCUIApplication.launchWithPhotoStory(opening: "first", Self.largestText)
        XCTAssertTrue(landing.any("photoCard").waitForExistence(timeout: 10))
        assertControlsReachable(landing, ids: ["photoCard.removeFromMemory", "photoCard.addToPage"], buttonTitles: ["Use this date for The beach"])
        landing.terminate()

        let page = XCUIApplication.launchWithPhotoStory(Self.largestText)
        openFirstStory(page)
        let last = page.buttons["photoCard.removeFromStory"]
        XCTAssertTrue(page.reveal(last), "the card's last control is in the list")
        // Revealed, it can sit clear of the record bar: the page scrolls it above the bar, not under it.
        for _ in 0..<4 where !(last.frame.maxY <= page.buttons["home.start"].frame.minY) { page.swipeUp() }
        XCTAssertTrue(last.isHittable, "the last control is not under the bar")
        XCTAssertLessThanOrEqual(last.frame.maxY, page.buttons["home.start"].frame.minY, "the last control ends above the record bar")
        assertControlsReachable(page, ids: ["photoCard.removeFromMemory", "photoCard.addToPage", "photoCard.removeFromStory"], buttonTitles: ["Use this date for The beach"])
    }

    /// Every button with these identifiers and titles is reachable and at least 44 points high.
    @MainActor
    private func assertControlsReachable(_ app: XCUIApplication, ids: [String], buttonTitles: [String]) {
        // Names are read now, while each control is in the tree: a lazy list drops it once it scrolls away.
        var controls = ids.flatMap { id in app.buttons.matching(identifier: id).allElementsBoundByIndex.map { ($0, "\(id) \($0.label)") } }
        controls += buttonTitles.map { (app.buttons[$0], $0) }
        for (control, name) in controls {
            // The page is a lazy list: start each control from the top, so a control above the last one is not skipped.
            for _ in 0..<4 { app.swipeDown() }
            XCTAssertTrue(app.scrollIntoView(control), "\(name) is reachable")
            if control.exists { XCTAssertGreaterThanOrEqual(control.frame.height, 44, "\(name) is at least 44 points high") }
        }
    }
}
