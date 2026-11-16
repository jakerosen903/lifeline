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
}
