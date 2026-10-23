import XCTest

/// M4: the session's two views, the offers, correction with Undo, the landing and its choices,
/// resume after a kill, and first open. All with the scripted services and short arc numbers.
final class LandingUITests: XCTestCase {
    private static let disclosureText = "Thank you for telling me that. You can stop here, or keep going. It is your choice. If you need to talk to someone now, call or text 988 (Suicide and Crisis Lifeline, US)."

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func launchToTimeline(arguments: [String] = []) -> XCUIApplication {
        let app = launch(arguments: arguments)
        app.skipFirstOpen()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        return app
    }

    /// Start a quick story in the review view, keep the first card, Finish, and stop on the landing.
    @MainActor
    private func recordToLanding(_ app: XCUIApplication) {
        app.startSession()
        let add = app.buttons["card.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.staticTexts["landing.headline"].waitForExistence(timeout: 10))
    }

    // MARK: - The session

    @MainActor
    func testFinishOpensTheLandingAtOnceAndDoneLands() {
        let app = launchToTimeline()
        app.startSession()
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["session.finish"].tap()
        let headline = app.staticTexts["landing.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 3), "the landing appears at once, not after sorting")
        XCTAssertEqual(headline.label, "Your first story is saved. Hear it back.")
        XCTAssertTrue(app.any("landing.row").waitForExistence(timeout: 10), "moments fill in while sorting finishes")
        let sorting = app.any("landing.stillSorting")
        let deadline = Date().addingTimeInterval(15)
        while sorting.exists && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        XCTAssertFalse(sorting.exists, "Still sorting clears on its own")
        XCTAssertTrue(app.buttons["landing.play"].firstMatch.exists)
        app.buttons["landing.done"].tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10))
        XCTAssertTrue(app.reveal(app.any("timeline.waiting")), "the possible memories wait on the timeline")
    }

    @MainActor
    func testListenViewIsQuietAndCountsPossibleMemories() {
        let app = launchToTimeline()
        app.startSession(review: false)
        let count = app.staticTexts["session.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.hasSuffix("possible memories") || count.label.hasSuffix("possible memory"), count.label)
        let two = NSPredicate(format: "label == %@", "2 possible memories")   // the blue door and Maya's climb
        expectation(for: two, evaluatedWith: count).fulfillmentTimeout(15)
        XCTAssertFalse(app.any("card.memory").exists, "the Listen view shows no cards")
        app.openReview()
        XCTAssertTrue(app.any("card.memory").waitForExistence(timeout: 5), "the review view shows the card")
        app.finishSession()
    }

    @MainActor
    func testQuickStoryNeverSeesTheClock() {
        let app = launchToTimeline()
        app.startSession(review: false)
        XCTAssertEqual(app.staticTexts["session.kind"].label, "You chose a quick story")
        RunLoop.current.run(until: Date().addingTimeInterval(13))   // past the settle-in planned length in test config
        XCTAssertFalse(app.any("session.wrapUp").exists, "a quick story is never asked to wrap up")
        XCTAssertFalse(app.any("session.nextPrompt").exists, "a quick story is one prompt")
        XCTAssertTrue(app.buttons["session.finish"].exists, "and it is still recording")
        app.finishSession()
    }

    @MainActor
    func testSettleInOffersTheNextQuestionAfterQuiet() {
        let app = launchToTimeline()
        XCTAssertTrue(app.waitHittable(app.buttons["home.settleIn"], timeout: 5))
        app.buttons["home.settleIn"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["session.kind"].label, "You chose settling in")
        let offer = app.any("session.nextPrompt")
        XCTAssertTrue(offer.waitForExistence(timeout: 15), "after a story and a quiet moment the next question is offered")
        XCTAssertNotEqual(app.staticTexts["session.nextPromptText"].label, app.staticTexts["session.prompt"].label)
        app.buttons["session.nextPromptLater"].tap()
        XCTAssertFalse(offer.waitForExistence(timeout: 1))
        app.finishSession()
    }

    @MainActor
    func testWrapUpOffersAndKeepGoingContinues() {
        let app = launchToTimeline()
        XCTAssertTrue(app.waitHittable(app.buttons["home.settleIn"], timeout: 5))
        app.buttons["home.settleIn"].tap()
        let wrapUp = app.any("session.wrapUp")
        XCTAssertTrue(wrapUp.waitForExistence(timeout: 14), "settling in is offered a wrap-up at the planned length")
        app.buttons["session.keepGoing"].tap()
        XCTAssertFalse(wrapUp.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["session.finish"].exists, "recording continues")
        XCTAssertTrue(wrapUp.waitForExistence(timeout: 10), "offered again after the grace, never a stop")
        app.finishSession()
    }

    @MainActor
    func testPauseAndResumeKeepRecording() {
        let app = launchToTimeline(arguments: ["-uiTesting-slow"])
        app.startSession()
        let pause = app.buttons["session.pause"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: pause).fulfillmentTimeout(5)
        pause.tap()
        app.openListen()
        let recording = app.any("session.recording")
        XCTAssertTrue(recording.waitForExistence(timeout: 3))
        XCTAssertTrue(recording.label.contains("Paused"), recording.label)
        app.openReview()
        let before = app.staticTexts.matching(identifier: "session.segment").count
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertEqual(app.staticTexts.matching(identifier: "session.segment").count, before, "nothing arrives while paused")
        pause.tap()   // Resume
        let deadline = Date().addingTimeInterval(10)
        var after = before
        while after <= before && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            after = app.staticTexts.matching(identifier: "session.segment").count
        }
        XCTAssertGreaterThan(after, before, "recording goes on after Resume (had \(before) before the pause)")
        app.finishSession()
    }

    // MARK: - Correction

    @MainActor
    func testDismissShowsUndo() {
        let app = launchToTimeline()
        app.startSession()
        let dismiss = app.buttons["card.dismiss"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 15))
        dismiss.tap()
        XCTAssertTrue(app.staticTexts["card.dismissedNotice"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["card.dismissedNotice"].label, "Suggestion dismissed. Your recording is untouched.")
        app.buttons["card.undo"].tap()
        let title = app.staticTexts.matching(identifier: "card.title").matching(NSPredicate(format: "label == %@", "The blue door")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Undo brings the card back exactly")
        XCTAssertFalse(app.staticTexts["card.dismissedNotice"].exists)
        app.finishSession()
    }

    @MainActor
    func testChangeTitleFromTheCard() {
        let app = launchToTimeline()
        app.startSession()
        let change = app.buttons["card.change"].firstMatch
        XCTAssertTrue(change.waitForExistence(timeout: 15))
        change.tap()
        let field = app.textViews["change.title"].exists ? app.textViews["change.title"] : app.textFields["change.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()   // cursor at the end
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "Grandma's door")
        app.buttons["change.saveTitle"].tap()
        XCTAssertTrue(app.any("change.later").exists, "the rows that wait are visible, disabled")
        app.buttons["change.done"].tap()
        app.buttons["session.finish"].tap()
        let renamed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Grandma's door")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 10), "the landing shows the new title")
        app.buttons["landing.done"].tap()
    }

    @MainActor
    func testCheckThisTagOnAnInferredRange() {
        let app = launchToTimeline()
        recordToLanding(app)
        app.buttons["landing.done"].tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.settings"], timeout: 10))
        app.buttons["home.settings"].tap()
        let toggle = app.switches["aboutYou.hasBirthday"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(app.datePickers["aboutYou.birthday"].waitForExistence(timeout: 3))
        app.buttons["aboutYou.continue"].tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 5))
        let tag = app.any("card.checkThis")
        XCTAssertTrue(app.reveal(tag), "an inferred range carries a Check this tag")
        XCTAssertTrue(tag.label.hasPrefix("Check this: around"), tag.label)
    }

    // MARK: - Heavy moments

    @MainActor
    func testDisclosureCardShowsVerbatimAndLandsGently() {
        let app = launchToTimeline(arguments: ["-uiTesting-heavy"])
        app.startSession()
        XCTAssertTrue(app.any("card.memory").waitForExistence(timeout: 15), "the first segment's card shows as usual")
        let card = app.any("session.disclosure")
        XCTAssertTrue(card.waitForExistence(timeout: 15), "the second segment is flagged")
        XCTAssertEqual(app.staticTexts["session.disclosureText"].label, Self.disclosureText, "verbatim, never the model's words")
        XCTAssertTrue(app.links["session.crisisLine"].exists || app.buttons["session.crisisLine"].exists)
        let who = app.descendants(matching: .any).matching(identifier: "card.whoIsThis").count
        let memories = app.descendants(matching: .any).matching(identifier: "card.memory").count
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "card.whoIsThis").count, who, "no new who-is-this after a heavy moment")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "card.memory").count, memories, "no new memory card either")
        app.buttons["session.disclosureOkay"].tap()
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.staticTexts["landing.closing"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["landing.closing"].label, "Thank you. That's enough for today.")
        XCTAssertEqual(app.staticTexts["landing.headline"].label, "Your recording is saved.")
        app.buttons["landing.done"].tap()
    }

    // MARK: - The landing's choices

    @MainActor
    func testHideTodayRemovesFromTimelineNotSessions() {
        let app = launchToTimeline()
        recordToLanding(app)
        app.buttons["landing.hide"].tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10))
        XCTAssertFalse(app.buttons["timeline.memory"].firstMatch.waitForExistence(timeout: 2), "hidden from everyday browsing")
        app.buttons["timeline.showHidden"].tap()
        XCTAssertTrue(app.reveal(app.buttons["timeline.memory"].firstMatch), "the Hidden filter shows it")
        app.buttons["timeline.sessions"].tap()
        XCTAssertTrue(app.buttons["home.sessionRow"].firstMatch.waitForExistence(timeout: 5), "Sessions still has it")
        app.buttons["home.sessionRow"].firstMatch.tap()
        XCTAssertTrue(app.reveal(app.buttons["detail.memory"].firstMatch))
    }

    @MainActor
    func testDeleteTodayAsksThenRemovesEverything() {
        let app = launchToTimeline()
        recordToLanding(app)
        app.buttons["landing.delete"].tap()
        let confirm = app.buttons["Delete the recording and everything from it"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "it asks first")
        confirm.tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10))
        XCTAssertFalse(app.buttons["timeline.memory"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.any("timeline.waiting").exists)
        app.buttons["timeline.sessions"].tap()
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 5), "the recording is gone")
    }

    // MARK: - Resume and first open

    @MainActor
    func testResumeAfterKillOpensTheLanding() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lifeline-resume-\(UUID().uuidString)").path
        let app = launchToTimeline(arguments: ["-uiTesting-db", dir])
        app.startSession()
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15))
        app.terminate()
        let again = launch(arguments: ["-uiTesting-db", dir])
        let headline = again.staticTexts["landing.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 10), "a session cut short resumes at its landing")
        XCTAssertEqual(headline.label, "Your first story is saved. Hear it back.")
        XCTAssertTrue(again.any("landing.row").waitForExistence(timeout: 10), "what was captured is there")
        again.buttons["landing.done"].tap()
        XCTAssertTrue(again.waitHittable(again.buttons["home.start"], timeout: 10))
        again.terminate()
        let third = launch(arguments: ["-uiTesting-db", dir])
        XCTAssertTrue(third.waitHittable(third.buttons["home.start"], timeout: 10), "once landed, it does not come back")
    }

    @MainActor
    func testFirstOpenOffersTwoWaysIn() {
        let app = launch()
        XCTAssertTrue(app.buttons["firstOpen.quick"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["firstOpen.settleIn"].exists)
        XCTAssertTrue(app.buttons["firstOpen.context"].exists, "context is offered, not required")
        app.buttons["firstOpen.settleIn"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 10), "a story starts straight away")
        XCTAssertEqual(app.staticTexts["session.kind"].label, "You chose settling in")
        app.openReview()
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.buttons["landing.tellAnother"].waitForExistence(timeout: 10), "the first payoff offers another")
        app.buttons["landing.done"].tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10))
    }
}

private extension XCTestExpectation {
    func fulfillmentTimeout(_ seconds: TimeInterval) {
        let result = XCTWaiter().wait(for: [self], timeout: seconds)
        XCTAssertEqual(result, .completed, "timed out waiting for \(expectationDescription)")
    }
}
