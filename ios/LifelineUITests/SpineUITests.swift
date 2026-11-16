import XCTest

/// S6a: the Timeline is one spine of moments. The seed (`-uiTesting-seedSpine`) is Jordan, born 1990, with six placed
/// moments in 1999, 2000, 2001, 2003, 2006 and 2008–2010 (gaps of 1, 1, 2, 3 and 2 years), a chapter "Maple Street"
/// on the first, a chapter with no title on the third, and one undated moment, "The blue kite".
final class SpineUITests: XCTestCase {

    private let placedTitles = ["The tree house", "Learning to swim", "The science fair", "Maya's graduation", "The first gig", "The first apartment"]

    override func setUp() { continueAfterFailure = false }

    private func memoryRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// The labels of every element with this identifier, in the order the list shows them, however far down.
    /// The list is lazy, so this scrolls to the last row (the shelf's "The blue kite") and records each screen on the way.
    private func labelsOnTheWholeTimeline(_ app: XCUIApplication, identifier: String) -> [String] {
        var seen: [String] = []
        func record() {
            let found = app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
                .sorted { $0.frame.minY < $1.frame.minY }
            for element in found where !seen.contains(element.label) { seen.append(element.label) }
        }
        let last = memoryRow(app, "The blue kite")
        for _ in 0..<10 {
            record()
            if last.exists && app.waitHittable(last, timeout: 1) { break }
            app.swipeUp()
        }
        record()
        XCTAssertTrue(last.exists, "the scroll reached the last row, so everything above it was on screen once")
        return seen
    }

    // Each of the six dated titles is one timeline.memory button; the undated one is on the shelf.
    @MainActor
    func testEveryPlacedMomentIsOnTheSpine() {
        let app = XCUIApplication.launchWithSpine()
        for title in placedTitles {
            let row = memoryRow(app, title)
            XCTAssertTrue(app.reveal(row), "\(title) is on the timeline")
            XCTAssertEqual(app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label BEGINSWITH %@", title)).count, 1,
                           "\(title) appears once")
            XCTAssertFalse(row.label.contains("no date yet"), "\(title) is placed: \(row.label)")
        }
        let kite = memoryRow(app, "The blue kite")
        XCTAssertTrue(app.reveal(kite), "The blue kite is on the timeline")
        XCTAssertTrue(app.staticTexts["timeline.shelf"].exists, "the shelf holds the undated moment")
        XCTAssertTrue(kite.label.contains("no date yet"), kite.label)
    }

    // timeline.period: one "Childhood · by your age", then one "Teens · by your age", in that order.
    @MainActor
    func testWaypointsNameThePeriodsOnce() {
        let app = XCUIApplication.launchWithSpine()
        let periods = labelsOnTheWholeTimeline(app, identifier: "timeline.period")
        XCTAssertEqual(periods, ["Childhood · by your age", "Teens · by your age"], "each period once, oldest first")
    }

    // timeline.gap: exactly one, labelled "3 years"; none says "2 years".
    @MainActor
    func testAThreeYearGapSaysSo() {
        let app = XCUIApplication.launchWithSpine()
        let gaps = labelsOnTheWholeTimeline(app, identifier: "timeline.gap")
        XCTAssertEqual(gaps, ["3 years"], "only the three-year gap names itself")
        XCTAssertFalse(gaps.contains("2 years"), "a two-year gap does not")
    }

    // "The tree house" row's label contains "Maple Street"; one timeline.tag.
    @MainActor
    func testAChapterTheOwnerNamedShowsAsATag() {
        let app = XCUIApplication.launchWithSpine()
        let row = memoryRow(app, "The tree house")
        XCTAssertTrue(app.reveal(row))
        XCTAssertTrue(row.label.contains("Maple Street"), row.label)
        let tags = labelsOnTheWholeTimeline(app, identifier: "timeline.tag")
        XCTAssertEqual(tags, ["Maple Street"], "one tag: the untitled chapter shows none")
    }

    // No static text "Untitled chapter", "Outside any chapter" or "On the timeline"; no element timeline.chapter.
    @MainActor
    func testNoChapterHeadingsAndNoUntitledChapter() {
        let app = XCUIApplication.launchWithSpine()
        let forbidden = ["Untitled chapter", "Outside any chapter", "On the timeline"]
        func assertAbsent() {
            for text in forbidden {
                XCTAssertFalse(app.staticTexts[text].exists, "no \"\(text)\" heading")
            }
            XCTAssertFalse(app.any("timeline.chapter").exists, "no chapter section")
        }
        let last = memoryRow(app, "The blue kite")
        var reachedTheEnd = false
        for _ in 0..<10 {
            assertAbsent()
            if last.exists && app.waitHittable(last, timeout: 1) { reachedTheEnd = true; break }
            app.swipeUp()
        }
        XCTAssertTrue(reachedTheEnd, "the whole list was scrolled before the absences were trusted")
        assertAbsent()
    }

    // Open row.more on a row: no button "New chapter from here".
    @MainActor
    func testTheRowMenuHasNoNewChapter() {
        let app = XCUIApplication.launchWithSpine()
        let more = app.buttons["row.more"].firstMatch
        XCTAssertTrue(app.waitHittable(more, timeout: 10), "a row's menu is on screen")
        more.tap()
        XCTAssertTrue(app.buttons["row.hide"].waitForExistence(timeout: 5), "the menu is open")
        XCTAssertFalse(app.buttons["New chapter from here"].exists, "a moment's menu does not start a chapter")
    }

    // At the largest text the margin closes: "The first apartment" is hittable and its label holds "2008–10".
    @MainActor
    func testAtTheLargestTextTheDateSitsAboveTheTitle() {
        let app = XCUIApplication.launchWithSpine(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let row = memoryRow(app, "The first apartment")
        XCTAssertTrue(app.reveal(row, swipes: 20), "The first apartment is on the timeline")
        XCTAssertTrue(app.scrollIntoView(row, swipes: 6), "The first apartment is hittable")
        XCTAssertTrue(row.label.contains("2008–10"), row.label)
    }
}
