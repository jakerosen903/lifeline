import XCTest

/// The shell: five labeled tabs, and a record bar under them that starts a session from anywhere
/// and names the page it would be about.
final class ShellUITests: XCTestCase {
    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        app.skipFirstOpen()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10), "the record bar is on screen")
        return app
    }

    /// People, then the seeded person's page.
    @MainActor
    private func openMaya(_ app: XCUIApplication) {
        app.tabBars.buttons["People"].tap()
        let row = app.any("entities.row")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Maya")
        row.tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [match], timeout: 5), .completed, "label is “\(label)”, was “\(element.label)”")
    }

    @MainActor
    func testFiveLabeledTabs() {
        let app = launch()
        for title in ["Timeline", "People", "Places", "Things", "You"] {
            XCTAssertTrue(app.tabBars.buttons[title].waitForExistence(timeout: 5), "a tab titled \(title)")
        }
    }

    @MainActor
    func testTheBarStartsASessionFromAnyTab() {
        let app = launch()
        app.tabBars.buttons["Things"].tap()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 5))
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTheBarNamesThePageAndTheSessionOpensAboutIt() {
        let app = launch(["-uiTesting-seed"])
        openMaya(app)
        waitForLabel(app.buttons["home.start"], "Tell a story about Maya")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "task-5-person"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.staticTexts["Tell me about Maya."].waitForExistence(timeout: 5), "the session opens about the page")
    }

    @MainActor
    func testTheBarForgetsThePageWhenTheTabChanges() {
        let app = launch(["-uiTesting-seed"])
        openMaya(app)
        waitForLabel(app.buttons["home.start"], "Tell a story about Maya")
        app.tabBars.buttons["Timeline"].tap()
        waitForLabel(app.buttons["home.start"], "Tell a story")
    }

    @MainActor
    func testAStartErrorShowsOnTheBarOnAnyTab() {
        let app = launch(["-uiTesting-denyMicrophone"])
        app.tabBars.buttons["Things"].tap()
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.any("timeline.error").waitForExistence(timeout: 5), "the start error shows on the bar")
        XCTAssertFalse(app.buttons["session.finish"].exists, "no session started")
    }

    @MainActor
    func testASecondStartFromAnotherTabDoesNothing() {
        // The microphone answers after five seconds: time to change tab and tap again while the first start waits.
        let app = launch(["-uiTesting-slowMicrophone"])
        app.buttons["home.start"].tap()
        app.tabBars.buttons["Places"].tap()
        XCTAssertTrue(app.buttons["home.start"].isHittable, "the session screen is not up yet")
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 15) || app.staticTexts["session.count"].exists)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.finishSession()

        app.tabBars.buttons["Timeline"].tap()
        app.buttons["timeline.sessions"].tap()
        XCTAssertTrue(app.any("home.sessionRow").waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "home.sessionRow").count, 1, "one session, not two")
    }

    @MainActor
    func testSettleInIsInTheBarsMenu() {
        let app = launch()
        app.buttons["home.more"].tap()
        XCTAssertTrue(app.buttons["home.settleIn"].waitForExistence(timeout: 5))
        app.buttons["home.settleIn"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["session.kind"].label, "You chose settling in")
    }

    @MainActor
    func testSessionsAndSettingsAreLabeled() {
        let app = launch()
        XCTAssertTrue(app.buttons["Sessions"].exists)
        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    }

    /// The You root and the owner's own page are both about yourself, also after going back.
    @MainActor
    func testTheYouTabIsAboutYourself() {
        let app = launch()
        app.tabBars.buttons["You"].tap()
        waitForLabel(app.buttons["home.start"], "Tell a story about yourself")
        app.buttons["entities.aboutYou"].tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        waitForLabel(app.buttons["home.start"], "Tell a story about yourself")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["entities.aboutYou"].waitForExistence(timeout: 5))
        waitForLabel(app.buttons["home.start"], "Tell a story about yourself")
        app.tabBars.buttons["Places"].tap()
        waitForLabel(app.buttons["home.start"], "Tell a story")
    }

    @MainActor
    func testTheLastTimelineRowIsReachableAboveTheBar() {
        let app = launch(["-uiTesting-seed"])
        let last = app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "The lake in 1991")).firstMatch
        XCTAssertTrue(app.reveal(last, swipes: 10), "the twelfth memory scrolls into view")
        app.swipeUp()   // to the very end of the list
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(last.isHittable, "the last row is not under the bar")
        XCTAssertLessThanOrEqual(last.frame.maxY, app.buttons["home.start"].frame.minY, "the last row ends above the record bar")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "task-5-timeline"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
