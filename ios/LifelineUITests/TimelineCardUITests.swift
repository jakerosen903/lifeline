import XCTest

/// The card pinned under the Timeline's title: a strip of the whole life, a frame over the years on screen and a
/// "During" line for the chapters whose stated years those years touch. One accessibility element, `timeline.card`,
/// whose label is the spoken sentence. The seed (`-uiTesting-seedSpine`) is Jordan, born 1990, with moments in 1999
/// (inferred), 2000, 2001, 2003, 2006 and 2008-2010, one undated moment, the chapter "Maple Street" (no stated years) on
/// "The tree house" and a chapter with no name on "The science fair".
///
/// No test opens a story: no seed has a dated story whose members change the years on screen. `-uiTesting-seedDuplicates`
/// has one, but all its moments are in 2009 and it has no birth date, so opening it cannot move the frame.
final class TimelineCardUITests: XCTestCase {

    private static let lifePrefix = "Your life from 1990 to now. On screen: 1999 to "

    override func setUp() { continueAfterFailure = false }

    // MARK: - Finding things

    private func card(_ app: XCUIApplication) -> XCUIElement { app.any("timeline.card") }

    /// Waits for the card's label to satisfy a predicate: the label changes a moment after a scroll settles.
    @discardableResult
    private func waitForLabel(_ app: XCUIApplication, _ format: String, _ argument: String? = nil, timeout: TimeInterval = 10) -> Bool {
        let predicate = argument.map { NSPredicate(format: format, $0) } ?? NSPredicate(format: format)
        let met = XCTNSPredicateExpectation(predicate: predicate, object: card(app))
        return XCTWaiter().wait(for: [met], timeout: timeout) == .completed
    }

    private func memoryRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Scrolls until the last row of the spine is on screen and the card has had time to follow.
    private func scrollToTheEndOfTheSpine(_ app: XCUIApplication) {
        let last = memoryRow(app, "The first apartment")
        XCTAssertTrue(app.scrollIntoView(last, swipes: 8), "The first apartment is on screen")
        app.swipeUp()
        XCTAssertTrue(waitForLabel(app, "label CONTAINS %@", "to 2010."), "the frame reaches 2010: \(card(app).label)")
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    // MARK: - Moves

    private func openLifeMapFromTheMenu(_ app: XCUIApplication) {
        let more = app.buttons["timeline.more"]
        XCTAssertTrue(app.waitHittable(more, timeout: 10), "the Timeline's menu is on screen")
        more.tap()
        let chapters = app.buttons["timeline.chapters"]
        XCTAssertTrue(app.waitHittable(chapters, timeout: 5), "Chapters is in the menu")
        chapters.tap()
        XCTAssertTrue(app.any("lifemap.sheet").waitForExistence(timeout: 5), "the life map opens")
    }

    private func closeSheet(_ app: XCUIApplication, done: String) {
        let button = app.buttons[done]
        XCTAssertTrue(app.waitHittable(button, timeout: 5), "\(done) is on screen")
        button.tap()
        XCTAssertTrue(waitUntilGone(button, timeout: 5), "the sheet closed")
    }

    /// From the life map, opens the chapter listed under "Not placed in time yet" with this button label and taps "Say when".
    private func openUnplacedChapter(_ app: XCUIApplication, _ label: String) {
        let row = app.any("lifemap.unplaced").buttons[label]
        XCTAssertTrue(app.waitHittable(row, timeout: 5), "\(label) is under Not placed in time yet")
        row.tap()
        XCTAssertTrue(app.staticTexts["chapter.name"].waitForExistence(timeout: 5), "the chapter's sheet opens")
        app.buttons["chapter.sayWhen"].tap()
    }

    /// The sheet opens on "A year": the first wheel is the year.
    private func sayWhenAYear(_ app: XCUIApplication, _ year: String) {
        let wheel = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "the year wheel is up")
        wheel.adjust(toPickerWheelValue: year)
        app.buttons["when.save"].tap()
    }

    /// Menu "Between two years", wheels, Save (the steps `ChaptersUITests` uses).
    private func sayWhen(_ app: XCUIApplication, from first: String, to second: String) {
        let shape = app.buttons["when.shape"]
        XCTAssertTrue(app.waitHittable(shape, timeout: 5), "the date sheet is up")
        shape.tap()
        let between = app.buttons["Between two years"]
        XCTAssertTrue(app.waitHittable(between, timeout: 5), "Between two years is in the menu")
        between.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 1).waitForExistence(timeout: 5), "two year wheels")
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: first)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: second)
        app.buttons["when.save"].tap()
    }

    /// Gives Maple Street the single year 1999, then closes both sheets. The card at the top then names it.
    private func sayWhenMapleStreetWas1999(_ app: XCUIApplication) {
        openLifeMapFromTheMenu(app)
        openUnplacedChapter(app, "Maple Street, no dates yet")
        sayWhenAYear(app, "1999")
        let years = app.staticTexts["chapter.years"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '1999'"), object: years)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 5), .completed, "the sheet reads the year: \(years.label)")
        closeSheet(app, done: "chapter.done")
        closeSheet(app, done: "lifemap.done")
    }

    // MARK: - Tests

    @MainActor
    func testTheCardReadsTheLifeAndTheYearsOnScreen() {
        let app = XCUIApplication.launchWithSpine()
        let card = card(app)
        XCTAssertTrue(app.waitHittable(card, timeout: 10), "the card is on screen and tappable")
        XCTAssertTrue(waitForLabel(app, "label BEGINSWITH %@", Self.lifePrefix), "the card reads the life and the years on screen: \(card.label)")
        XCTAssertFalse(card.label.contains("During"), "no chapter has stated years, so no During line: \(card.label)")
        XCTAssertTrue(app.any("timeline.cardStrip").exists, "the strip is drawn")
    }

    // R5: the large title collapses on a scroll and the card moves up with it, so its top is not compared for equality.
    @MainActor
    func testTheCardStaysWhileTheListScrolls() {
        let app = XCUIApplication.launchWithSpine()
        let card = card(app)
        XCTAssertTrue(app.waitHittable(card, timeout: 10), "the card is on screen at launch")
        let launchTop = card.frame.minY
        XCTAssertTrue(app.scrollIntoView(memoryRow(app, "The first apartment"), swipes: 8), "The first apartment is on screen")
        XCTAssertTrue(app.waitHittable(card, timeout: 5), "the card is still on screen and tappable after the scroll")
        XCTAssertLessThanOrEqual(card.frame.minY, launchTop + 0.5, "the card is no lower than at launch")
        // Rows above the card's top are under the navigation bar, which is translucent: they count as hittable but are not in the list.
        let rows = app.buttons.matching(identifier: "timeline.memory").allElementsBoundByIndex
            .filter { $0.exists && $0.frame.minY >= card.frame.minY && $0.isHittable }
        guard let firstRow = rows.min(by: { $0.frame.minY < $1.frame.minY }) else { return XCTFail("a spine row is hittable under the card") }
        XCTAssertLessThanOrEqual(card.frame.maxY, firstRow.frame.minY + 0.5, "the card's bottom is above the first spine row: \(card.frame) \(firstRow.frame)")
    }

    // Review Focus 1.
    @MainActor
    func testTheFrameFollowsTheList() {
        let app = XCUIApplication.launchWithSpine()
        XCTAssertTrue(waitForLabel(app, "label BEGINSWITH %@", Self.lifePrefix), "the frame starts at 1999: \(card(app).label)")
        scrollToTheEndOfTheSpine(app)
        let label = card(app).label
        XCTAssertTrue(label.contains("to 2010."), "the years on screen end at 2010: \(label)")
        XCTAssertFalse(label.contains("On screen: 1999"), "the years on screen no longer start at 1999: \(label)")
        XCTAssertTrue(label.hasPrefix("Your life from 1990 to now."), "the strip still runs from 1990: \(label)")
    }

    // Maple Street is stated as the year 1999. The frame at the top (1999 to 2006) touches it; the frame at the end (2000 to 2010) does not.
    @MainActor
    func testDuringNamesAChapterOnlyWhileItsYearsAreOnScreen() {
        let app = XCUIApplication.launchWithSpine()
        sayWhenMapleStreetWas1999(app)
        XCTAssertTrue(waitForLabel(app, "label ENDSWITH %@", "During Maple Street."), "the card names Maple Street at the top: \(card(app).label)")
        scrollToTheEndOfTheSpine(app)
        XCTAssertFalse(card(app).label.contains("During"), "its year is off screen, so no During line: \(card(app).label)")
    }

    // Review Focus 3.
    @MainActor
    func testAChapterInTheDuringLineTagsNoOtherMoment() {
        let app = XCUIApplication.launchWithSpine()
        sayWhenMapleStreetWas1999(app)
        XCTAssertTrue(waitForLabel(app, "label ENDSWITH %@", "During Maple Street."), "the card names Maple Street: \(card(app).label)")
        XCTAssertEqual(app.tagsOnTheWholeTimeline(), ["The tree house": "Maple Street"], "one tag on the whole timeline")
    }

    @MainActor
    func testAChapterWithNoNameIsNotInTheDuringLine() {
        let app = XCUIApplication.launchWithSpine()
        openLifeMapFromTheMenu(app)
        openUnplacedChapter(app, "No name yet, no dates yet")
        sayWhen(app, from: "1999", to: "2003")
        let years = app.staticTexts["chapter.years"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '1999–2003'"), object: years)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 5), .completed, "the sheet reads the range: \(years.label)")
        closeSheet(app, done: "chapter.done")
        closeSheet(app, done: "lifemap.done")
        XCTAssertTrue(app.waitHittable(card(app), timeout: 5), "the card is back")
        XCTAssertTrue(waitForLabel(app, "label BEGINSWITH %@", Self.lifePrefix), "the card reads the years on screen: \(card(app).label)")
        // A negative has nothing to wait for: the same steps for a named chapter show "During" within a second (see the test above).
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertFalse(card(app).label.contains("During"), "a chapter with no name is never named: \(card(app).label)")
        XCTAssertFalse(card(app).label.contains("No name yet"), "no placeholder name either: \(card(app).label)")
    }

    @MainActor
    func testATapOnTheCardOpensTheLifeMap() {
        let app = XCUIApplication.launchWithSpine()
        let card = card(app)
        XCTAssertTrue(app.waitHittable(card, timeout: 10), "the card is on screen")
        card.tap()
        XCTAssertTrue(app.any("lifemap.sheet").waitForExistence(timeout: 5), "the life map opens")
        closeSheet(app, done: "lifemap.done")
        XCTAssertTrue(app.waitHittable(card, timeout: 5), "Done returns to the Timeline with the card in place")
    }

    // No seed has a dated story on the spine whose members move the frame, so there is no test for opening a story
    // (see the note on the class and ruling R1). The kit's tests cover that case.

    // A first open with nothing told: no moment, so no card. `-uiTesting` alone, then Skip.
    @MainActor
    func testWithNoDatedMomentThereIsNoCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.skipFirstOpen()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10), "the app lands on the timeline")
        XCTAssertTrue(app.waitHittable(app.buttons["timeline.more"], timeout: 10), "the Timeline's menu is on screen")
        XCTAssertFalse(card(app).exists, "no dated moment, no card")
        openLifeMapFromTheMenu(app)
        XCTAssertTrue(app.any("lifemap.empty").waitForExistence(timeout: 5), "the life map still opens from the menu")
    }

    // Review Focus 5.
    @MainActor
    func testAtTheLargestTextTheCardAndTheListAreReachable() {
        let app = XCUIApplication.launchWithSpine(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let card = card(app)
        XCTAssertTrue(app.waitHittable(card, timeout: 10), "the card is hittable")
        XCTAssertLessThan(card.frame.height, app.frame.height / 2, "the card is under half the screen: \(card.frame.height) of \(app.frame.height)")
        let first = memoryRow(app, "The tree house")
        if !(first.exists && app.waitHittable(first, timeout: 2)) { app.swipeUp() }
        XCTAssertTrue(app.waitHittable(first, timeout: 5), "the first spine row is hittable after at most one swipe")
        XCTAssertTrue(app.waitHittable(card, timeout: 5), "the card is still hittable")
    }
}
