import XCTest

/// The launch repair (audit A1): stories that share a title become one, the person is told once
/// above the record bar, and a second launch finds nothing to repair and says nothing.
final class RepairUITests: XCTestCase {
    private static let notice = "Joined 3 copies of “The road trip”."

    /// Launches on the seed of three stories titled "The road trip" in three spellings. The notice stays
    /// six seconds from the moment the shell is up, so this waits for nothing before it returns.
    @MainActor
    private func launchWithDuplicates(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTesting-seedDuplicates"] + extra
        app.launch()
        return app
    }

    @MainActor
    private func roadTrip(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "timeline.story").matching(NSPredicate(format: "label BEGINSWITH %@", "The road trip · "))
    }

    @MainActor
    func testTheNoticeSaysWhatWasJoinedAndThenGoes() {
        let app = launchWithDuplicates()
        let notice = app.any("shell.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the repair's notice shows at launch")
        XCTAssertEqual(notice.label, Self.notice)
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 5), "the record bar stays under the notice")
        XCTAssertLessThanOrEqual(notice.frame.maxY, app.buttons["home.start"].frame.minY, "the notice sits above the record bar")
        XCTAssertTrue(notice.waitForNonExistence(timeout: 12), "the notice does not stay")
    }

    @MainActor
    func testATapSendsTheNoticeAway() {
        let app = launchWithDuplicates()
        let notice = app.any("shell.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the repair's notice shows at launch")
        notice.tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 2), "a tap sends it away before its six seconds")
    }

    @MainActor
    func testTheNoticeShowsOnWhicheverTabIsOnScreen() {
        let app = launchWithDuplicates()
        app.openTab("People")
        let notice = app.any("shell.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 3), "the notice is on People too")
        XCTAssertEqual(notice.label, Self.notice)
    }

    @MainActor
    func testTheTimelineShowsOneStoryWithThreeMoments() {
        let app = launchWithDuplicates()
        let stories = roadTrip(app)
        XCTAssertTrue(stories.firstMatch.waitForExistence(timeout: 10), "the joined story is on the Timeline")
        XCTAssertEqual(app.buttons.matching(identifier: "timeline.story").count, 1, "one story, not three")
        XCTAssertTrue(stories.firstMatch.label.hasSuffix(" · 3 moments"), stories.firstMatch.label)
    }

    @MainActor
    func testARelaunchOnTheSameDatabaseShowsNoNotice() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lifeline-ui-repair").path
        try? FileManager.default.removeItem(atPath: dir)
        let app = launchWithDuplicates(["-uiTesting-db", dir])
        XCTAssertTrue(app.any("shell.notice").waitForExistence(timeout: 5), "the first launch repairs and says so")
        app.terminate()

        // No seed this time: the database is as the first launch left it.
        let again = XCUIApplication()
        again.launchArguments = ["-uiTesting", "-uiTesting-db", dir]
        again.launch()
        XCTAssertTrue(roadTrip(again).firstMatch.waitForExistence(timeout: 10), "the joined story is still one story")
        XCTAssertTrue(roadTrip(again).firstMatch.label.hasSuffix(" · 3 moments"), roadTrip(again).firstMatch.label)
        XCTAssertFalse(again.any("shell.notice").waitForExistence(timeout: 3), "a second launch finds nothing to repair and says nothing")
    }
}
