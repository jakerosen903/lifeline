import XCTest

/// "Tell a story about a photo" in the record bar's menu: the first tap explains, then the system asks; the app then
/// shows the person's Favorites (or the photos they allowed), with "All photos" for the system picker. The photo
/// library is out of process, so a scripted source serves three generated photos, newest first ("taken 14 July 2019",
/// then 2015, then 2008); `-uiTesting-photoAccess` sets its access, and `-uiTesting-pickPhoto` serves the picker path.
final class PhotoStoryStartUITests: XCTestCase {
    private static let newestCaption = "taken 14 July 2019"
    /// The caption of the `photo-orange` fixture that `-uiTesting-pickPhoto` serves.
    private static let pickedCaption = "taken 14 June 2012"

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        app.skipFirstOpen()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10), "the record bar is on screen")
        return app
    }

    @MainActor
    private func launchWithPicked(_ arguments: [String] = [], fixture: String = "photo-orange") throws -> XCUIApplication {
        launch(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath(fixture, ext: "jpg")] + arguments)
    }

    /// The record bar's menu, then "Tell a story about a photo".
    @MainActor
    private func tapTheEntry(_ app: XCUIApplication) {
        let more = app.buttons["home.more"]
        XCTAssertTrue(app.waitHittable(more, timeout: 10), "the record bar's menu is on screen")
        more.tap()
        let entry = app.buttons["home.photoStory"]
        XCTAssertTrue(app.waitHittable(entry, timeout: 5), "the entry is in the bar's menu")
        entry.tap()
    }

    @MainActor
    private func waitForGrid(_ app: XCUIApplication) {
        XCTAssertTrue(app.any("favorites.grid").waitForExistence(timeout: 10), "the grid is up")
        XCTAssertTrue(app.waitHittable(app.buttons.matching(identifier: "favorites.photo").firstMatch, timeout: 10), "the photos are on screen")
    }

    /// The session screen is up with the photo the person picked.
    @MainActor
    private func assertSessionAbout(_ app: XCUIApplication, caption: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 15), "the session starts", file: file, line: line)
        let photo = app.any("session.photo")
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "the photo is on the session screen", file: file, line: line)
        XCTAssertEqual(photo.value as? String, caption, file: file, line: line)
    }

    /// Waits for the scripted words, then Finish and "Done for now".
    @MainActor
    private func finishWithWords(_ app: XCUIApplication) {
        app.openReview()
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15), "the session hears something, so it lands")
        app.finishSession()
    }

    @MainActor
    func testTheEntryIsInTheRecordBarMenuOnEveryTab() {
        let app = launch()
        for tab in ["Timeline", "People", "Places", "Things", "You"] {
            app.openTab(tab)
            let more = app.buttons["home.more"]
            XCTAssertTrue(app.waitHittable(more, timeout: 10), "the bar's menu is on \(tab)")
            more.tap()
            let entry = app.buttons["home.photoStory"]
            XCTAssertTrue(app.waitHittable(entry, timeout: 5), "the entry is in the menu on \(tab)")
            XCTAssertEqual(entry.label, "Tell a story about a photo")
            let settle = app.buttons["home.settleIn"]
            XCTAssertTrue(settle.exists)
            XCTAssertGreaterThanOrEqual(entry.frame.minY, settle.frame.maxY - 1, "the entry sits below Settle in on \(tab)")
            // A tap away from the menu closes it and does nothing else.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
            XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 5), "the menu closed on \(tab)")
        }
    }

    @MainActor
    func testTheFirstTapExplainsThenShowsFavorites() {
        let app = launch(["-uiTesting-photoAccess", "notAsked"])
        tapTheEntry(app)
        let explanation = "Lifeline will ask to see your photos. They stay on this phone. Lifeline shows them only so you can pick one."
        XCTAssertTrue(app.staticTexts[explanation].waitForExistence(timeout: 10), "the explanation comes before the system prompt")
        let next = app.buttons["photoAccess.continue"]
        XCTAssertTrue(app.waitHittable(next, timeout: 5))
        XCTAssertEqual(next.label, "Continue")
        next.tap()
        waitForGrid(app)
        XCTAssertEqual(app.staticTexts["favorites.heading"].label, "Your favorites")
        XCTAssertEqual(app.buttons.matching(identifier: "favorites.photo").count, 3)
        // Newest first: the first photo is the newest of the three.
        app.buttons.matching(identifier: "favorites.photo").firstMatch.tap()
        assertSessionAbout(app, caption: Self.newestCaption)
    }

    @MainActor
    func testTheExplanationShowsOnce() {
        let app = launch(["-uiTesting-photoAccess", "notAsked"])
        tapTheEntry(app)
        XCTAssertTrue(app.waitHittable(app.buttons["photoAccess.continue"], timeout: 10))
        app.buttons["photoAccess.continue"].tap()
        waitForGrid(app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10), "the grid closed")
        tapTheEntry(app)
        waitForGrid(app)
        XCTAssertFalse(app.buttons["photoAccess.continue"].exists, "a second start goes straight to the grid")
    }

    @MainActor
    func testATapOnAFavoriteStartsItsStory() {
        let app = launch()
        tapTheEntry(app)
        waitForGrid(app)
        app.buttons.matching(identifier: "favorites.photo").firstMatch.tap()
        assertSessionAbout(app, caption: Self.newestCaption)
        XCTAssertFalse(app.any("favorites.grid").exists, "the grid closed before the session")
        XCTAssertFalse(app.alerts.firstMatch.exists, "no confirmation appears")
        let opening = app.staticTexts["session.prompt"]
        XCTAssertTrue(opening.waitForExistence(timeout: 5))
        XCTAssertEqual(opening.label, "Tell me about this one.")
    }

    @MainActor
    func testLimitedAccessShowsWhatWasAllowed() {
        let app = launch(["-uiTesting-photoAccess", "limited"])
        tapTheEntry(app)
        waitForGrid(app)
        XCTAssertEqual(app.staticTexts["favorites.heading"].label, "Photos you allowed")
        XCTAssertFalse(app.staticTexts["Your favorites"].exists, "the grid does not say Favorites")
    }

    @MainActor
    func testNoAccessOpensThePicker() throws {
        let app = try launchWithPicked(["-uiTesting-photoAccess", "none"])
        tapTheEntry(app)
        assertSessionAbout(app, caption: Self.pickedCaption)
        XCTAssertFalse(app.any("favorites.grid").exists, "no grid")
        XCTAssertFalse(app.any("photo.error").exists, "no error")
        XCTAssertFalse(app.buttons["photoAccess.continue"].exists, "no second ask")
    }

    @MainActor
    func testAnEmptyAlbumOpensThePicker() throws {
        let app = try launchWithPicked(["-uiTesting-photoAccess", "empty"])
        tapTheEntry(app)
        assertSessionAbout(app, caption: Self.pickedCaption)
        XCTAssertFalse(app.any("favorites.grid").exists, "no grid")
        XCTAssertFalse(app.any("photo.error").exists, "no error")
    }

    @MainActor
    func testAllPhotosOpensThePicker() throws {
        let app = try launchWithPicked()
        tapTheEntry(app)
        waitForGrid(app)
        let all = app.buttons["favorites.allPhotos"]
        XCTAssertTrue(app.waitHittable(all, timeout: 5))
        XCTAssertEqual(all.label, "All photos")
        all.tap()
        assertSessionAbout(app, caption: Self.pickedCaption)
    }

    @MainActor
    func testAnUnreadablePhotoStartsNoSession() throws {
        let app = try launchWithPicked(["-uiTesting-photoAccess", "none"], fixture: "not-a-photo")
        tapTheEntry(app)
        let error = app.any("photo.error")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "Could not add this photo: Lifeline cannot read this file as a photo.")
        XCTAssertFalse(app.buttons["session.finish"].exists, "no session screen")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10))
        XCTAssertFalse(app.buttons["session.finish"].exists, "no session started after the sheet closed")
        app.openSessions()
        XCTAssertFalse(app.any("home.sessionRow").waitForExistence(timeout: 3), "Sessions has no new row")
    }

    @MainActor
    func testTwoStoriesFromTheSameFavorite() {
        let app = launch()
        for _ in 0..<2 {
            tapTheEntry(app)
            waitForGrid(app)
            app.buttons.matching(identifier: "favorites.photo").firstMatch.tap()
            assertSessionAbout(app, caption: Self.newestCaption)
            finishWithWords(app)
        }
        app.openSessions()
        XCTAssertTrue(app.any("home.sessionRow").waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "home.sessionRow").count, 2, "two stories")
    }

    @MainActor
    func testTellAnotherOpensTheGridAgain() {
        let app = launch()
        tapTheEntry(app)
        waitForGrid(app)
        app.buttons.matching(identifier: "favorites.photo").firstMatch.tap()
        assertSessionAbout(app, caption: Self.newestCaption)
        app.openReview()
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["session.finish"].tap()
        let another = app.buttons["landing.tellAnother"]
        XCTAssertTrue(another.waitForExistence(timeout: 15), "the first session's landing offers Tell another")
        another.tap()
        XCTAssertTrue(app.any("favorites.grid").waitForExistence(timeout: 10), "Tell another opens the grid again")
        XCTAssertFalse(app.buttons["session.finish"].exists, "no session starts until a photo is picked")
    }

    @MainActor
    func testTheGridHoldsAtTheLargestText() {
        // The seeded launch skips first open, whose Skip button is out of reach at this size.
        let app = XCUIApplication.launchWithPeople(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tapTheEntry(app)
        XCTAssertTrue(app.any("favorites.grid").waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollIntoView(app.staticTexts["favorites.heading"]), "the heading is reachable")
        let all = app.buttons["favorites.allPhotos"]
        XCTAssertTrue(app.scrollIntoView(all), "All photos is reachable")
        XCTAssertGreaterThanOrEqual(all.frame.height, 44, "All photos is at least 44 points high")
        let photos = app.buttons.matching(identifier: "favorites.photo")
        for i in 0..<3 { XCTAssertTrue(app.scrollIntoView(photos.element(boundBy: i)), "photo \(i + 1) is reachable") }
    }

    @MainActor
    func testAddAPhotoStillAsksForNoAccess() throws {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-photoAccess", "notAsked",
                                                    "-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")])
        app.openEntityPage("Maya")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        let header = app.buttons["photo.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10), "the picked file is added")
        XCTAssertEqual(header.value as? String, Self.pickedCaption)
        XCTAssertFalse(app.buttons["photoAccess.continue"].exists, "Add a photo never shows the explanation")
        XCTAssertFalse(app.any("favorites.grid").exists)
    }
}
