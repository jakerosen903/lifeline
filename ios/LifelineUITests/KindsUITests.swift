import XCTest

/// M7, PR A: a fact is not a moment. It lands under About, never on the shelf, and "What is
/// this?" moves it back.
final class KindsUITests: XCTestCase {
    @MainActor
    func testAFactAboutTheHouseLandsOnItsPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-fact"]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        let add = app.buttons["card.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15), "the fact card arrives")
        XCTAssertTrue(app.staticTexts["Something about your life"].firstMatch.exists, "the card says what it heard")
        add.tap()
        app.finishSession()

        // The fact is a detail of "the house" (S2 decision 17): not on Timeline, not on You, on the house's page.
        XCTAssertTrue(app.any("timeline.summary").waitForExistence(timeout: 5))
        // The List is lazy: scroll to its last row, the "Who's this?" card for Maya at the foot of the waiting cards,
        // so an About section below it would be in the tree.
        app.scrollTimelineToItsEnd(last: app.buttons["card.notAPerson"].firstMatch)
        XCTAssertFalse(app.any("timeline.about").exists, "no About section on Timeline")
        XCTAssertFalse(app.buttons["row.addDate"].exists, "nobody asks when a fact happened")
        XCTAssertFalse(app.any("timeline.shelf").exists, "the shelf holds moments only")
        app.openTab("You")
        // Nothing else is told, so a wrongly placed house fact would be the lead, not a `you.line`: assert the empty page.
        XCTAssertTrue(app.any("you.invite").waitForExistence(timeout: 10), "a fact about the house is not on You: You still invites a story")
        XCTAssertFalse(app.any("you.lead").exists, "and nothing leads")
        XCTAssertFalse(app.buttons.matching(identifier: "you.line").firstMatch.exists, "and no line shows")
        app.openTab("Things")
        let house = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "the house")).firstMatch
        XCTAssertTrue(house.waitForExistence(timeout: 5))
        house.tap()
        let row = app.buttons.matching(identifier: "entity.detail").matching(NSPredicate(format: "label CONTAINS %@", "The house had a blue door")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the fact is a detail on the page of the house")

        row.tap()
        XCTAssertTrue(app.any("memory.kind").waitForExistence(timeout: 5), "the memory screen shows the kind, not a date")
        XCTAssertFalse(app.buttons["memory.range"].exists)
        app.buttons["memory.change"].tap()
        XCTAssertTrue(app.buttons["change.done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["change.tellMeWhen"].exists, "no Tell me when on a fact")
        let kind = app.buttons["change.kind"]
        XCTAssertTrue(app.reveal(kind), "What is this? sits at the bottom of the sheet")
        kind.tap()
        let moment = app.buttons["change.kind.event"]
        XCTAssertTrue(moment.waitForExistence(timeout: 5))
        moment.tap()
        app.buttons["change.done"].tap()
        XCTAssertTrue(app.buttons["memory.range"].waitForExistence(timeout: 5), "a moment shows its when again")
        app.buttons["memory.change"].tap()
        XCTAssertTrue(app.buttons["change.tellMeWhen"].waitForExistence(timeout: 5), "a moment can be dated")
        app.buttons["change.done"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        app.openTab("Timeline")
        XCTAssertTrue(app.reveal(app.any("timeline.shelf")), "back as a moment, it sits on the shelf")
        XCTAssertTrue(app.reveal(app.buttons["row.addDate"].firstMatch), "and Add a date is offered")
        XCTAssertFalse(app.any("timeline.about").exists)
    }
}
