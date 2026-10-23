import XCTest

extension XCUIApplication {
    /// Start a quick story and, by default, open the Transcript & memories view where the
    /// transcript and the cards live (Listen is the quiet default).
    func startSession(review: Bool = true) {
        buttons["home.start"].tap()
        XCTAssertTrue(buttons["session.finish"].waitForExistence(timeout: 5))
        if review { openReview() }
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
