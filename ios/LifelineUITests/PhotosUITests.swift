import XCTest

/// S4: a photo added from a page's menu heads the page; two or more sit in a row; the viewer makes a cover
/// and removes a photo. The picker is out of process, so `-uiTesting-pickPhoto` hands the app a generated file.
final class PhotosUITests: XCTestCase {
    @MainActor
    func testAddingAPhotoMakesItThePagesCover() throws {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")])
        app.openEntityPage("Lena")
        XCTAssertFalse(app.buttons["photo.header"].exists, "no photo, no frame")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        let header = app.buttons["photo.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.label, "Photo of Lena")
        XCTAssertEqual(header.value as? String, "taken 14 June 2012")
        XCTAssertEqual(app.staticTexts["photo.caption"].label, "taken 14 June 2012")
        XCTAssertLessThan(header.frame.maxY, app.staticTexts["entity.title"].frame.minY, "the title sits under the photo, not on it")
        XCTAssertGreaterThan(header.frame.height, header.frame.width, "the rotated photo is stored upright and framed 3:4")
        XCTAssertFalse(app.staticTexts["Photos"].exists, "one photo is the header, not a row")
    }

    @MainActor
    func testAPageWithoutAPhotoHasNoFrame() {
        let app = XCUIApplication.launchWithPhotos()
        app.openEntityPage("Sam")
        XCTAssertFalse(app.buttons["photo.header"].exists)
        XCTAssertFalse(app.staticTexts["Photos"].exists)
        XCTAssertFalse(app.buttons.matching(identifier: "photo.thumb").firstMatch.exists)
    }

    @MainActor
    func testSeveralPhotosShowInARow() {
        let app = XCUIApplication.launchWithPhotos()
        app.openEntityPage("Maya")
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "taken 14 June 2012")
        let thumbs = app.buttons.matching(identifier: "photo.thumb")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        XCTAssertEqual(thumbs.count, 2)
        XCTAssertEqual(thumbs.allElementsBoundByIndex.map(\.label), ["Photo of Maya", "Photo of Maya"])
        XCTAssertEqual(thumbs.allElementsBoundByIndex.map { $0.value as? String ?? "" }, ["taken 14 June 2012", ""], "cover first")
        XCTAssertLessThan(app.buttons["entity.oftenWith"].firstMatch.frame.minY, app.staticTexts["Photos"].frame.minY)
        XCTAssertLessThan(app.staticTexts["Photos"].frame.minY, app.buttons["entity.moment"].firstMatch.frame.minY)
    }

    @MainActor
    func testMakeThisTheCoverChangesTheHeader() {
        let app = XCUIApplication.launchWithPhotos()
        app.openEntityPage("Maya")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        app.buttons.matching(identifier: "photo.thumb").element(boundBy: 1).tap()
        XCTAssertTrue(app.any("photo.viewer").waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["photo.makeCover"].label, "Make this the key photo")
        app.buttons["photo.makeCover"].tap()
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "")
        XCTAssertFalse(app.staticTexts["photo.caption"].exists, "no date, no caption")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        XCTAssertEqual(thumbValues(app), ["", "taken 14 June 2012"], "the key photo moved to the front")
    }

    // MARK: - The key photo on the shelf

    @MainActor
    func testTheShelfSaysWhichPhotoIsTheKeyPhoto() {
        let app = openMayasShelf()
        let hint = app.staticTexts["photo.shelfHint"]
        XCTAssertTrue(hint.exists)
        XCTAssertEqual(hint.label, "The first photo is the key photo. Hold a photo and drag it to the front to change it.")
        let first = thumbs(app).element(boundBy: 0)
        XCTAssertLessThan(app.staticTexts["Photos"].frame.maxY, hint.frame.minY + 1, "the line sits under the heading")
        XCTAssertLessThan(hint.frame.maxY, first.frame.minY + 1, "and above the tiles")
        let key = app.any("photo.keyLabel")
        XCTAssertTrue(key.exists)
        XCTAssertEqual(key.label, "Key photo")
        XCTAssertTrue(first.frame.contains(key.frame), "the pill is on the first tile: \(key.frame) in \(first.frame)")
    }

    @MainActor
    func testDraggingAPhotoToTheFrontChangesTheKeyPhoto() {
        let app = openMayasShelf()
        let all = thumbs(app)
        all.element(boundBy: 1).press(forDuration: 1.0, thenDragTo: all.element(boundBy: 0))
        XCTAssertFalse(app.any("photo.viewer").exists, "a drag does not open the viewer")
        XCTAssertTrue(app.buttons["photo.header"].waitForValue("", timeout: 5), "the undated photo is the key photo now")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        XCTAssertEqual(thumbValues(app), ["", "taken 14 June 2012"])
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openEntityPage("Maya")
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "", "the order is stored")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        XCTAssertEqual(thumbValues(app), ["", "taken 14 June 2012"])
    }

    @MainActor
    func testDraggingTheKeyPhotoAwayMakesTheNextOneTheKeyPhoto() {
        let app = openMayasShelf()
        let all = thumbs(app)
        all.element(boundBy: 0).press(forDuration: 1.0, thenDragTo: all.element(boundBy: 1))
        XCTAssertTrue(app.buttons["photo.header"].waitForValue("", timeout: 5), "the next photo is the key photo")
    }

    @MainActor
    func testADragThatEndsWhereItStartedChangesNothing() {
        let app = openMayasShelf()
        let second = thumbs(app).element(boundBy: 1)
        let start = second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: 6, dy: 0)))
        XCTAssertEqual(thumbValues(app), ["taken 14 June 2012", ""])
        XCTAssertFalse(app.any("photo.error").exists)
        XCTAssertFalse(app.any("photo.viewer").exists)
    }

    @MainActor
    func testADragThatRestsBeforeTheReleaseDoesNotOpenTheViewer() {
        let app = openMayasShelf()
        let all = thumbs(app)
        all.element(boundBy: 1).press(forDuration: 1.0, thenDragTo: all.element(boundBy: 0), withVelocity: .default, thenHoldForDuration: 1.0)
        XCTAssertTrue(app.buttons["photo.header"].waitForValue("", timeout: 5), "the move happened")
        XCTAssertFalse(app.any("photo.viewer").exists, "the release of a drag is not a tap")
    }

    @MainActor
    func testAHoldWithNoMoveDoesNotOpenTheViewer() {
        let app = openMayasShelf()
        thumbs(app).element(boundBy: 1).press(forDuration: 1.5)
        XCTAssertFalse(app.any("photo.viewer").waitForExistence(timeout: 2), "the release of a hold is not a tap")
        XCTAssertEqual(thumbValues(app), ["taken 14 June 2012", ""], "the order is unchanged")
    }

    @MainActor
    func testATapOnAThumbStillOpensTheViewer() {
        let app = openMayasShelf()
        let all = thumbs(app)
        all.element(boundBy: 1).press(forDuration: 1.0, thenDragTo: all.element(boundBy: 0))
        XCTAssertTrue(app.buttons["photo.header"].waitForValue("", timeout: 5))
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        thumbs(app).element(boundBy: 1).tap()
        XCTAssertTrue(app.any("photo.viewer").waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnePhotoHasNoHintAndNoDrag() {
        let app = XCUIApplication.launchWithPhotos(); app.openEntityPage("Maya")
        let moment = app.buttons.matching(identifier: "entity.moment").matching(NSPredicate(format: "label == %@", "The tree house")).firstMatch
        XCTAssertTrue(app.reveal(moment)); moment.tap()
        XCTAssertTrue(app.buttons["memory.range"].waitForExistence(timeout: 5))
        let thumb = thumbs(app).firstMatch
        XCTAssertTrue(thumb.exists)
        XCTAssertTrue(app.any("photo.keyLabel").exists)
        XCTAssertFalse(app.staticTexts["photo.shelfHint"].exists)
        let start = thumb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: 120, dy: 0)))
        XCTAssertFalse(app.any("photo.viewer").exists)
        XCTAssertEqual(thumbs(app).count, 1)
        XCTAssertEqual(thumbValues(app), ["taken 4 July 1999"])
        XCTAssertFalse(app.any("photo.error").exists)
    }

    @MainActor
    func testTheShelfHoldsAtTheLargestText() {
        let app = openMayasShelf(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let hint = app.staticTexts["photo.shelfHint"]
        XCTAssertTrue(app.reveal(hint))
        XCTAssertGreaterThan(hint.frame.height, 44, "the line wraps, it does not clip")
        for thumb in thumbs(app).allElementsBoundByIndex { XCTAssertGreaterThanOrEqual(thumb.frame.height, 44) }
    }

    @MainActor
    private func openMayasShelf(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.launchWithPhotos(extra)
        app.openEntityPage("Maya")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        return app
    }

    @MainActor
    private func thumbs(_ app: XCUIApplication) -> XCUIElementQuery { app.buttons.matching(identifier: "photo.thumb") }

    @MainActor
    private func thumbValues(_ app: XCUIApplication) -> [String] {
        thumbs(app).allElementsBoundByIndex.map { $0.value as? String ?? "" }
    }

    @MainActor
    func testRemovingTheCoverAsksFirstAndPassesTheCoverOn() {
        let app = XCUIApplication.launchWithPhotos()
        app.openEntityPage("Maya")
        app.buttons["photo.header"].tap()
        XCTAssertFalse(app.buttons["photo.makeCover"].exists, "it is already the cover")
        app.buttons["photo.remove"].tap()
        // A dialog button appears twice in the tree on iOS 26 (a button in a button), as `row.confirmDelete` does.
        let confirm = app.buttons["photo.confirmRemove"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "Remove photo")
        XCTAssertTrue(app.staticTexts["It leaves this page. The original stays in your photo library."].exists)
        confirm.tap()
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "", "the other photo is the cover now")
        XCTAssertFalse(app.staticTexts["Photos"].exists, "one photo left: no row")
    }

    @MainActor
    func testAnUnreadablePhotoSaysSoAndAddsNothing() throws {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("not-a-photo", ext: "jpg")])
        app.openEntityPage("Lena")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        let error = app.any("photo.error")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "Could not add this photo: Lifeline cannot read this file as a photo.")
        XCTAssertFalse(app.buttons["photo.header"].exists)
        XCTAssertTrue(app.staticTexts["entity.title"].isHittable, "the page stays as it was")
    }

    @MainActor
    func testTheViewerControlsAreFullSizeAtTheLargestText() {
        let app = XCUIApplication.launchWithPhotos(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.openEntityPage("Maya")
        app.buttons["photo.header"].tap()
        for id in ["photo.remove", "photo.done"] { XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44) }
        // The page's own caption stays in the tree under the sheet: this is the viewer's.
        XCTAssertTrue(app.any("photo.viewer").staticTexts["photo.caption"].frame.height > 0, "the caption reads in full")
    }

    // MARK: - A memory page and You

    @MainActor
    func testAMemoryShowsItsPhotos() {
        let app = XCUIApplication.launchWithPhotos(); app.openEntityPage("Maya")
        let moment = app.buttons.matching(identifier: "entity.moment").matching(NSPredicate(format: "label == %@", "The tree house")).firstMatch
        XCTAssertTrue(app.reveal(moment)); moment.tap() // A List holds only the rows on screen; the cover and the row push this one below.
        XCTAssertTrue(app.buttons["memory.range"].waitForExistence(timeout: 5)) // "The tree house" is an event: its page shows the range, not a kind.
        let thumb = app.buttons.matching(identifier: "photo.thumb").firstMatch
        XCTAssertTrue(thumb.exists)
        XCTAssertEqual(thumb.label, "Photo for The tree house")
        XCTAssertEqual(thumb.value as? String, "taken 4 July 1999")
    }

    @MainActor
    func testAPhotoAddedToAMemoryShowsThere() throws {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")])
        app.openEntityPage("Sam")
        app.buttons.matching(identifier: "entity.moment").firstMatch.tap()
        XCTAssertFalse(app.buttons.matching(identifier: "photo.thumb").firstMatch.exists, "no photo, no frame")
        app.addPhotoFromMenu("memory.more", "memory.addPhoto")
        XCTAssertTrue(app.buttons.matching(identifier: "photo.thumb").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["memory.change"].exists, "Change… stays a labeled button")
    }

    @MainActor
    func testYouShowsYourCover() {
        let app = XCUIApplication.launchWithPhotos(); app.openYou()
        let header = app.buttons["photo.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "Photo of you")
        XCTAssertLessThan(header.frame.maxY, app.staticTexts["you.name"].frame.minY)
        XCTAssertTrue(app.buttons["home.settings"].exists)
    }

    @MainActor
    func testAddingAPhotoOnYouGoesToYourPage() throws {
        let app = XCUIApplication.launchWithPortrait(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")]); app.openYou()
        XCTAssertFalse(app.buttons["photo.header"].exists)
        app.addPhotoFromMenu("you.more", "you.addPhoto")
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10))
        app.buttons["entities.aboutYou"].tap()
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["photo.header"].label, "Photo of you")
    }

    @MainActor
    func testAnUnreadablePhotoOnYouUsesYourSlot() throws {
        let app = XCUIApplication.launchWithPortrait(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("not-a-photo", ext: "jpg")]); app.openYou()
        app.addPhotoFromMenu("you.more", "you.addPhoto")
        XCTAssertTrue(app.any("you.error").waitForExistence(timeout: 10))
        XCTAssertEqual(app.any("you.error").label, "Could not add this photo: Lifeline cannot read this file as a photo.")
    }

    // MARK: - Several photos at one time (part 4)

    @MainActor
    func testSeveralPhotosAreAddedInTheOrderPicked() throws {
        let app = XCUIApplication.launchWithPhotos(try pickPhotos(["photo-orange", "photo-green"]))
        app.openEntityPage("Maya")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        XCTAssertEqual(thumbValues(app), ["taken 14 June 2012", ""])
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        XCTAssertTrue(waitForCount(thumbs(app), 4, timeout: 20), "the row gains two thumbs")
        XCTAssertEqual(thumbValues(app), ["taken 14 June 2012", "", "taken 14 June 2012", "taken 2 March 2005"],
                       "the picked photos follow the ones the page had, in the order picked; the key photo stays first")
        XCTAssertFalse(app.any("photo.error").exists)
    }

    @MainActor
    func testOneBadPhotoDoesNotStopTheOthers() throws {
        let app = XCUIApplication.launchWithPhotos(try pickPhotos(["photo-orange", "not-a-photo", "photo-green"]))
        app.openEntityPage("Maya")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        let error = app.any("photo.error")
        XCTAssertTrue(error.waitForExistence(timeout: 20))
        XCTAssertEqual(error.label, "Could not add this photo: Lifeline cannot read this file as a photo.", "one failure keeps today's line")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "photo.error").count, 1, "one error line")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        XCTAssertTrue(waitForCount(thumbs(app), 4, timeout: 10), "the two good photos are added")
        XCTAssertEqual(thumbValues(app), ["taken 14 June 2012", "", "taken 14 June 2012", "taken 2 March 2005"])
    }

    @MainActor
    func testTheFirstPickedPhotoIsTheKeyPhotoOnAnEmptyPage() throws {
        let app = XCUIApplication.launchWithPeople(try pickPhotos(["photo-green", "photo-orange"]))
        app.openEntityPage("Lena")
        XCTAssertFalse(app.buttons["photo.header"].exists, "no photo, no frame")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        // The header is read before the scroll to the row: a scrolled page can drop it from the tree.
        XCTAssertTrue(app.staticTexts["Photos"].waitForExistence(timeout: 20), "two photos make a row")
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "taken 2 March 2005", "the first picked photo is the key photo")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        XCTAssertTrue(waitForCount(thumbs(app), 2, timeout: 20))
        XCTAssertEqual(thumbValues(app), ["taken 2 March 2005", "taken 14 June 2012"])
    }

    @MainActor
    func testTheSamePhotoPickedTwiceIsAddedOnce() throws {
        // Two copies of one image: the library finds the stored photo by its hash.
        let app = XCUIApplication.launchWithPeople(try pickPhotos(["photo-orange", "photo-orange"]))
        app.openEntityPage("Lena")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 20))
        XCTAssertTrue(waitForAbsence(app.any("photo.adding"), timeout: 20), "both photos are done")
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "taken 14 June 2012")
        XCTAssertFalse(app.staticTexts["Photos"].exists, "one photo is the header, not a row")
        XCTAssertFalse(thumbs(app).firstMatch.exists)
        XCTAssertFalse(app.any("photo.error").exists, "the second is no failure")
    }

    /// Each file waits three seconds (`-uiTesting-slowPhotoFile`), so the page is seen while the photos are added.
    @MainActor
    func testAddAPhotoWaitsWhilePhotosAreAdded() throws {
        let app = XCUIApplication.launchWithPeople(try pickPhotos(["photo-orange", "photo-green"]) + ["-uiTesting-slowPhotoFile"])
        app.openEntityPage("Lena")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        XCTAssertTrue(app.any("photo.adding").waitForExistence(timeout: 5), "the photos are being added")
        app.buttons["entity.more"].tap()
        let add = app.buttons["entity.addPhoto"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Add a photo stays in the menu")
        XCTAssertFalse(add.isEnabled, "a second pick cannot start while photos are added")
        XCTAssertEqual(add.label, "Add a photo")
        closeMenu(app)
        XCTAssertTrue(waitForAbsence(app.any("photo.adding"), timeout: 30), "both photos are done")
        XCTAssertTrue(app.staticTexts["Photos"].waitForExistence(timeout: 5), "both photos were added")
        app.buttons["entity.more"].tap()
        XCTAssertTrue(app.waitHittable(add, timeout: 5))
        XCTAssertTrue(add.isEnabled, "Add a photo works again once the photos are added")
    }

    /// A tap away from the menu closes it and does nothing else. Lena's page is empty there: she has no moment.
    @MainActor
    private func closeMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        XCTAssertTrue(app.waitHittable(app.buttons["entity.more"], timeout: 5), "the menu closed")
    }

    /// `-uiTesting-pickPhotos` with a fresh copy of each fixture, in this order.
    @MainActor
    private func pickPhotos(_ names: [String]) throws -> [String] {
        ["-uiTesting-pickPhotos", try names.map { try XCUIApplication.fixturePath($0, ext: "jpg") }.joined(separator: ",")]
    }

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, _ count: Int, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: query)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

private extension XCUIElement {
    /// A write lands after the gesture ends: waits for the element to read `value`.
    func waitForValue(_ value: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
