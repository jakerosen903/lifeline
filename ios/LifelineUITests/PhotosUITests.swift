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
        app.buttons["photo.makeCover"].tap()
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "")
        XCTAssertFalse(app.staticTexts["photo.caption"].exists, "no date, no caption")
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
}
