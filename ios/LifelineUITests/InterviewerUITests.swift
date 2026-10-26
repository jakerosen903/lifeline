import XCTest

/// M8: what the interviewer says is shown where the person reads, and kept with the session.
/// The scripted voice plays each turn for 150 ms a word, and a scripted segment cuts the turn it starts in.
/// Under UI testing the app speaks only with `-uiTesting-speaks`.
final class InterviewerUITests: XCTestCase {
    private static let spokenPastDisclosure = "Thank you for telling me that. You can stop here, or keep going. It is your choice."
    private static let earlyWindDown = "We can leave this here and come back whenever you want."
    private static let wrapUp = "We can leave it here, or carry on."

    @MainActor
    private func launchToTimeline(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        app.skipFirstOpen()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func startSettleIn(_ app: XCUIApplication) {
        XCTAssertTrue(app.waitHittable(app.buttons["home.settleIn"], timeout: 5))
        app.buttons["home.settleIn"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 5))
    }

    /// The text element with this identifier and exactly this label.
    @MainActor
    private func text(_ app: XCUIApplication, _ identifier: String, _ label: String) -> XCUIElement {
        app.staticTexts.matching(identifier: identifier).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// The "cut off" mark sits on the line above a turn's words.
    @MainActor
    private func hasCutOffMark(_ app: XCUIApplication, above words: XCUIElement) -> Bool {
        app.staticTexts.matching(identifier: "transcript.turn.interrupted").allElementsBoundByIndex
            .contains { $0.frame.maxY <= words.frame.minY + 1 && words.frame.minY - $0.frame.maxY < 20 }
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
        let app = launchToTimeline(arguments: ["-uiTesting-speaks"])
        app.startSession(review: false)
        let prompt = app.staticTexts["session.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        let opening = prompt.label
        // Two segments in, the opening has long been played and stored.
        XCTAssertTrue(app.staticTexts["session.count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15))
        XCTAssertFalse(app.staticTexts["session.turn"].exists, "the opening is not shown as a turn")
        XCTAssertEqual(app.staticTexts["session.listenCopy"].label, "Take your time. Pauses are fine. I'll stay quiet while you talk.")
        app.finishSession()

        openSessionDetail(app)
        XCTAssertTrue(app.reveal(text(app, "transcript.turn", opening)), "the opening is kept with the session")
    }

    /// The scripted extractor flags the second segment as a past disclosure. The card shows its fixed
    /// words; the interviewer says the spoken past text, then the wind-down line straight after it,
    /// so the Listen view ends on the wind-down line. The detail keeps both, in order, after the person's words.
    @MainActor
    func testScriptedDisclosureShowsAndStoresTheFixedText() {
        let app = launchToTimeline(arguments: ["-uiTesting-speaks", "-uiTesting-heavy"])
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

    /// Slow script: the second segment is flagged as a past disclosure and the spoken text (17 words,
    /// about 2.5 s) starts after its pause. The third segment starts about 2.5 s after that pause, so it
    /// cuts the disclosure text. The detail marks that turn as cut off.
    /// Timing: the second segment's pause is at about 6.7 s, the third segment starts at about 9.2 s. The
    /// disclosure plays from its flags (pause + about 0.2 s of scripted sorting, or up to 1 s more while the
    /// last partial holds the floor) for 2.55 s, so it is still playing at 9.2 s if it started after about
    /// 6.6 s, which it must. A slow extraction is the risk: the disclosure is cut only while its flags arrive
    /// before about 9.2 s, a margin of about 2.3 s over the scripted 0.2 s.
    @MainActor
    func testSpeechDuringATurnMarksItInterrupted() {
        let app = launchToTimeline(arguments: ["-uiTesting-speaks", "-uiTesting-heavy", "-uiTesting-slow"])
        app.startSession(review: false)
        XCTAssertTrue(app.any("session.disclosure").waitForExistence(timeout: 20), "the second segment is flagged")
        // The wind-down line waits for the third segment's pause, then plays to its end (about 1.7 s).
        XCTAssertTrue(text(app, "session.turn", Self.earlyWindDown).waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        app.buttons["session.disclosureOkay"].tap()
        app.finishSession()

        openSessionDetail(app)
        let disclosure = text(app, "transcript.turn", Self.spokenPastDisclosure)
        XCTAssertTrue(app.reveal(disclosure), "the cut turn is kept with the session")
        XCTAssertTrue(hasCutOffMark(app, above: disclosure), "the disclosure text is marked as cut off")
        let windDown = text(app, "transcript.turn", Self.earlyWindDown)
        XCTAssertTrue(app.reveal(windDown))
        XCTAssertFalse(hasCutOffMark(app, above: windDown), "a turn that played to its end is not marked")
    }

    /// One tap makes the interviewer quiet, one tap asks it back; the label follows the interviewer's own
    /// state, and nothing is said while quiet. That turns come back after "Ask me again" is tested with PR 3's reflections.
    @MainActor
    func testQuietTogglesWithAskMeAgainAndNothingIsSaidWhileQuiet() {
        let app = launchToTimeline(arguments: ["-uiTesting-speaks"])
        app.startSession(review: false)
        let quiet = app.buttons["session.quiet"]
        XCTAssertTrue(quiet.waitForExistence(timeout: 5), "the Listen view offers Quiet while the app may speak")
        XCTAssertEqual(quiet.label, "Quiet")
        quiet.tap()
        XCTAssertTrue(quiet.wait(for: \.label, toEqual: "Ask me again", timeout: 5), "the interviewer is quiet")
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15))
        XCTAssertFalse(app.staticTexts["session.turn"].exists, "nothing is said while quiet")
        XCTAssertEqual(quiet.label, "Ask me again", "quiet lasts until the person asks again")
        quiet.tap()
        XCTAssertTrue(quiet.wait(for: \.label, toEqual: "Quiet", timeout: 5), "the interviewer may speak again")
        app.finishSession()
    }

    /// Quiet cuts the turn that is playing, of any kind, and the disclosure card stays. The script's last
    /// segment pauses at about 3.2 s; the spoken disclosure (17 words, 2.55 s) starts after it, so nothing
    /// in the script cuts it. A tap reaches the app about 0.5 to 1 s after the turn shows. The wind-down line
    /// that follows plays to its end, so the mark is the tap's.
    @MainActor
    func testQuietCutsTheTurnThatIsPlaying() {
        let app = launchToTimeline(arguments: ["-uiTesting-speaks", "-uiTesting-heavy"])
        app.startSession(review: false)
        XCTAssertTrue(text(app, "session.turn", Self.spokenPastDisclosure).waitForExistence(timeout: 15), "the disclosure text plays")
        let quiet = app.buttons["session.quiet"]
        quiet.tap()
        XCTAssertTrue(quiet.wait(for: \.label, toEqual: "Ask me again", timeout: 5))
        XCTAssertTrue(app.any("session.disclosure").exists, "the card stays")
        XCTAssertTrue(text(app, "session.turn", Self.earlyWindDown).waitForExistence(timeout: 10), "the wind-down line is spoken while quiet")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        app.buttons["session.disclosureOkay"].tap()
        app.finishSession()

        openSessionDetail(app)
        let disclosure = text(app, "transcript.turn", Self.spokenPastDisclosure)
        XCTAssertTrue(app.reveal(disclosure))
        XCTAssertTrue(hasCutOffMark(app, above: disclosure), "the tap cut the disclosure text")
        let windDown = text(app, "transcript.turn", Self.earlyWindDown)
        XCTAssertTrue(app.reveal(windDown))
        XCTAssertFalse(hasCutOffMark(app, above: windDown), "the line after it played to its end")
    }

    /// "Lifeline speaks" off: today's listening session. No Quiet control, and no turn is kept, not even the opening.
    @MainActor
    func testSpeaksOffShowsNoTurns() {
        let app = launchToTimeline(arguments: ["-uiTesting-speaks"])
        app.buttons["home.settings"].tap()
        let toggle = app.switches["settings.speaks"]
        XCTAssertTrue(app.reveal(toggle), "Settings has Lifeline speaks")
        XCTAssertEqual(toggle.value as? String, "1", "on by default")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["settings.done"].tap()

        app.startSession(review: false)
        XCTAssertTrue(app.staticTexts["session.count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15))
        XCTAssertFalse(app.buttons["session.quiet"].exists, "no Quiet control when the app does not speak")
        XCTAssertEqual(app.staticTexts["session.listenCopy"].label, "Take your time. Pauses are fine. I'm only listening.")
        app.finishSession()

        openSessionDetail(app)
        // The list is lazy: look for a turn at every scroll position down to the person's words.
        let words = app.descendants(matching: .any).matching(identifier: "detail.segment")
            .matching(NSPredicate(format: "label CONTAINS %@", "climbed it in 1998")).firstMatch
        for _ in 0..<6 where !words.exists {
            XCTAssertFalse(app.staticTexts["transcript.turn"].exists, "no turn is kept")
            app.swipeUp()
        }
        XCTAssertTrue(words.waitForExistence(timeout: 2), "the person's words are kept")
        XCTAssertFalse(app.staticTexts["transcript.turn"].exists, "no turn is kept, not even the opening")
    }

    /// Settling in, the scripted interviewer reflects the newest segment's last four words after a clean check.
    /// Slow script, so the first story gets its reflection: its pause is at about 3.3 s, the reply grace
    /// (0.3 s) and its partial's hold on the floor (1 s from 2.5 s) have passed by about 3.6 s, and the
    /// reflection (4 words, 0.6 s) plays to its end long before the second segment starts at about 5.8 s.
    /// With the 0.8 s script, each next segment starts inside the partial's hold and makes the reply stale.
    /// The Listen view shows the first reflection only until the next one, so its words are checked in the
    /// stored transcript; on the Listen view, a turn stays once one has played.
    @MainActor
    func testSettleInShowsAReflectionAfterAScriptedSegment() {
        let app = launchToTimeline(arguments: ["-uiTesting-speaks", "-uiTesting-slow"])
        startSettleIn(app)
        XCTAssertTrue(app.staticTexts["session.turn"].waitForExistence(timeout: 15), "the Listen view shows a reflection")
        app.finishSession()

        openSessionDetail(app)
        XCTAssertTrue(app.reveal(text(app, "transcript.turn", "Before Maya climbed it")), "the first story is reflected in its own words")
    }

    /// At the planned length (8 s under UI testing) the arc winds down, and the wrap-up waits for a check
    /// of a segment stored after the last turn. Slow script: the second segment's reflection plays at about
    /// 7 s; the planned length fires between 8 and 9 s on the arc's one-second tick; the third segment pauses
    /// at about 10 s, its check-only call goes out after the 0.3 s grace, and the wrap-up is spoken then.
    /// The margin is the planned length firing before about 10.3 s, when the third segment is asked about.
    @MainActor
    func testTheWrapUpIsSpokenAtThePlannedLength() {
        let app = launchToTimeline(arguments: ["-uiTesting-speaks", "-uiTesting-slow"])
        startSettleIn(app)
        XCTAssertTrue(app.any("session.wrapUp").waitForExistence(timeout: 14), "the wrap-up is offered at the planned length")
        XCTAssertTrue(text(app, "session.turn", Self.wrapUp).waitForExistence(timeout: 10), "and spoken after a clean check")
        app.finishSession()
    }
}
