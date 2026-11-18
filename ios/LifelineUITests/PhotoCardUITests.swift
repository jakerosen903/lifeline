import XCTest

/// Photo story: the photo card on the landing and on a session's page, in one layout: the photo with its moments row (a sheet
/// lists the memories that hold it), the pages as chips in groups, one date block with Undo, and removals.
/// The seed `-uiTesting-seedPhotoStory` holds two photo sessions: the first (two moments) has "The beach" (unplaced; Maya, Dad)
/// and "The drive home" (stated 2012; Dad), both holding a photo dated 14 June 2012, which Maya's page holds and Dad's does not.
/// The second has no kept memory and a photo nothing else holds. `-uiTesting-photoStoryGuess` adds "The picnic" to the first
/// (a guess from "when I was 22"; Maya, Alder Street), which holds the photo too.
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

    /// The kept memories that hold the photo, as the moments sheet lists them: opens the row, reads, closes.
    @MainActor
    private func cardMemoryTitles(_ app: XCUIApplication) -> [String] {
        let row = app.buttons["photoCard.moments"]
        XCTAssertTrue(app.scrollIntoView(row), "the moments row is on screen")
        row.tap()
        let sheet = app.any("photoCard.momentsSheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the moments sheet is up")
        let titles = sheet.staticTexts.matching(identifier: "photoCard.memory").allElementsBoundByIndex.filter { $0.exists }.map { $0.label }
        closeSheet(app)
        return titles
    }

    @MainActor
    private func closeSheet(_ app: XCUIApplication) {
        app.buttons["photoCard.momentsDone"].tap()
        XCTAssertTrue(app.any("photoCard.momentsSheet").waitForNonExistence(timeout: 5), "the sheet is closed")
    }

    @MainActor
    private func dateBlocks(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(identifier: "photoCard.date").allElementsBoundByIndex.filter { $0.exists }
    }

    @MainActor
    private func chip(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "photoCard.page").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor
    private func labels(_ id: String, in app: XCUIApplication) -> [String] {
        app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.filter { $0.exists }.map { $0.label }
    }

    /// The session's page is a lazy list: back at its top, the card is in the tree again.
    @MainActor
    private func toTop(_ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(app.any("photoCard").waitForExistence(timeout: 5), "the card is on the page")
    }

    /// The `memory.range` label of one memory on the session's page, read on its own page; comes back to the card.
    @MainActor
    private func rangeLabel(of title: String, in app: XCUIApplication) -> String {
        openMemory(title, in: app)
        let label = app.buttons["memory.range"].label
        back(app)
        toTop(app)
        return label
    }

    /// True once the element's accessibility value reads `value`.
    @MainActor
    private func waitValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Flips a switch: a tap on its knob side, since a tap on its label does not flip it.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if inner.exists { inner.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
    }

    /// Opens a memory on the session's page by its title, and waits for the memory's own page.
    @MainActor
    private func openMemory(_ title: String, in app: XCUIApplication) {
        let row = app.buttons.matching(identifier: "detail.memory").matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(app.reveal(row), "\(title) is listed on the session's page")
        // The taller card can leave the row under the record bar and the tab bar, where XCUITest still calls it hittable:
        // a tap there opens the Timeline tab's root. The row's middle must be above the bar.
        let bar = app.buttons["home.start"]
        for _ in 0..<4 where bar.exists && row.frame.midY >= bar.frame.minY { app.swipeUp() }
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
        // Decision 9: while a moment waits, the row is only the waiting sentence.
        let pending = app.staticTexts["photoCard.pending"]
        XCTAssertTrue(app.scrollIntoView(pending), "one moment still waits, so the row says so")
        XCTAssertFalse(app.buttons["photoCard.moments"].exists, "and does not open")
        XCTAssertTrue(app.scrollIntoView(review), "Review these moments is still on the landing")
        review.tap()
        let next = app.staticTexts["card.title"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 20), "the second card is waiting")
        let keptSecond = next.label
        app.buttons["card.add"].firstMatch.tap()
        XCTAssertTrue(app.buttons["card.add"].firstMatch.waitForNonExistence(timeout: 10), "no card waits")
        back(app)
        let moments = app.buttons["photoCard.moments"]
        XCTAssertTrue(app.scrollIntoView(moments), "the landing's card has its moments row")
        XCTAssertEqual(moments.label, "On 2 moments from this story")
        XCTAssertEqual(Set(cardMemoryTitles(app)), [kept, keptSecond], "the sheet lists both kept memories")
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
        XCTAssertEqual(app.buttons["photoCard.moments"].label, "On 2 moments from this story")
        XCTAssertEqual(labels("photoCard.group", in: app), ["People"])
        let pages = app.buttons.matching(identifier: "photoCard.page").allElementsBoundByIndex
        XCTAssertEqual(pages.map(\.label), ["Dad", "Maya"])
        XCTAssertEqual(pages.map { $0.value as? String }, ["not added", "added"], "Maya's page holds the photo already")
    }

    @MainActor
    func testAddToAPagePutsThePhotoThere() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let dad = chip("Dad", in: app)
        XCTAssertTrue(app.waitHittable(dad, timeout: 5))
        dad.tap()
        XCTAssertTrue(waitValue(dad, "added"), "the chip is chosen")
        XCTAssertTrue(dad.exists, "and stays")
        app.openEntityPage("Dad")
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10), "Dad's first photo is his cover")
    }

    @MainActor
    func testOneDateBlockForTheStory() {
        let app = XCUIApplication.launchWithPhotoStory(["-uiTesting-photoStoryGuess"])
        openFirstStory(app)
        let blocks = dateBlocks(app)
        XCTAssertEqual(blocks.count, 1, "one date block for the story")
        XCTAssertEqual(app.staticTexts["photoCard.dateText"].label, "The photo is dated 14 June 2012. Two moments have no date you said.")
        XCTAssertEqual(app.buttons["photoCard.useDate"].label, "Use for those 2")
        XCTAssertEqual(app.buttons["photoCard.chooseMoments"].label, "Choose moments")
        XCTAssertFalse(blocks.first?.staticTexts["The beach"].exists ?? true, "the block names no memory")
        XCTAssertFalse(blocks.first?.staticTexts["The drive home"].exists ?? true)
    }

    @MainActor
    func testUseThisDateDatesTheMemory() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let text = app.staticTexts["photoCard.dateText"]
        XCTAssertEqual(text.label, "The photo is dated 14 June 2012. One moment has no date you said.")
        let use = app.buttons["photoCard.useDate"]
        XCTAssertTrue(app.waitHittable(use, timeout: 5))
        XCTAssertEqual(use.label, "Use for that one")
        use.tap()
        XCTAssertTrue(text.wait(for: \.label, toEqual: "The photo is dated 14 June 2012. One moment now uses that date.", timeout: 5))
        XCTAssertEqual(app.staticTexts["photoCard.dateUsed"].label, "Used for that one")
        XCTAssertFalse(app.buttons["photoCard.dateUsed"].exists, "the used state is not a control")
        XCTAssertEqual(app.buttons["photoCard.undoDate"].label, "Undo")
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
        let row = app.buttons["photoCard.moments"]
        XCTAssertTrue(app.waitHittable(row, timeout: 5))
        row.tap()
        XCTAssertTrue(app.any("photoCard.momentsSheet").waitForExistence(timeout: 5), "the moments sheet is up")
        let remove = app.buttons.matching(identifier: "photoCard.removeFromMemory").matching(NSPredicate(format: "label == %@", "Remove from The drive home")).firstMatch
        XCTAssertTrue(app.waitHittable(remove, timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "photoCard.removeFromMemory").count, 2, "one Remove for each memory")
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        closeSheet(app)
        XCTAssertTrue(row.wait(for: \.label, toEqual: "On 1 moment from this story", timeout: 5), "the row counts one moment")
        let dad = chip("Dad", in: app)
        XCTAssertTrue(dad.exists, "Dad is still listed through The beach")
        XCTAssertEqual(dad.value as? String, "not added")
        XCTAssertEqual(app.staticTexts["photoCard.dateText"].label, "The photo is dated 14 June 2012. One moment has no date you said.")
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
        toTop(app)
        XCTAssertEqual(cardMemoryTitles(app), ["The beach", "The drive home"], "nothing changed")
    }

    // MARK: - Pages as chips

    @MainActor
    func testThePagesAreInGroups() {
        let app = XCUIApplication.launchWithPhotoStory(["-uiTesting-photoStoryGuess"])
        openFirstStory(app)
        XCTAssertEqual(labels("photoCard.group", in: app), ["People", "Places"])
        XCTAssertEqual(app.buttons.matching(identifier: "photoCard.page").allElementsBoundByIndex.map(\.label), ["Dad", "Maya", "Alder Street"])
        XCTAssertTrue(app.staticTexts["Also show this photo on"].exists)
        XCTAssertTrue(app.staticTexts["Tap to add. Tap again to take it off."].exists)
        let groups = app.staticTexts.matching(identifier: "photoCard.group")
        XCTAssertLessThanOrEqual(groups.element(boundBy: 0).frame.maxY, chip("Dad", in: app).frame.minY, "People is above its first chip")
        XCTAssertLessThanOrEqual(groups.element(boundBy: 1).frame.maxY, chip("Alder Street", in: app).frame.minY, "Places is above its first chip")
    }

    @MainActor
    func testAChipAddsAndTakesOff() {
        let app = XCUIApplication.launchWithPhotoStory(["-uiTesting-photoStoryGuess"])
        openFirstStory(app)
        let dad = chip("Dad", in: app)
        XCTAssertTrue(app.waitHittable(dad, timeout: 5))
        XCTAssertEqual(dad.value as? String, "not added")
        dad.tap()
        XCTAssertTrue(waitValue(dad, "added"), "the tap adds the photo")
        app.openEntityPage("Dad")
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10), "Dad's page shows the photo")
        back(app)
        app.openTab("Timeline")
        XCTAssertTrue(app.waitHittable(dad, timeout: 5), "back on the card")
        dad.tap()
        XCTAssertTrue(waitValue(dad, "not added"), "a second tap takes it off")
        app.openEntityPage("Dad")
        XCTAssertFalse(app.buttons["photo.header"].waitForExistence(timeout: 3), "Dad's page has no photo")
    }

    @MainActor
    func testAChosenChipTakesThePhotoOffAPageThatHeldIt() {
        let app = XCUIApplication.launchWithPhotoStory()
        openFirstStory(app)
        let maya = chip("Maya", in: app)
        XCTAssertTrue(app.waitHittable(maya, timeout: 5))
        XCTAssertEqual(maya.value as? String, "added")
        maya.tap()
        XCTAssertTrue(waitValue(maya, "not added"), "the tap takes the photo off Maya's page")
        XCTAssertTrue(app.any("photoCard").exists, "the card stays: the session still holds the photo")
        openMemory("The beach", in: app)
        XCTAssertTrue(app.buttons["photo.thumb"].waitForExistence(timeout: 5), "The beach still shows the photo")
        back(app)
        toTop(app)
        XCTAssertTrue(app.waitHittable(maya, timeout: 5))
        maya.tap()
        XCTAssertTrue(waitValue(maya, "added"), "a second tap puts it back")
    }

    // MARK: - The date

    @MainActor
    func testUndoPutsTheDatesBack() {
        let app = XCUIApplication.launchWithPhotoStory(["-uiTesting-photoStoryGuess"])
        openFirstStory(app)
        let picnicBefore = rangeLabel(of: "The picnic", in: app)
        let beachBefore = rangeLabel(of: "The beach", in: app)
        let use = app.buttons["photoCard.useDate"]
        XCTAssertTrue(app.waitHittable(use, timeout: 5))
        use.tap()
        let text = app.staticTexts["photoCard.dateText"]
        XCTAssertTrue(text.wait(for: \.label, toEqual: "The photo is dated 14 June 2012. Two moments now use that date.", timeout: 5))
        for title in ["The picnic", "The beach"] {
            let range = rangeLabel(of: title, in: app)
            XCTAssertTrue(range.contains("14 June 2012"), "\(title) shows the day: \(range)")
            XCTAssertTrue(range.contains("from a photo"), "\(title) shows its source: \(range)")
        }
        let undo = app.buttons["photoCard.undoDate"]
        XCTAssertTrue(app.waitHittable(undo, timeout: 5), "Undo is still on the card")
        undo.tap()
        XCTAssertTrue(text.wait(for: \.label, toEqual: "The photo is dated 14 June 2012. Two moments have no date you said.", timeout: 5))
        XCTAssertEqual(use.label, "Use for those 2")
        XCTAssertEqual(rangeLabel(of: "The picnic", in: app), picnicBefore, "the guess is back")
        XCTAssertEqual(rangeLabel(of: "The beach", in: app), beachBefore, "the unplaced memory is unplaced again")
    }

    @MainActor
    func testChooseMomentsUsesOnlyTheCheckedOnes() {
        let app = XCUIApplication.launchWithPhotoStory(["-uiTesting-photoStoryGuess"])
        openFirstStory(app)
        let picnicBefore = rangeLabel(of: "The picnic", in: app)
        let choose = app.buttons["photoCard.chooseMoments"]
        XCTAssertTrue(app.waitHittable(choose, timeout: 5))
        choose.tap()
        let sheet = app.any("photoCard.momentsSheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the sheet is up")
        let toggles = app.switches.matching(identifier: "photoCard.chooseMoment")
        XCTAssertEqual(toggles.count, 2)
        XCTAssertEqual(toggles.allElementsBoundByIndex.map(\.label), ["The beach", "The picnic"])
        XCTAssertEqual(toggles.allElementsBoundByIndex.map { $0.value as? String }, ["1", "1"], "every moment starts on")
        let useChosen = app.buttons["photoCard.useChosen"]
        XCTAssertEqual(useChosen.label, "Use for 2")
        let beach = toggles.matching(NSPredicate(format: "label == %@", "The beach")).firstMatch
        let picnic = toggles.matching(NSPredicate(format: "label == %@", "The picnic")).firstMatch
        flip(beach)
        XCTAssertTrue(waitValue(beach, "0"))
        flip(picnic)
        XCTAssertTrue(waitValue(picnic, "0"))
        XCTAssertFalse(useChosen.isEnabled, "nothing chosen: the button does nothing")
        flip(beach)
        XCTAssertTrue(waitValue(beach, "1"))
        XCTAssertEqual(useChosen.label, "Use for 1")
        useChosen.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "the sheet closes")
        XCTAssertTrue(app.staticTexts["photoCard.dateText"].wait(for: \.label, toEqual: "The photo is dated 14 June 2012. One moment now uses that date.", timeout: 5))
        XCTAssertEqual(app.staticTexts["photoCard.dateUsed"].label, "Used for that one", "the unchecked moment does not bring the offer back")
        XCTAssertEqual(rangeLabel(of: "The picnic", in: app), picnicBefore, "the unchecked moment keeps its date")
        XCTAssertTrue(rangeLabel(of: "The beach", in: app).contains("from a photo"), "the checked one uses the photo's date")
    }

    // MARK: - One layout

    @MainActor
    func testTheCardKeepsItsLayoutAfterEachChoice() {
        let app = XCUIApplication.launchWithPhotoStory(["-uiTesting-photoStoryGuess"])
        openFirstStory(app)
        let remove = app.buttons["photoCard.removeFromStory"]
        XCTAssertTrue(app.waitHittable(remove, timeout: 5), "the whole card is on screen")
        let pages = app.buttons.matching(identifier: "photoCard.page")
        let pageFrames = pages.allElementsBoundByIndex.map(\.frame)
        let date = app.any("photoCard.date").frame
        let use = app.buttons["photoCard.useDate"].frame
        let choose = app.buttons["photoCard.chooseMoments"].frame
        let removeTop = remove.frame.minY
        let dad = chip("Dad", in: app)
        dad.tap()
        XCTAssertTrue(waitValue(dad, "added"))
        app.buttons["photoCard.useDate"].tap()
        let used = app.staticTexts["photoCard.dateUsed"]
        XCTAssertTrue(used.waitForExistence(timeout: 5))
        XCTAssertEqual(pages.allElementsBoundByIndex.map(\.frame), pageFrames, "every chip keeps its frame")
        XCTAssertEqual(app.any("photoCard.date").frame.minY, date.minY, "the date block stays where it was")
        XCTAssertEqual(used.frame, use, "the used state takes the button's frame")
        XCTAssertEqual(app.buttons["photoCard.undoDate"].frame.minY, choose.minY, "Undo sits where Choose moments sat")
        XCTAssertEqual(remove.frame.minY, removeTop, "the last control stays where it was")
    }

    @MainActor
    func testTheLandingsCardHasTheSameParts() {
        let app = XCUIApplication.launchWithPhotoStory(opening: "first", ["-uiTesting-photoStoryGuess"])
        XCTAssertTrue(app.any("photoCard").waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollIntoView(app.buttons["photoCard.moments"]), "the moments row")
        XCTAssertTrue(app.scrollIntoView(app.buttons.matching(identifier: "photoCard.page").firstMatch), "the chips")
        XCTAssertTrue(app.scrollIntoView(app.any("photoCard.date")), "the date block")
        XCTAssertFalse(app.any("photoCard.removeFromStory").exists, "a landing cannot let the story go of its photo")
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
        assertControlsReachable(landing, ids: ["photoCard.moments", "photoCard.page", "photoCard.useDate", "photoCard.chooseMoments"])
        landing.terminate()

        let page = XCUIApplication.launchWithPhotoStory(Self.largestText)
        openFirstStory(page)
        let last = page.buttons["photoCard.removeFromStory"]
        XCTAssertTrue(page.reveal(last), "the card's last control is in the list")
        // Revealed, it can sit clear of the record bar: the page scrolls it above the bar, not under it.
        for _ in 0..<4 where !(last.frame.maxY <= page.buttons["home.start"].frame.minY) { page.swipeUp() }
        XCTAssertTrue(last.isHittable, "the last control is not under the bar")
        XCTAssertLessThanOrEqual(last.frame.maxY, page.buttons["home.start"].frame.minY, "the last control ends above the record bar")
        assertControlsReachable(page, ids: ["photoCard.moments", "photoCard.page", "photoCard.useDate", "photoCard.chooseMoments", "photoCard.removeFromStory"])
        let use = page.buttons["photoCard.useDate"]
        for _ in 0..<4 { page.swipeDown() }
        XCTAssertTrue(page.scrollIntoView(use), "the date button is reachable")
        use.tap()
        XCTAssertTrue(page.buttons["photoCard.undoDate"].waitForExistence(timeout: 5), "Undo is offered")
        assertControlsReachable(page, ids: ["photoCard.undoDate"])
    }

    /// Every button with these identifiers is reachable and at least 44 points high.
    @MainActor
    private func assertControlsReachable(_ app: XCUIApplication, ids: [String]) {
        // Names are read now, while each control is in the tree: a lazy list drops it once it scrolls away.
        let controls = ids.flatMap { id in app.buttons.matching(identifier: id).allElementsBoundByIndex.map { ($0, "\(id) \($0.label)") } }
        XCTAssertEqual(Set(controls.map { $0.1.components(separatedBy: " ")[0] }), Set(ids), "each identifier has a control")
        for (control, name) in controls {
            // The page is a lazy list: start each control from the top, so a control above the last one is not skipped.
            for _ in 0..<4 { app.swipeDown() }
            XCTAssertTrue(app.scrollIntoView(control), "\(name) is reachable")
            if control.exists { XCTAssertGreaterThanOrEqual(control.frame.height, 44, "\(name) is at least 44 points high") }
        }
    }
}
