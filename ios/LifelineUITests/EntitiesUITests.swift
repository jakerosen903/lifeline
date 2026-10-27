import XCTest

/// M7, PR B: entity cards, pages with details above moments, ideas in order, a domain filter.
final class EntitiesUITests: XCTestCase {
    /// Records the entity script and keeps every memory card, then leaves the landing. Every thing
    /// and idea in the script is named by a memory, so Keep links it and no chip asks (a mention
    /// that a memory carries is a record, not a question).
    @MainActor
    private func launchAndRecord() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-entities"]
        app.launch()
        app.skipFirstOpen()
        app.startSession()
        for _ in 0..<5 {
            let add = app.buttons["card.add"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 20), "a memory card arrives")
            add.tap()
        }
        XCTAssertFalse(app.any("card.followUp").exists, "nothing in the script is a question")
        XCTAssertFalse(app.staticTexts["entity.title"].exists, "Keep never leaves the session")
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

        // The shed was linked by its memory's Keep; its page is in Things.
        openEntities(app, segment: "Things")
        let shed = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "the old shed")).firstMatch
        XCTAssertTrue(shed.waitForExistence(timeout: 5))
        shed.tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entity.title"].label, "the old shed")
        XCTAssertTrue(app.staticTexts["no dates yet"].exists, "nobody asks when")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.segmentedControls["entities.type"].waitForExistence(timeout: 5))

        // The house: the detail first, the moment below, its span from the moment.
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

        // Two ideas that share words are two ideas: each Keep makes its own, reused by id only.
        app.segmentedControls["entities.type"].buttons["Ideas"].tap()
        let ideas = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "hard work"))
        XCTAssertTrue(ideas.firstMatch.waitForExistence(timeout: 5))
        let both = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: ideas)
        XCTAssertEqual(XCTWaiter().wait(for: [both], timeout: 10), .completed, "two ideas, not one merged by title")
        var told: [String] = []
        for index in 0..<2 {
            ideas.element(boundBy: index).tap()
            let lines = app.buttons.matching(identifier: "entity.moment")
            XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(lines.count, 1, "each idea holds the one moment that named it")
            told.append(lines.firstMatch.label)
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(ideas.firstMatch.waitForExistence(timeout: 5))
        }
        XCTAssertEqual(Set(told), ["Hard work was everything", "I saw hard work differently"])
    }

    @MainActor
    func testThingsFilterByDomainTag() {
        let app = launchAndRecord()
        // Keep linked both things; Things lists them.
        openEntities(app, segment: "Things")
        let rows = app.buttons.matching(identifier: "entities.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2, "the house and the shed")
        XCTAssertFalse(app.buttons["entities.tagFilter"].exists, "Keep tags nothing, so there is nothing to filter by yet")

        // A tag exists only because the owner tapped it in: tag the house "home" on its page.
        rows.matching(NSPredicate(format: "label == %@", "the house")).firstMatch.tap()
        let addTag = app.buttons["entity.addTag"]
        XCTAssertTrue(app.reveal(addTag))
        addTag.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("home")
        app.alerts.buttons["Add"].firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["entities.tagFilter"].waitForExistence(timeout: 5))
        app.buttons["entities.tagFilter"].tap()
        app.buttons["entities.tag.home"].tap()
        XCTAssertTrue(rows.matching(NSPredicate(format: "label == %@", "the house")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "only what was tagged home")
    }
}
