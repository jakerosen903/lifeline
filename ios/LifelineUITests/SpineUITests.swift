import XCTest

/// S6a: the Timeline is one spine of moments. The seed (`-uiTesting-seedSpine`) is Jordan, born 1990, with six placed
/// moments in 1999, 2000, 2001, 2003, 2006 and 2008–2010 (gaps of 1, 1, 2, 3 and 2 years), a chapter "Maple Street"
/// on the first, a chapter with no title on the third, and one undated moment, "The blue kite".
final class SpineUITests: XCTestCase {

    private let placedTitles = ["The tree house", "Learning to swim", "The science fair", "Maya's graduation", "The first gig", "The first apartment"]

    override func setUp() { continueAfterFailure = false }

    private func memoryRows(_ app: XCUIApplication, _ title: String) -> XCUIElementQuery {
        app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label BEGINSWITH %@", title))
    }

    private func memoryRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        memoryRows(app, title).firstMatch
    }

    /// The labels of every element with this identifier, top to bottom, one entry per element, however far down.
    /// The list is lazy, so this scrolls to the last row (the shelf's "The blue kite") and records each screen on the way.
    /// An element seen on two screens must count once and two elements with one label must count twice, so every sighting
    /// gets an absolute y: each memory row's title is a fixed reference (titles are unique), and a later screen is shifted
    /// by the row it shares with what was already seen. Two sightings are one element when label and absolute y agree.
    private func labelsOnTheWholeTimeline(_ app: XCUIApplication, identifier: String) -> [String] {
        var rowY: [String: CGFloat] = [:]   // title -> absolute y of its row
        var log = SightingLog()
        func record(firstScreen: Bool) {
            let rows = app.buttons.matching(identifier: "timeline.memory").allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
                .map { (title: $0.label.components(separatedBy: " · ")[0], y: $0.frame.minY) }
            var shift: CGFloat = 0
            if !firstScreen {
                guard let shared = rows.first(where: { rowY[$0.title] != nil }) else {
                    XCTFail("this screen shares no row with the last one, so its elements cannot be placed")
                    return
                }
                shift = rowY[shared.title]! - shared.y
            }
            for row in rows where rowY[row.title] == nil { rowY[row.title] = row.y + shift }
            let found = app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
            for element in found { log.add(element.label, atY: element.frame.minY + shift) }
        }
        let last = memoryRow(app, "The blue kite")
        var firstScreen = true
        for _ in 0..<10 {
            record(firstScreen: firstScreen)
            firstScreen = false
            if last.exists && app.waitHittable(last, timeout: 1) { break }
            app.swipeUp()
        }
        if !firstScreen { record(firstScreen: false) }
        XCTAssertTrue(last.exists, "the scroll reached the last row, so everything above it was on screen once")
        return log.labelsTopToBottom
    }

    // Each of the six dated titles is one timeline.memory button; the undated one is on the shelf.
    @MainActor
    func testEveryPlacedMomentIsOnTheSpine() {
        let app = XCUIApplication.launchWithSpine()
        for title in placedTitles {
            let row = memoryRow(app, title)
            XCTAssertTrue(app.reveal(row), "\(title) is on the timeline")
            XCTAssertEqual(memoryRows(app, title).count, 1,
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

/// What was seen while scrolling, as (label, absolute y). The same label at the same place is one element; at another place, another.
private struct SightingLog {
    /// Closer than any two rows, waypoints or tags can sit, so it absorbs rounding and never merges two elements.
    static let sameSpot: CGFloat = 20
    private var entries: [(label: String, y: CGFloat)] = []

    mutating func add(_ label: String, atY y: CGFloat) {
        guard !entries.contains(where: { $0.label == label && abs($0.y - y) < Self.sameSpot }) else { return }
        entries.append((label, y))
    }

    var labelsTopToBottom: [String] { entries.sorted { $0.y < $1.y }.map(\.label) }
}
