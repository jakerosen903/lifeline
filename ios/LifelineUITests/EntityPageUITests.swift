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
        XCTAssertLessThan(app.any("entity.strip").frame.minY, app.buttons["entity.detail"].firstMatch.frame.minY)
        XCTAssertLessThan(app.buttons["entity.detail"].firstMatch.frame.minY, app.buttons["entity.oftenWith"].firstMatch.frame.minY)
        XCTAssertLessThan(app.buttons["entity.oftenWith"].firstMatch.frame.minY, moments.firstMatch.frame.minY)
        XCTAssertFalse(app.staticTexts["Jordan"].exists, "the owner is never often with anyone")
        // A List holds only the rows on screen: scroll to the last moment before reading them all.
        XCTAssertTrue(app.reveal(moments.matching(NSPredicate(format: "label == %@", "Maya's graduation")).firstMatch))
        XCTAssertEqual(moments.allElementsBoundByIndex.map(\.label),
                       ["The tree house", "Learning to swim", "The science fair", "Maya's graduation"], "oldest first")
    }
    @MainActor
    func testThePagesControlsAreFullSize() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Maya")
        XCTAssertGreaterThanOrEqual(app.buttons["entity.play"].frame.height, 44)
        let chips = app.buttons.matching(identifier: "entity.oftenWith").allElementsBoundByIndex
        XCTAssertEqual(chips.count, 2)
        for chip in chips { XCTAssertGreaterThanOrEqual(chip.frame.height, 44, chip.label) }
    }
    /// A session lands under a full-screen cover, so the page under it gets no onAppear. The scripted
    /// session names Maya ("before Maya climbed it", in 1998), never Lena, so the test starts on Maya's page.
    @MainActor
    func testThePageReadsWhatASessionAddedWhenItCloses() {
        let app = XCUIApplication.launchWithPeople(); app.openEntityPage("Maya")
        XCTAssertEqual(app.any("entity.strip").label, "In 4 moments, from 1999 to 2003")
        app.startSession()
        let add = app.buttons["card.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), "a memory card arrives")
        var kept = 0
        while add.waitForExistence(timeout: 8), kept < 3 { add.tap(); kept += 1 }
        app.finishSession()
        XCTAssertEqual(app.staticTexts["entity.title"].label, "Maya", "the landing closes onto her page")
        let strip = app.any("entity.strip")
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "In 5 moments, from 1998 to 2003"), object: strip)
        XCTAssertEqual(XCTWaiter().wait(for: [updated], timeout: 5), .completed, "the strip counts the new moment: \(strip.label)")
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
