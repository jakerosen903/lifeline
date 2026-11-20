import XCTest

/// The Things shelf (S7): tiles grouped by life period, a key photo or the person's words on each,
/// and a guess said in words. The seed is `-uiTesting-seedThings` (see `UITestSeed.writeThings`).
final class ThingsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Waits up to 5 seconds for the record bar to read `label`.
    private func waitForBarLabel(_ app: XCUIApplication, _ label: String) -> Bool {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: app.buttons["home.start"])
        return XCTWaiter().wait(for: [match], timeout: 5) == .completed
    }

    @MainActor func testThingsIsAShelfGroupedByPeriod() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertEqual(app.shelfLabels(), ["Childhood · by your age", "The piano", "The red bike", "Dad's Volvo",
                                           "Twenties · by your age", "The radiator",
                                           "Not placed in time yet", "Grandpa's watch", "The blue kite",
                                           "The enormous green armchair that came with the flat on Hemenway Street", "The guitar"])
        XCTAssertTrue(app.navigationBars["Things"].exists)
    }

    @MainActor func testAThingShowsOnceInItsFirstPeriod() {
        let app = XCUIApplication.launchWithThings()
        let labels = app.shelfLabels()
        XCTAssertEqual(labels.filter { $0 == "The red bike" }.count, 1)
        XCTAssertFalse(labels.contains("Teens · by your age"), "its 2004 moment does not open a Teens group")
    }

    @MainActor func testATileWithAPhotoShowsThePhotoAndTheCount() {
        let app = XCUIApplication.launchWithThings()
        let bike = app.shelfTile("The red bike")
        XCTAssertTrue(bike.waitForExistence(timeout: 5))
        XCTAssertEqual(bike.value as? String, "2 moments")
        XCTAssertTrue(app.isNear(app.colour(of: bike, at: CGPoint(x: 0.5, y: 0.3)), 0xC8893F), "the key photo fills the top")
    }

    @MainActor func testATileWithoutAPhotoShowsTheQuote() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertEqual(app.shelfTile("Dad's Volvo").value as? String, "1 moment. “It smelled like oranges and wet dog”")
        XCTAssertEqual(app.shelfTile("The guitar").value as? String, "“I never learned more than three chords”", "a fact gives a quote, and no count")
        XCTAssertTrue(app.isNear(app.colour(of: app.shelfTile("Dad's Volvo"), at: CGPoint(x: 0.95, y: 0.05)), 0xECE3D2), "the sand face")
    }

    @MainActor func testAGuessedDateSaysSo() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertEqual(app.shelfTile("The radiator").value as? String, "1 moment. Placed by a guess")
        XCTAssertFalse((app.shelfTile("The red bike").value as? String ?? "x guess").contains("guess"))
        XCTAssertFalse((app.shelfTile("The piano").value as? String ?? "x guess").contains("guess"), "a stated span is not a guess")
    }

    @MainActor func testAHiddenMemoryGivesNoQuoteAndNoPlace() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertFalse((app.shelfTile("The radiator").value as? String ?? "x clanked").contains("clanked"), "the hidden fact gives no quote")
        let kite = app.shelfTile("The blue kite")
        XCTAssertTrue(app.reveal(kite))
        XCTAssertEqual(kite.value as? String, "", "the hidden moment gives no count and no period")
    }

    @MainActor func testAHiddenThingIsNotOnTheShelf() {
        XCTAssertFalse(XCUIApplication.launchWithThings().shelfLabels().contains("The shoebox"))
    }

    @MainActor func testAPhotoThatCannotLoadKeepsTheTile() {
        let app = XCUIApplication.launchWithThings()
        let watch = app.shelfTile("Grandpa's watch")
        XCTAssertTrue(app.reveal(watch))
        XCTAssertEqual(watch.value as? String, "1 moment")
        XCTAssertTrue(app.isNear(app.colour(of: watch, at: CGPoint(x: 0.5, y: 0.3)), 0xECE3D2), "sand where the photo would be")
    }

    @MainActor func testTilesInARowAreOneHeight() {
        let app = XCUIApplication.launchWithThings()
        let piano = app.shelfTile("The piano"), bike = app.shelfTile("The red bike")
        XCTAssertTrue(piano.waitForExistence(timeout: 5))
        XCTAssertEqual(piano.frame.minY, bike.frame.minY, accuracy: 1)
        XCTAssertEqual(piano.frame.height, bike.frame.height, accuracy: 1)
        XCTAssertLessThan(piano.frame.maxX, bike.frame.minX, "two columns")
    }

    @MainActor func testATapOpensThePageAndTheBarNamesIt() {
        let app = XCUIApplication.launchWithThings()
        app.shelfTile("The red bike").tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entity.title"].label, "The red bike")
        XCTAssertTrue(waitForBarLabel(app, "Tell a story about The red bike"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Things"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForBarLabel(app, "Tell a story"))
    }

    @MainActor func testTheShelfIsFlatWithNoPlacedThing() {
        let app = XCUIApplication.launchWithThings(["-uiTesting-thingsUndatedOnly"])
        XCTAssertTrue(app.shelfTile("Grandpa's watch").waitForExistence(timeout: 5))
        XCTAssertFalse(app.any("things.period").exists)
        XCTAssertFalse(app.any("things.unplaced").exists, "a flat grid has no heading")
    }

    @MainActor func testAnEmptyShelfSaysWhereThingsComeFrom() {
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting"]; app.launch(); app.skipFirstOpen(); app.openTab("Things")
        XCTAssertTrue(app.any("things.empty").waitForExistence(timeout: 5))
        XCTAssertEqual(app.any("things.empty").label, "Nothing yet. They appear as you tell stories.")
        XCTAssertFalse(app.buttons["entities.row"].exists)
    }

    @MainActor func testNoCountOrAddControlOnTheShelf() {
        let app = XCUIApplication.launchWithThings()
        XCTAssertTrue(app.shelfTile("The piano").waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Add")).count, 0)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "things you")).count, 0)
    }

    @MainActor func testATileReadsAsOneButton() {
        let app = XCUIApplication.launchWithThings()
        let volvo = app.shelfTile("Dad's Volvo")
        XCTAssertTrue(volvo.waitForExistence(timeout: 5))
        XCTAssertEqual(volvo.elementType, .button)
        XCTAssertEqual(volvo.label, "Dad's Volvo")
        // Ruling R3: XCUITest lists a button's texts even when VoiceOver reads one element, so this checks
        // what VoiceOver reads (the label and the spoken value) and that the tile is one button.
        XCTAssertEqual(volvo.value as? String, "1 moment. “It smelled like oranges and wet dog”", "the count and the quote are the spoken value")
        XCTAssertEqual(volvo.buttons.count, 0, "no button inside the tile")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Dad's Volvo")).count, 1, "one button for the tile")
        let bike = app.shelfTile("The red bike")
        XCTAssertTrue(bike.exists)
        XCTAssertFalse(bike.images.firstMatch.exists, "no photo is described")
    }

    @MainActor func testTheLargestTextIsOneColumnAndNothingIsCut() {
        let app = XCUIApplication.launchWithThings(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let piano = app.shelfTile("The piano"), bike = app.shelfTile("The red bike")
        XCTAssertTrue(piano.waitForExistence(timeout: 5) && app.reveal(bike))
        XCTAssertEqual(piano.frame.minX, bike.frame.minX, accuracy: 1, "one column")
        XCTAssertGreaterThanOrEqual(piano.frame.height, 44)
        // The grid is lazy: the piano leaves the tree when the chair is scrolled in, so keep its title's height now.
        let pianoTitleHeight = piano.staticTexts["The piano"].frame.height
        XCTAssertGreaterThan(pianoTitleHeight, 0)
        let chairTitle = "The enormous green armchair that came with the flat on Hemenway Street"
        let chair = app.shelfTile(chairTitle)
        XCTAssertTrue(app.reveal(chair, swipes: 20))
        XCTAssertLessThanOrEqual(chair.frame.maxX, app.windows.firstMatch.frame.maxX)
        // A text's label is always its full string, so no assertion here can see a cut title. This checks that the
        // long title wraps to more lines than a short one; that nothing is cut is on the device checklist.
        XCTAssertGreaterThan(chair.staticTexts[chairTitle].frame.height, pianoTitleHeight, "the long title wraps")
    }
}
