import XCTest

/// Photo story: "Tell its story" in the photo viewer starts a quick session about that photo. The photo
/// stays on the session screen, the interviewer asks nothing after its opening, and a memory dated from a
/// photo says so. The seed's first Maya photo is a dated landscape: "taken 14 June 2012".
final class PhotoStoryUITests: XCTestCase {
    /// Maya's page, her cover in the viewer, then "Tell its story".
    @MainActor
    private func tellMayasCoversStory(_ app: XCUIApplication) { app.tellMayasCoversStory() }

    @MainActor
    func testTellItsStoryStartsASessionWithThePhotoOnScreen() {
        let app = XCUIApplication.launchWithPhotos()
        tellMayasCoversStory(app)
        XCTAssertFalse(app.any("photo.viewer").exists, "the viewer closed first")
        XCTAssertEqual(app.staticTexts["session.kind"].label, "You chose a story about a photo", "the header names the session")
        let photo = app.any("session.photo")
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertEqual(photo.label, "Photo for this story")
        XCTAssertEqual(photo.value as? String, "taken 14 June 2012")
        let opening = app.staticTexts["session.prompt"]
        XCTAssertTrue(opening.waitForExistence(timeout: 5))
        XCTAssertEqual(opening.label, "Tell me about this one.")
        XCTAssertLessThan(photo.frame.maxY, opening.frame.minY, "the photo sits above the question")
    }

    @MainActor
    func testThePhotoStaysWhileThePersonTalks() {
        let app = XCUIApplication.launchWithPhotos()
        tellMayasCoversStory(app)
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15), "the scripted segments arrived")
        app.openReview()
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 5))
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(app.any("session.photo").exists)
        XCTAssertTrue(app.waitHittable(app.any("session.photo"), timeout: 5), "scrolled to the top, the photo is on screen")
    }

    @MainActor
    func testAPhotoSessionAsksNothingAfterItsOpening() {
        let app = XCUIApplication.launchWithPhotos(["-uiTesting-speaks", "-uiTesting-followUps"])
        tellMayasCoversStory(app)
        // The follow-ups script says one thing; an interviewer that asked would answer it within seconds.
        app.openReview()
        XCTAssertTrue(app.staticTexts["session.segment"].firstMatch.waitForExistence(timeout: 20), "the scripted segment arrived")
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        XCTAssertFalse(app.staticTexts["transcript.turn"].exists, "no interviewer turn appears between the person's words")
        app.openListen()
        XCTAssertFalse(app.staticTexts["session.turn"].exists, "no turn on the Listen view: the opening is the prompt")
        app.buttons["session.finish"].tap()
        XCTAssertTrue(app.buttons["landing.done"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testThePhotoKeepsItsPage() {
        let app = XCUIApplication.launchWithPhotos()
        tellMayasCoversStory(app)
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15))
        app.finishSession()
        app.openEntityPage("Maya")
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10), "the photo is still Maya's cover")
    }

    @MainActor
    func testTheSessionsListNamesAPhotoStory() {
        let app = XCUIApplication.launchWithPhotos()
        tellMayasCoversStory(app)
        XCTAssertTrue(app.staticTexts["session.count"].wait(for: \.label, toEqual: "2 possible memories", timeout: 15))
        app.finishSession()
        app.openSessions()
        XCTAssertTrue(app.staticTexts["A story about a photo"].waitForExistence(timeout: 5), "the session is named for what it was about")
    }

    @MainActor
    func testTheSessionScreenHoldsAtTheLargestText() {
        let app = XCUIApplication.launchWithPhotos(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tellMayasCoversStory(app)
        XCTAssertTrue(app.reveal(app.any("session.photo")), "the photo is reachable")
        XCTAssertTrue(app.reveal(app.staticTexts["session.prompt"]), "the opening is reachable")
        let finish = app.buttons["session.finish"]
        XCTAssertTrue(app.reveal(finish), "Finish is reachable")
        for id in ["session.finish", "session.pause"] { XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44, "\(id) is at least 44 points high") }
    }

    @MainActor
    func testADateFromAPhotoSaysSo() {
        let app = XCUIApplication.launchWithPhotos()
        app.openTab("Timeline")
        let beach = app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "The beach")).firstMatch
        XCTAssertTrue(app.reveal(beach, swipes: 10), "The beach is on the timeline")
        // The swipe that brings the row in can leave it under the record bar, and the tap point with it.
        XCTAssertTrue(app.bringClearOfTheCardAndBar(beach), "The beach is between the pinned card and the record bar")
        beach.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)).tap()
        let range = app.buttons["memory.range"]
        XCTAssertTrue(range.waitForExistence(timeout: 5))
        XCTAssertTrue(range.label.contains("14 June 2012"), "the day is shown: \(range.label)")
        XCTAssertTrue(range.label.contains("from a photo"), "and its source: \(range.label)")
        XCTAssertFalse(app.staticTexts["memory.evidence"].exists, "the person did not say the date: no \"you said\" line")
    }
}
