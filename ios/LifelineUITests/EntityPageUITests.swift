import XCTest

/// S2: a person's page reads in the spec's order — the strip, what was said, often with, the
/// moments — and a page with nothing in it invites a story instead of listing empty sections.
final class EntityPageUITests: XCTestCase {

    @MainActor
    func testAPersonsPageReadsInTheSpecOrder() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Maya")
        XCTAssertEqual(app.any("entity.ownWords").label, "my sister")
        XCTAssertEqual(app.any("entity.strip").label, "In 4 moments, from 1999 to 2003")
        XCTAssertTrue(app.staticTexts["What you've said about them"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "entity.detail").allElementsBoundByIndex.map(\.label),
                       ["Two years younger than me", "She was always the brave one"])
        XCTAssertEqual(app.buttons.matching(identifier: "entity.oftenWith").allElementsBoundByIndex.map(\.label),
                       ["Dad, 3 moments together", "Alder Street, 2 moments together"])
        let moments = app.buttons.matching(identifier: "entity.moment")
        XCTAssertTrue(app.reveal(app.staticTexts["Moments with Maya"]))
        XCTAssertEqual(moments.count, 4)
        XCTAssertLessThan(app.any("entity.strip").frame.minY, app.buttons["entity.detail"].firstMatch.frame.minY)
        XCTAssertLessThan(app.buttons["entity.detail"].firstMatch.frame.minY, app.buttons["entity.oftenWith"].firstMatch.frame.minY)
        XCTAssertLessThan(app.buttons["entity.oftenWith"].firstMatch.frame.minY, moments.firstMatch.frame.minY)
        XCTAssertFalse(app.staticTexts["Jordan"].exists, "the owner is never often with anyone")
    }
    @MainActor
    func testOftenWithOpensThatPage() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Maya")
        app.buttons.matching(identifier: "entity.oftenWith").firstMatch.tap()
        let title = app.staticTexts["entity.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertEqual(title.label, "Dad")
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story about Dad")
    }
    @MainActor
    func testAPageWithOneMomentHasNoAxis() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Sam")
        XCTAssertEqual(app.any("entity.stripSentence").label, "In one moment, in 2012")
        XCTAssertFalse(app.any("entity.strip").exists)
        XCTAssertFalse(app.staticTexts["Often with"].exists, "absent, not empty")
    }
    @MainActor
    func testAPageWithNothingInvitesAStory() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Lena")
        XCTAssertEqual(app.any("entity.invite").label, "Stories you tell about Lena will show here.")
        for absent in ["What you've said about them", "Often with", "Moments with Lena"] { XCTAssertFalse(app.staticTexts[absent].exists) }
        XCTAssertFalse(app.any("entity.strip").exists || app.any("entity.stripSentence").exists)
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story about Lena")
    }
    @MainActor
    func testAddATagIsASmallPill() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Lena")
        let add = app.buttons["entity.addTag"]
        XCTAssertTrue(app.reveal(add))
        XCTAssertLessThanOrEqual(add.frame.height, 48)
        XCTAssertGreaterThan(add.frame.width, add.frame.height)
    }
}
