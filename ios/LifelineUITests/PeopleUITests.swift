import XCTest

final class PeopleUITests: XCTestCase {
    @MainActor
    func testTheSeedReachesEveryList() {
        let app = XCUIApplication.launchWithPeople()
        app.openTab("People")
        XCTAssertTrue(app.buttons.matching(identifier: "entities.row").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(Set(app.entityRowLabels()), ["Maya", "Dad", "Sam", "Lena"], "the owner, Jordan, is never a row")
        app.openTab("Places")
        XCTAssertTrue(app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "Alder Street")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPeopleIsAGridOfNamesAndOwnWords() {
        let app = XCUIApplication.launchWithPeople(); app.openTab("People")
        XCTAssertTrue(app.any("people.grid").waitForExistence(timeout: 5))
        XCTAssertEqual(app.entityRowLabels(), ["Maya", "Dad", "Sam", "Lena"])
        // Reading order: top to bottom, then leading to trailing (the same order `entityRowLabels` returns).
        let tiles = app.buttons.matching(identifier: "entities.row").allElementsBoundByIndex
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        XCTAssertEqual(tiles.map { $0.value as? String ?? "" }, ["my sister", "my dad", "my roommate", ""])
        XCTAssertEqual(tiles[0].frame.minY, tiles[2].frame.minY, accuracy: 1, "three to a row")
        XCTAssertEqual(app.buttons["people.sort"].label, "Most told")
        // The hint is not readable from XCUITest; the visible title is: the sort is state the person can see.
        XCTAssertTrue(app.staticTexts["Most told"].exists, "the current sort shows as text")
    }

    @MainActor
    func testTheSortMenuReorders() {
        let app = XCUIApplication.launchWithPeople(); app.openTab("People")
        app.buttons["people.sort"].tap(); app.buttons["people.sort.byName"].tap()
        XCTAssertEqual(app.entityRowLabels(), ["Dad", "Lena", "Maya", "Sam"])
        app.buttons["people.sort"].tap(); app.buttons["people.sort.firstInStory"].tap()
        XCTAssertEqual(app.entityRowLabels(), ["Dad", "Maya", "Sam", "Lena"])
        XCTAssertEqual(app.buttons["people.sort"].label, "First in your story")
    }

    @MainActor
    func testATileOpensItsPage() {
        let app = XCUIApplication.launchWithPeople(); app.openTab("People")
        app.openEntityPage("Maya")
        XCTAssertEqual(app.staticTexts["entity.title"].label, "Maya")
    }

    @MainActor
    func testNoTileOffersAPhoto() {
        let app = XCUIApplication.launchWithPeople(); app.openTab("People")
        XCTAssertTrue(app.any("people.grid").waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "photo")).count, 0)
    }

    @MainActor
    func testTheGridBecomesAListAtTheLargestTextSize() {
        let app = XCUIApplication.launchWithPeople(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.openTab("People")
        XCTAssertTrue(app.any("people.list").waitForExistence(timeout: 5))
        XCTAssertFalse(app.any("people.grid").exists)
        XCTAssertEqual(Set(app.entityRowLabels()), ["Maya", "Dad", "Sam", "Lena"])
    }

    // MARK: - Covers

    /// A tile or row of this person, by its label.
    private func personRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    @MainActor
    func testATileShowsItsCover() {
        let app = XCUIApplication.launchWithPhotos(); app.openTab("People")
        let maya = personRow(app, "Maya")
        let dad = personRow(app, "Dad")
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        let face = CGPoint(x: 0.25, y: 0.2)   // inside the face's upper left quarter, clear of the circle
        // The cover decodes off the main thread: wait for it to draw.
        waitForColour(app, maya, at: face, near: 0xC8893F)
        XCTAssertTrue(app.isNear(app.colour(of: maya, at: face), 0xC8893F), "Maya's cover fills her face")
        XCTAssertTrue([0xE3DCC6, 0xDDE2D3, 0xEADBCB].contains { app.isNear(app.colour(of: dad, at: face), $0) }, "Dad keeps his letter tile")
        XCTAssertEqual(maya.value as? String, "my sister", "the tile reads as before")
    }

    @MainActor
    func testAPhotoAddedOnThePageShowsOnTheTile() throws {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")])
        app.openEntityPage("Lena"); app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        let lena = personRow(app, "Lena")
        XCTAssertTrue(lena.waitForExistence(timeout: 5))
        waitForColour(app, lena, at: CGPoint(x: 0.25, y: 0.2), near: 0xE07A2E)
        XCTAssertTrue(app.isNear(app.colour(of: lena, at: CGPoint(x: 0.25, y: 0.2)), 0xE07A2E))
    }

    @MainActor
    func testNoTileOffersAPhotoWhenSomeHaveOne() {
        let app = XCUIApplication.launchWithPhotos(); app.openTab("People")
        XCTAssertTrue(app.any("people.grid").waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "photo")).count, 0)
    }

    @MainActor
    func testTheListKeepsTheCoverAtTheLargestTextSize() {
        let app = XCUIApplication.launchWithPhotos(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.openTab("People")
        XCTAssertTrue(app.any("people.list").waitForExistence(timeout: 5))
        let maya = personRow(app, "Maya")
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        // The row spans the screen; its face is the 52-point square at the leading edge, after the list's inset,
        // so the sample sits at the face's middle (at 0.04 it lands in the inset, on the screen's white).
        let face = CGPoint(x: 0.1, y: 0.5)
        waitForColour(app, maya, at: face, near: 0xC8893F)
        XCTAssertTrue(app.isNear(app.colour(of: maya, at: face), 0xC8893F))
    }

    /// Polls up to 10 seconds for the pixel to turn this colour; the assertion that follows still checks it.
    private func waitForColour(_ app: XCUIApplication, _ element: XCUIElement, at point: CGPoint, near colour: Int) {
        let deadline = Date().addingTimeInterval(10)
        while !app.isNear(app.colour(of: element, at: point), colour), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }
}
