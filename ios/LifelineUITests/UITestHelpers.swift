import XCTest

extension XCUIApplication {
    /// First open: "Add a little context" then Skip, which saves an empty profile and leads home.
    func skipFirstOpen() {
        XCTAssertTrue(buttons["firstOpen.context"].waitForExistence(timeout: 5))
        buttons["firstOpen.context"].tap()
        XCTAssertTrue(buttons["aboutYou.skip"].waitForExistence(timeout: 5))
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
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.exists && element.isHittable
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
}
