import XCTest

/// M8: what the interviewer says is shown where the person reads, and kept with the session.
/// In this PR playback is silent; the scripted voice reports each turn as played at once.
final class InterviewerUITests: XCTestCase {
    private static let spokenPastDisclosure = "Thank you for telling me that. You can stop here, or keep going. It is your choice."
    private static let earlyWindDown = "We can leave this here and come back whenever you want."

    @MainActor
    private func launchToTimeline(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        app.skipFirstOpen()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        return app
    }

    /// The text element with this identifier and exactly this label.
    @MainActor
    private func text(_ app: XCUIApplication, _ identifier: String, _ label: String) -> XCUIElement {
        app.staticTexts.matching(identifier: identifier).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// From the timeline, the newest session's detail, settled so it can scroll.
    @MainActor
    private func openSessionDetail(_ app: XCUIApplication) {
        app.buttons["timeline.sessions"].tap()
        let row = app.buttons["home.sessionRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        // Swiping while the push still animates can stall the runner for a minute waiting for idle.
        XCTAssertTrue(app.waitHittable(app.navigationBars.buttons["BackButton"], timeout: 5), "the detail is open")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    /// A quick story with nothing heavy: the opening is the only turn. It is stored, but the Listen view
    /// does not repeat it under the prompt, which already shows it.
    @MainActor
    func testTheOpeningIsStoredButNotRepeatedOnTheListenView() {
        let app = launchToTimeline()
        app.startSession(review: false)
        let prompt = app.staticTexts["session.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        let opening = prompt.label
        // Two segments in, the opening has long been played and stored.
        XCTAssertTrue(app.staticTexts["session.count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15))
        XCTAssertFalse(app.staticTexts["session.turn"].exists, "the opening is not shown as a turn")
        app.finishSession()

        openSessionDetail(app)
        XCTAssertTrue(app.reveal(text(app, "transcript.turn", opening)), "the opening is kept with the session")
    }

    /// The scripted extractor flags the second segment as a past disclosure. The card shows its fixed
    /// words; the interviewer says the spoken past text, then the wind-down line straight after it,
    /// so the Listen view ends on the wind-down line. The detail keeps both, in order, after the person's words.
    @MainActor
    func testScriptedDisclosureShowsAndStoresTheFixedText() {
        let app = launchToTimeline(arguments: ["-uiTesting-heavy"])
        app.startSession(review: false)
        XCTAssertTrue(app.any("session.disclosure").waitForExistence(timeout: 15), "the second segment is flagged")
        let turn = text(app, "session.turn", Self.earlyWindDown)
        XCTAssertTrue(turn.waitForExistence(timeout: 10), "the Listen view shows the newest turn")
        app.buttons["session.disclosureOkay"].tap()
        app.finishSession()

        openSessionDetail(app)
        let disclosure = text(app, "transcript.turn", Self.spokenPastDisclosure)
        XCTAssertTrue(app.reveal(disclosure), "the spoken disclosure is kept with the session")
        let windDown = text(app, "transcript.turn", Self.earlyWindDown)
        XCTAssertTrue(app.reveal(windDown), "and the wind-down line after it")
        XCTAssertLessThan(disclosure.frame.minY, windDown.frame.minY, "in the order they were said")
        let flagged = app.descendants(matching: .any).matching(identifier: "detail.segment")
            .matching(NSPredicate(format: "label CONTAINS %@", "climbed it in 1998")).firstMatch
        XCTAssertTrue(flagged.exists)
        XCTAssertLessThan(flagged.frame.minY, disclosure.frame.minY, "the turn follows the words it answers")
    }
}
