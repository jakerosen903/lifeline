import XCTest

extension XCUIApplication {
    /// First open: "Add a little context" then Skip, which saves an empty profile and leads home.
    func skipFirstOpen() {
        XCTAssertTrue(waitHittable(buttons["firstOpen.context"], timeout: 15), "the first-open context button is tappable")
        buttons["firstOpen.context"].tap()
        XCTAssertTrue(waitHittable(buttons["aboutYou.skip"], timeout: 15), "the Skip button is tappable")
        buttons["aboutYou.skip"].tap()
    }

    /// Start a quick story and, by default, open the Transcript & memories view where the
    /// transcript and the cards live (Listen is the quiet default).
    func startSession(review: Bool = true) {
        XCTAssertTrue(waitHittable(buttons["home.start"], timeout: 10), "the Start button is on screen and tappable")
        buttons["home.start"].tap()
        XCTAssertTrue(buttons["session.finish"].waitForExistence(timeout: 5))
        if review { openReview() }
    }

    /// Finish, then leave the landing with "Done for now" (a session with no words has no landing).
    func finishSession() {
        buttons["session.finish"].tap()
        let done = buttons["landing.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "the landing appears at once after Finish")
        done.tap()
        XCTAssertTrue(waitHittable(buttons["home.start"], timeout: 10), "Done for now leads back to the timeline")
    }

    /// Elements under a full-screen cover still "exist"; only a hittable one is really on screen.
    func waitHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        // Asking isHittable of an element mid-transition records a failure instead of answering no,
        // so ask only once its frame is on screen and has held still for a poll.
        var last = CGRect.null
        func settled() -> Bool {
            guard element.exists else { last = .null; return false }
            let frame = element.frame
            defer { last = frame }
            return !frame.isEmpty && frame == last && self.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if settled() && element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return settled() && element.isHittable
    }

    /// Lists are lazy: a row below the fold is not in the tree until it scrolls into view.
    func reveal(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists { return true }
            swipeUp()
        }
        return element.waitForExistence(timeout: 2)
    }

    /// Any element with this identifier, whatever its type.
    func any(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func openReview() {
        let segment = segmentedControls["session.view"].buttons["Transcript & memories"]
        if segment.waitForExistence(timeout: 3) { segment.tap() } else { buttons["Transcript & memories"].firstMatch.tap() }
    }

    func openListen() {
        let segment = segmentedControls["session.view"].buttons["Listen"]
        if segment.waitForExistence(timeout: 3) { segment.tap() } else { buttons["Listen"].firstMatch.tap() }
    }

    // MARK: - The invented family

    /// Launches with `-uiTesting-seedPeople`: Jordan with Maya, Dad, Sam, Lena and Alder Street. The seed saves a
    /// profile, so first open is done; do not call `skipFirstOpen()`.
    static func launchWithPeople(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTesting-seedPeople"] + extra
        app.launch()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 15), "the seeded app lands on the timeline")
        return app
    }

    /// The `entities.row` labels, top to bottom, then leading to trailing.
    func entityRowLabels() -> [String] {
        let rows = buttons.matching(identifier: "entities.row").allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty }
        return rows.sorted { a, b in
            let (fa, fb) = (a.frame, b.frame)
            return abs(fa.minY - fb.minY) > 1 ? fa.minY < fb.minY : fa.minX < fb.minX
        }.map(\.label)
    }

    /// People, then the row with this label, then wait for the page's title.
    func openEntityPage(_ title: String) {
        openTab("People")
        let row = buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(waitHittable(row, timeout: 10), "the \(title) row is on screen")
        row.tap()
        XCTAssertTrue(staticTexts["entity.title"].waitForExistence(timeout: 10), "the \(title) page is up")
    }

    // MARK: - Routes through the tabs

    /// Select a tab by its title. Tapping the tab the app is already on is harmless.
    func openTab(_ title: String) {
        let tab = tabBars.buttons[title]
        XCTAssertTrue(waitHittable(tab, timeout: 10), "the \(title) tab is on screen")
        tab.tap()
    }

    /// The entity list for a type: People, Places or Things have a tab; Ideas are listed on You.
    func openEntities(_ type: String) {
        openTab(type == "Ideas" ? "You" : type)
    }

    /// You, then the Settings button.
    func openSettings() {
        openTab("You")
        let settings = buttons["home.settings"]
        XCTAssertTrue(waitHittable(settings, timeout: 10), "Settings is on the You tab")
        settings.tap()
    }

    /// Timeline, then the Sessions button.
    func openSessions() {
        openTab("Timeline")
        let sessions = buttons["timeline.sessions"]
        XCTAssertTrue(waitHittable(sessions, timeout: 10), "Sessions is on the Timeline tab")
        sessions.tap()
        XCTAssertTrue(navigationBars["Sessions"].waitForExistence(timeout: 5), "the Sessions screen is up")
    }

    /// People, the overflow menu, then "Names you mentioned".
    func openNamesQueue() {
        openTab("People")
        let more = buttons["people.more"]
        XCTAssertTrue(waitHittable(more, timeout: 10), "the People overflow menu is on screen")
        more.tap()
        let names = buttons["home.people"]
        XCTAssertTrue(waitHittable(names, timeout: 5), "Names you mentioned is in the menu")
        names.tap()
    }

    /// Timeline, its overflow menu, then the "Show hidden memories" toggle.
    func toggleShowHiddenMemories() {
        openTab("Timeline")
        let more = buttons["timeline.more"]
        XCTAssertTrue(waitHittable(more, timeout: 10), "the Timeline overflow menu is on screen")
        more.tap()
        let toggle = any("timeline.showHidden")
        XCTAssertTrue(waitHittable(toggle, timeout: 5), "Show hidden memories is in the menu")
        toggle.tap()
    }

    /// The record bar's menu, then "Settle in".
    func startSettleIn() {
        let more = buttons["home.more"]
        XCTAssertTrue(waitHittable(more, timeout: 10), "the record bar's menu is on screen")
        more.tap()
        let settle = buttons["home.settleIn"]
        XCTAssertTrue(waitHittable(settle, timeout: 5), "Settle in is in the bar's menu")
        settle.tap()
        XCTAssertTrue(buttons["session.finish"].waitForExistence(timeout: 5))
    }
}
