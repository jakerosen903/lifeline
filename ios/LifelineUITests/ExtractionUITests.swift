import XCTest

/// Cards, confirmation, people and the Settings key, with the scripted voice and extraction services.
final class ExtractionUITests: XCTestCase {
    @MainActor
    private func launchToHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.buttons["aboutYou.skip"].waitForExistence(timeout: 5))
        app.buttons["aboutYou.skip"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    func testMemoryCardAppearsAndAddsAMemory() {
        let app = launchToHome()
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.staticTexts["Sounds like a memory"].waitForExistence(timeout: 15), "a memory card should appear")
        let blueDoorCard = app.staticTexts.matching(identifier: "card.title").matching(NSPredicate(format: "label == %@", "The blue door")).firstMatch
        XCTAssertTrue(blueDoorCard.exists)
        app.buttons["card.add"].firstMatch.tap()
        XCTAssertFalse(blueDoorCard.waitForExistence(timeout: 2), "the card goes once added")
        app.buttons["session.stop"].tap()

        XCTAssertTrue(app.buttons["timeline.sessions"].waitForExistence(timeout: 10))
        app.buttons["timeline.sessions"].tap()
        let row = app.buttons["home.sessionRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let memory = app.buttons["detail.memory"].firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 5), "the accepted memory shows in the session's detail")
        XCTAssertTrue(memory.label.contains("The blue door"))
    }

    @MainActor
    func testWhoIsThisResolvesToANewPerson() {
        let app = launchToHome()
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.staticTexts["Who's this?"].waitForExistence(timeout: 20), "a who-is-this card should appear")
        app.buttons["card.newPerson"].firstMatch.tap()
        app.buttons["session.stop"].tap()
        XCTAssertTrue(app.buttons["home.people"].waitForExistence(timeout: 5))
        app.buttons["home.people"].tap()
        let person = app.buttons["people.row"].firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        XCTAssertTrue(person.label.contains("Maya"))
        XCTAssertTrue(person.label.contains("my sister"), "the kin phrase said with the name shows as the relation: \(person.label)")

        person.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue + "ra")   // Maya -> Mayra
        alert.buttons["Save"].firstMatch.tap()
        let renamed = app.buttons["people.row"].firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        XCTAssertTrue(renamed.label.contains("Mayra") && renamed.label.contains("Maya"), "new name shown, old spelling kept: \(renamed.label)")
    }

    @MainActor
    func testPendingCardsShowInSessionDetail() {
        let app = launchToHome()
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.staticTexts["Sounds like a memory"].waitForExistence(timeout: 15))
        app.buttons["session.stop"].tap()
        XCTAssertTrue(app.buttons["timeline.sessions"].waitForExistence(timeout: 10))
        app.buttons["timeline.sessions"].tap()
        let row = app.buttons["home.sessionRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["Sounds like a memory"].waitForExistence(timeout: 5), "an unacted card waits in the detail screen")
    }

    @MainActor
    func testSettingsSavesAKeyState() {
        let app = launchToHome()
        app.buttons["home.settings"].tap()
        let field = app.textFields["settings.apiKey"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("sk-ant-api03-" + String(repeating: "a", count: 40))
        XCTAssertTrue((field.value as? String)?.hasPrefix("sk-ant") == true, "typed text reached the field: \(String(describing: field.value))")
        XCTAssertTrue(app.buttons["settings.apiKeySave"].isEnabled, "a well-formed key enables Save")
        field.typeText("\n")   // Return saves, like the button
        let status = app.staticTexts["settings.apiKeyStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let saved = NSPredicate(format: "label == %@", "Key saved")
        expectation(for: saved, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["settings.apiKeyRemove"].exists, "a saved key can be removed")
    }
}
