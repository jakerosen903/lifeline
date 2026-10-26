import XCTest

/// M7, PR A: a fact is not a moment. It lands under About, never on the shelf, and "What is
/// this?" moves it back.
final class KindsUITests: XCTestCase {
    @MainActor
    func testFactKeptLandsUnderAbout() {
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

        XCTAssertTrue(app.reveal(app.any("timeline.about")), "a kept fact sits under About")
        let row = app.buttons.matching(identifier: "about.row").matching(NSPredicate(format: "label CONTAINS %@", "The house had a blue door")).firstMatch
        XCTAssertTrue(app.reveal(row))
        XCTAssertFalse(app.buttons["row.addDate"].exists, "nobody asks when a fact happened")
        XCTAssertFalse(app.any("timeline.shelf").exists, "the shelf holds moments only")

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

        XCTAssertTrue(app.reveal(app.any("timeline.shelf")), "back as a moment, it sits on the shelf")
        XCTAssertTrue(app.reveal(app.buttons["row.addDate"].firstMatch), "and Add a date is offered")
        XCTAssertFalse(app.any("timeline.about").exists)
    }
}
