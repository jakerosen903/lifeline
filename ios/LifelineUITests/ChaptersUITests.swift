import XCTest

/// Chapters on the Timeline: a tag you can tap, the chapter's sheet, the life map, "Add to a chapter…", "Take out",
/// and the removal notice with Undo. The seed (`-uiTesting-seedSpine`) has "The tree house" (1999, inferred) in
/// "Maple Street", "The science fair" (2001) in a chapter with no name, and "Learning to swim" (2000) in none.
final class ChaptersUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    // MARK: - Finding things

    private func memoryRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func allTags(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "timeline.tag")
    }

    /// The tags on screen that sit in this row: below the top of its button and no further than a tag's height under it.
    private func tags(in title: String, _ app: XCUIApplication) -> [XCUIElement] {
        let row = memoryRow(app, title)
        guard row.exists else { return [] }
        let frame = row.frame
        return allTags(app).allElementsBoundByIndex.filter { $0.exists && $0.frame.minY >= frame.minY && $0.frame.minY <= frame.maxY + 24 }
    }

    /// The labels of the row's tags once it has one, or none after `timeout`. The row can settle before the
    /// tag it just got is drawn.
    @MainActor
    private func tagLabels(in title: String, _ app: XCUIApplication, timeout: TimeInterval = 5) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while tags(in: title, app).isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return tags(in: title, app).map(\.label)
    }

    /// The row's own "…" button: the nearest one to the top of the row.
    private func moreButton(of title: String, _ app: XCUIApplication) -> XCUIElement {
        let top = memoryRow(app, title).frame.minY
        let buttons = app.buttons.matching(identifier: "row.more").allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
        return buttons.min { abs($0.frame.minY - top) < abs($1.frame.minY - top) } ?? app.buttons["row.more"].firstMatch
    }

    /// The labels, of any element on any screen of the Timeline, that contain one of `texts`.
    private func timelineLabels(_ app: XCUIApplication, containingAny texts: [String]) -> Set<String> {
        var found: Set<String> = []
        app.eachScreenOfTheTimeline {
            for text in texts {
                let hits = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).allElementsBoundByIndex
                for hit in hits where hit.exists { found.insert(hit.label) }
            }
        }
        return found
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    // MARK: - Moves

    /// The tree house's tag, then the chapter's sheet once its name is up.
    @discardableResult
    private func openMapleStreet(_ app: XCUIApplication) -> XCUIElement {
        let tag = tags(in: "The tree house", app).first ?? allTags(app).firstMatch
        XCTAssertTrue(app.waitHittable(tag, timeout: 10), "the Maple Street tag is on screen")
        tag.tap()
        let name = app.staticTexts["chapter.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the chapter's sheet opens")
        return name
    }

    private func openLifeMap(_ app: XCUIApplication) {
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

    /// Menu "Between two years", wheels, Save.
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

    /// Removes the open chapter: "Remove chapter…", then the confirmation. The sheet closes.
    private func removeOpenChapter(_ app: XCUIApplication) {
        let remove = app.buttons["chapter.remove"]
        XCTAssertTrue(app.waitHittable(remove, timeout: 5), "Remove chapter… is on screen")
        remove.tap()
        // The dialog button shows twice in the tree (the same button under its wrapper), so take the first.
        let confirm = app.buttons.matching(identifier: "chapter.confirmRemove").firstMatch
        XCTAssertTrue(app.waitHittable(confirm, timeout: 5), "the removal asks first")
        confirm.tap()
    }

    // MARK: - Tests

    // The tag is an element of its own; it opens the sheet with the name, no years and the one member.
    @MainActor
    func testATagOpensItsChaptersSheet() {
        let app = XCUIApplication.launchWithSpine()
        openMapleStreet(app)
        XCTAssertEqual(app.staticTexts["chapter.name"].label, "Maple Street")
        XCTAssertEqual(app.staticTexts["chapter.years"].label, "No dates yet", "the inferred 1999 is not shown as the chapter's years")
        let members = app.descendants(matching: .any).matching(identifier: "chapter.member")
        XCTAssertEqual(members.count, 1, "one moment is in the chapter")
        XCTAssertEqual(members.firstMatch.label, "The tree house")
    }

    // Before the save the chapter is under "Not placed in time yet"; after it, one row on the map.
    @MainActor
    func testSayWhenPutsTheChapterOnTheLifeMap() {
        let app = XCUIApplication.launchWithSpine()
        openLifeMap(app)
        let unplaced = app.any("lifemap.unplaced")
        XCTAssertTrue(unplaced.waitForExistence(timeout: 5), "chapters with no years wait in their own section")
        XCTAssertTrue(unplaced.buttons["Maple Street, no dates yet"].exists, "Maple Street is not placed yet")
        XCTAssertEqual(app.buttons.matching(identifier: "lifemap.row").count, 0, "no chapter is on the map yet")
        closeSheet(app, done: "lifemap.done")

        openMapleStreet(app)
        app.buttons["chapter.sayWhen"].tap()
        sayWhen(app, from: "1998", to: "2001")
        let years = app.staticTexts["chapter.years"]
        let shown = NSPredicate(format: "label == '1998–2001'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: years)], timeout: 5), .completed,
                       "the sheet reads the range: \(years.label)")
        closeSheet(app, done: "chapter.done")

        openLifeMap(app)
        let rows = app.buttons.matching(identifier: "lifemap.row")
        XCTAssertEqual(rows.count, 1, "one chapter is on the map")
        XCTAssertTrue(rows.firstMatch.label.hasPrefix("Maple Street, 1998"), rows.firstMatch.label)
        XCTAssertFalse(app.any("lifemap.unplaced").buttons["Maple Street, no dates yet"].exists, "Maple Street left the unplaced section")
    }

    // Review Focus 4: a date inside the stated years is no claim about a moment.
    @MainActor
    func testADatedMomentInsideAChaptersYearsGetsNoTag() {
        let app = XCUIApplication.launchWithSpine()
        openMapleStreet(app)
        app.buttons["chapter.sayWhen"].tap()
        sayWhen(app, from: "1998", to: "2001")
        XCTAssertTrue(app.staticTexts["chapter.years"].waitForExistence(timeout: 5))
        closeSheet(app, done: "chapter.done")

        let swim = memoryRow(app, "Learning to swim")
        XCTAssertTrue(app.reveal(swim), "Learning to swim (2000) is on the timeline")
        XCTAssertEqual(tags(in: "Learning to swim", app).count, 0, "2000 is inside 1998 to 2001, and the moment still has no tag")
        XCTAssertEqual(app.tagsOnTheWholeTimeline(), ["The tree house": "Maple Street"], "one tag on the whole timeline")
    }

    @MainActor
    func testRenameShowsOnTheTag() {
        let app = XCUIApplication.launchWithSpine()
        openMapleStreet(app)
        app.buttons["chapter.rename"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the rename alert is up")
        app.focusAlertField(field)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        XCTAssertFalse(app.alerts.buttons["Save"].firstMatch.isEnabled, "an empty name cannot be saved")
        field.typeText("Maple St")
        XCTAssertTrue(app.alerts.buttons["Save"].firstMatch.isEnabled)
        XCTAssertTrue(app.tapUntilGone(app.alerts.buttons["Save"].firstMatch, closing: app.alerts.firstMatch), "Save closes the rename alert")
        let name = app.staticTexts["chapter.name"]
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Maple St'"), object: name)], timeout: 5),
                       .completed, "the sheet shows the new name: \(name.label)")
        closeSheet(app, done: "chapter.done")
        XCTAssertTrue(app.waitHittable(tags(in: "The tree house", app).first ?? allTags(app).firstMatch, timeout: 5))
        XCTAssertEqual(tags(in: "The tree house", app).map(\.label), ["Maple St"], "the tag on the Timeline reads the new name")
    }

    @MainActor
    func testRemoveKeepsTheMomentAndUndoBringsTheTagBack() {
        let app = XCUIApplication.launchWithSpine()
        openMapleStreet(app)
        removeOpenChapter(app)
        let notice = app.any("chapter.removed")
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the notice shows")
        XCTAssertEqual(notice.label, "Removed “Maple Street”.")
        XCTAssertTrue(memoryRow(app, "The tree house").exists, "the moment is still on the spine")
        XCTAssertEqual(tags(in: "The tree house", app).count, 0, "and has no tag")
        let undo = app.buttons.matching(identifier: "chapter.undo").firstMatch
        XCTAssertTrue(app.waitHittable(undo, timeout: 3), "Undo is tappable inside the six seconds")
        undo.tap()
        XCTAssertTrue(waitUntilGone(notice, timeout: 5), "the notice goes after Undo")
        let back = allTags(app).matching(NSPredicate(format: "label == 'Maple Street'")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the tag is back")
        XCTAssertEqual(tags(in: "The tree house", app).map(\.label), ["Maple Street"])
    }

    @MainActor
    func testTheNoticeLeavesAfterSixSeconds() {
        let app = XCUIApplication.launchWithSpine()
        openMapleStreet(app)
        removeOpenChapter(app)
        let notice = app.any("chapter.removed")
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the notice shows")
        XCTAssertTrue(waitUntilGone(notice, timeout: 8), "the notice is gone within eight seconds")
        XCTAssertEqual(tags(in: "The tree house", app).count, 0, "the tag stays gone")
        XCTAssertTrue(memoryRow(app, "The tree house").exists)
    }

    @MainActor
    func testAddToANewChapterTagsTheMoment() {
        let app = XCUIApplication.launchWithSpine()
        let swim = memoryRow(app, "Learning to swim")
        XCTAssertTrue(app.reveal(swim), "Learning to swim is on the timeline")
        XCTAssertTrue(app.bringClearOfTheCardAndBar(swim), "Learning to swim is between the pinned card and the record bar")
        moreButton(of: "Learning to swim", app).tap()
        let add = app.buttons["row.addChapter"]
        XCTAssertTrue(app.waitHittable(add, timeout: 5), "Add to a chapter… is in the row's menu")
        add.tap()
        let field = app.textFields["chapter.newName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the sheet asks for a name")
        XCTAssertFalse(app.buttons["chapter.add"].isEnabled, "Add is disabled with an empty field")
        field.tap()
        field.typeText("   ")
        XCTAssertFalse(app.buttons["chapter.add"].isEnabled, "Add is disabled with only spaces")
        field.typeText("Swim team")
        XCTAssertTrue(app.buttons["chapter.add"].isEnabled)
        app.buttons["chapter.add"].tap()
        XCTAssertTrue(waitUntilGone(field, timeout: 5), "the sheet closed")
        XCTAssertTrue(app.waitHittable(memoryRow(app, "Learning to swim"), timeout: 5))
        XCTAssertEqual(tagLabels(in: "Learning to swim", app), ["Swim team"], "the row has the tag")
    }

    @MainActor
    func testAddToAnExistingChapterAndTakeOut() {
        let app = XCUIApplication.launchWithSpine()
        let swim = memoryRow(app, "Learning to swim")
        XCTAssertTrue(app.reveal(swim), "Learning to swim is on the timeline")
        XCTAssertTrue(app.bringClearOfTheCardAndBar(swim), "Learning to swim is between the pinned card and the record bar")
        moreButton(of: "Learning to swim", app).tap()
        let add = app.buttons["row.addChapter"]
        XCTAssertTrue(app.waitHittable(add, timeout: 5), "Add to a chapter… is in the row's menu")
        add.tap()
        let pick = app.buttons.matching(identifier: "chapter.pick").matching(NSPredicate(format: "label CONTAINS 'Maple Street'")).firstMatch
        XCTAssertTrue(app.waitHittable(pick, timeout: 5), "Maple Street is on the list")
        pick.tap()
        XCTAssertTrue(waitUntilGone(pick, timeout: 5), "the sheet closed")
        XCTAssertTrue(app.waitHittable(memoryRow(app, "Learning to swim"), timeout: 5))
        XCTAssertEqual(tagLabels(in: "Learning to swim", app), ["Maple Street"], "the moment has the tag")
        XCTAssertEqual(app.tagsOnTheWholeTimeline(), ["The tree house": "Maple Street", "Learning to swim": "Maple Street"], "two tags show")

        XCTAssertTrue(app.reveal(memoryRow(app, "Learning to swim")))
        // The walk over the whole Timeline ends with this row under the pinned card.
        XCTAssertTrue(app.bringClearOfTheCardAndBar(memoryRow(app, "Learning to swim")), "Learning to swim is between the pinned card and the record bar")
        moreButton(of: "Learning to swim", app).tap()
        let takeOut = app.buttons["row.takeOutOfChapter"]
        XCTAssertTrue(app.waitHittable(takeOut, timeout: 5), "Take out is in the menu of a moment with a tag")
        takeOut.tap()
        XCTAssertTrue(waitUntilGone(takeOut, timeout: 5))
        XCTAssertEqual(app.tagsOnTheWholeTimeline(), ["The tree house": "Maple Street"], "one tag shows")
    }

    // The chapter with no name shows on the life map, never on the Timeline. Naming it puts its tag on its moment.
    @MainActor
    func testAChapterWithNoNameShowsOnTheLifeMapOnly() {
        let app = XCUIApplication.launchWithSpine()
        XCTAssertEqual(timelineLabels(app, containingAny: ["Untitled chapter", "No name yet"]), [], "no element on any screen of the Timeline names the chapter with no name")
        XCTAssertEqual(app.tagsOnTheWholeTimeline(), ["The tree house": "Maple Street"], "only the named chapter shows as a tag")

        openLifeMap(app)
        let unnamed = app.any("lifemap.unplaced").buttons["No name yet, no dates yet"]
        XCTAssertTrue(app.waitHittable(unnamed, timeout: 5), "the chapter with no name is under Not placed in time yet")
        unnamed.tap()
        XCTAssertTrue(app.staticTexts["chapter.name"].waitForExistence(timeout: 5))
        app.buttons["chapter.rename"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.focusAlertField(field)
        field.typeText("Mr. Okafor's class")
        XCTAssertTrue(app.tapUntilGone(app.alerts.buttons["Save"].firstMatch, closing: app.alerts.firstMatch), "Save closes the rename alert")
        let name = app.staticTexts["chapter.name"]
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Mr. Okafor'"), object: name)], timeout: 5),
                       .completed, "the sheet shows the name: \(name.label)")
        closeSheet(app, done: "chapter.done")
        closeSheet(app, done: "lifemap.done")

        XCTAssertEqual(app.tagsOnTheWholeTimeline()["The science fair"], "Mr. Okafor's class", "the new name is the tag on its moment")
    }

    // `-uiTesting-seed` makes memories with no chapter, so the life map has nothing to list.
    @MainActor
    func testWithNoChaptersTheLifeMapSaysWhatAChapterIs() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTesting-seed"]
        app.launch()
        app.skipFirstOpen()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 10), "the seeded app lands on the timeline")
        openLifeMap(app)
        XCTAssertTrue(app.any("lifemap.empty").waitForExistence(timeout: 5), "the life map says what a chapter is")
        XCTAssertEqual(app.buttons.matching(identifier: "lifemap.row").count, 0, "no row")
        XCTAssertFalse(app.any("lifemap.unplaced").exists, "no unplaced section")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Not placed in time yet'")).count, 0, "no empty section")
    }

    @MainActor
    func testAtTheLargestTextTheSheetsAreReachable() {
        let app = XCUIApplication.launchWithSpine(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let row = memoryRow(app, "The tree house")
        XCTAssertTrue(app.scrollIntoView(row, swipes: 4), "The tree house is on screen")
        var tag = tags(in: "The tree house", app).first ?? allTags(app).firstMatch
        if !app.waitHittable(tag, timeout: 2) { app.swipeUp(); tag = tags(in: "The tree house", app).first ?? allTags(app).firstMatch }
        XCTAssertTrue(app.waitHittable(tag, timeout: 5), "the tag is hittable")
        tag.tap()
        XCTAssertTrue(app.staticTexts["chapter.name"].waitForExistence(timeout: 5), "the sheet opens")
        let sheet = app.any("chapter.sheet")
        for id in ["chapter.rename", "chapter.sayWhen", "chapter.remove"] {
            let button = app.buttons[id]
            var swipes = 0
            while !app.waitHittable(button, timeout: 1) && swipes < 6 { sheet.swipeUp(); swipes += 1 }
            XCTAssertTrue(app.waitHittable(button, timeout: 2), "\(id) is hittable after a scroll")
        }
        for _ in 0..<6 where !app.waitHittable(app.buttons["chapter.done"], timeout: 1) { sheet.swipeDown() }
        closeSheet(app, done: "chapter.done")

        openLifeMap(app)
        XCTAssertTrue(app.waitHittable(app.buttons["lifemap.done"], timeout: 5), "Done on the life map is hittable")
    }
}
