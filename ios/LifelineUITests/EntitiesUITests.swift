import XCTest

/// M7, PR B: entity cards, pages with details above moments, ideas in order, a domain filter.
final class EntitiesUITests: XCTestCase {
    /// Records the entity script and keeps every memory card, then leaves the landing.
    @MainActor
    private func launchAndRecord() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-entities"]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        for _ in 0..<4 {
            let add = app.buttons["card.add"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 20), "a memory card arrives")
            add.tap()
        }
        XCTAssertTrue(app.any("card.entity").waitForExistence(timeout: 20), "the shed arrives as a card of its own")
        app.finishSession()
        return app
    }

    @MainActor
    private func openEntities(_ app: XCUIApplication, segment: String) {
        app.buttons["timeline.entities"].tap()
        let control = app.segmentedControls["entities.type"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.buttons[segment].tap()
    }

    @MainActor
    func testEntityPagesShowDetailsAboveMomentsAndIdeasInOrder() {
        let app = launchAndRecord()

        // The thing card waits on the timeline; Keep opens its page.
        let keep = app.buttons["card.entityKeep"].firstMatch
        XCTAssertTrue(app.reveal(keep))
        keep.tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entity.title"].label, "the old shed")
        XCTAssertTrue(app.staticTexts["no dates yet"].exists, "nobody asks when")
        app.navigationBars.buttons.firstMatch.tap()

        // The house: the detail first, the moment below, its span from the moment.
        openEntities(app, segment: "Things")
        let house = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "the house")).firstMatch
        XCTAssertTrue(house.waitForExistence(timeout: 5))
        house.tap()
        let detail = app.buttons["entity.detail"].firstMatch
        let moment = app.buttons["entity.moment"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5) && moment.exists)
        XCTAssertEqual(detail.label, "The house had a blue door")
        XCTAssertEqual(moment.label, "We painted the house")
        XCTAssertLessThan(detail.frame.minY, moment.frame.minY, "details first, moments below")
        XCTAssertEqual(app.staticTexts["entity.span"].label, "in 1995")
        app.navigationBars.buttons.firstMatch.tap()

        // An idea told twice reads in order.
        app.segmentedControls["entities.type"].buttons["Ideas"].tap()
        let idea = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "hard work")).firstMatch
        XCTAssertTrue(idea.waitForExistence(timeout: 5))
        idea.tap()
        let lines = app.buttons.matching(identifier: "entity.moment")
        XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.element(boundBy: 0).label, "Hard work was everything")
        XCTAssertEqual(lines.element(boundBy: 1).label, "I saw hard work differently")
    }

    @MainActor
    func testThingsFilterByDomainTag() {
        let app = launchAndRecord()
        let keep = app.buttons["card.entityKeep"].firstMatch
        XCTAssertTrue(app.reveal(keep))
        keep.tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        openEntities(app, segment: "Things")
        let rows = app.buttons.matching(identifier: "entities.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2, "the house and the shed")
        app.buttons["entities.tagFilter"].tap()
        app.buttons["entities.tag.home"].tap()
        XCTAssertTrue(rows.matching(NSPredicate(format: "label == %@", "the house")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "only what was heard as home")
    }
}
