import XCTest

/// You as a portrait (S3): the header, the lead line, the four parts in the spec's order, the chips, and the
/// page with nothing told. The portrait seed is invented: Jordan, born 1990 in Dayton.
final class YouUITests: XCTestCase {
    @MainActor
    func testThePortraitReadsInTheSpecOrder() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        XCTAssertEqual(app.staticTexts["you.name"].label, "Jordan")
        XCTAssertEqual(app.staticTexts["you.birth"].label, "born 1990 in Dayton")
        XCTAssertEqual(app.buttons["entities.aboutYou"].label, "In 2 moments, from 1999 to 2000")
        XCTAssertEqual(app.staticTexts["you.lead"].label, "I was always the kid who took things apart", "pickLead is 0 under test")
        XCTAssertEqual(app.youLineLabels(), ["I'm the oldest of two", "I never could sit still in a classroom", "Something about Ohio",
                                             "Leaving Boston felt like closing a book before the last chapter",
                                             "I was never scared at the lake, not once", "I want to take Maya to Lisbon someday"])
        XCTAssertFalse(app.buttons["Two years younger than me"].exists, "a fact about Maya is on her page, not here")
        XCTAssertFalse(app.buttons["I still sleep with the hall light on"].exists, "a hidden fact never shows")
        XCTAssertFalse(app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I was always the kid who took things apart")).firstMatch.exists, "the lead does not repeat")
        let headings = ["Who you are", "How it felt", "What you think", "What you're hoping for"].map { app.staticTexts[$0] }
        XCTAssertTrue(headings.allSatisfy(\.exists))
        XCTAssertEqual(headings.map(\.frame.minY), headings.map(\.frame.minY).sorted(), "the parts in spec order")
        XCTAssertLessThan(app.staticTexts["you.lead"].frame.minY, headings[0].frame.minY)
        XCTAssertEqual(app.buttons.matching(identifier: "you.feelingAbout").firstMatch.label, "about The lake")
        XCTAssertEqual(app.buttons.matching(identifier: "entities.row").firstMatch.label, "Saying yes to things")
        XCTAssertFalse(app.any("you.invite").exists)
        let line = { (label: String) in app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", label)).firstMatch }
        XCTAssertEqual(line("I'm the oldest of two").value as? String, "Family", "a fact's tags are its value")
        let said = line("I want to take Maya to Lisbon someday").value as? String ?? ""
        XCTAssertTrue(said.hasPrefix("said in "), "a goal says when it was said, was “\(said)”")
        XCTAssertNil(said.rangeOfCharacter(from: .decimalDigits), "said this year: the month only, was “\(said)”")
    }

    @MainActor
    func testTheChipsFilterWhoYouAre() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        XCTAssertEqual(app.buttons.matching(identifier: "you.tag").allElementsBoundByIndex.map(\.label), ["Family", "School"])
        let all = app.buttons["you.tag.all"]
        let family = app.buttons.matching(identifier: "you.tag").matching(NSPredicate(format: "label == %@", "Family")).firstMatch
        XCTAssertTrue(all.isSelected, "the filter starts on All")
        XCTAssertFalse(family.isSelected)
        for chip in [all, family] {
            // The accessibility frame carries float noise (43.99999999999994 seen), so 0.01 of rounding is allowed.
            XCTAssertGreaterThanOrEqual(chip.frame.height, 44 - 0.01, "a chip is a full-size control")
            XCTAssertLessThanOrEqual(chip.frame.height, 50, "a chip is not padded past its hit area")
        }
        family.tap()
        XCTAssertFalse(all.isSelected, "choosing a tag deselects All")
        XCTAssertEqual(app.youLineLabels(), ["I'm the oldest of two",
                                             "Leaving Boston felt like closing a book before the last chapter",
                                             "I was never scared at the lake, not once", "I want to take Maya to Lisbon someday"],
                       "the chip filters Who you are only")
        XCTAssertTrue(app.buttons.matching(identifier: "you.tag").matching(NSPredicate(format: "label == %@", "Family")).firstMatch.isSelected)
        app.buttons["you.tag.all"].tap()
        XCTAssertTrue(app.buttons["I never could sit still in a classroom"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAFeelingOpensWhatItIsAbout() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        app.buttons["you.feelingAbout"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entity.title"].label, "The lake")
    }

    @MainActor
    func testAFeelingWithNothingItIsAboutOpensItsMemory() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        let feeling = app.buttons.matching(identifier: "you.line")
            .matching(NSPredicate(format: "label == %@", "Leaving Boston felt like closing a book before the last chapter")).firstMatch
        XCTAssertTrue(app.reveal(feeling))
        feeling.tap()
        XCTAssertTrue(app.any("memory.kind").waitForExistence(timeout: 5))
    }

    @MainActor
    func testALineOpensItsMemory() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        app.buttons.matching(identifier: "you.line").firstMatch.tap()
        XCTAssertTrue(app.any("memory.kind").waitForExistence(timeout: 5))
    }

    @MainActor
    func testAYouPageWithNothingToldInvitesAStory() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]; app.launch(); app.skipFirstOpen()   // an owner, nothing told
        app.openTab("You")
        XCTAssertTrue(app.any("you.invite").waitForExistence(timeout: 5))
        XCTAssertEqual(app.any("you.invite").label, "Stories you tell about yourself will show here.")
        for absent in ["Who you are", "How it felt", "What you're hoping for"] { XCTAssertFalse(app.staticTexts[absent].exists) }
        XCTAssertFalse(app.any("you.lead").exists)
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story about yourself")
        XCTAssertTrue(app.buttons["home.settings"].exists)
    }

    @MainActor
    func testTheLargestTextSizeKeepsEveryLine() {
        let app = XCUIApplication.launchWithPortrait(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.openYou()
        XCTAssertEqual(app.youLineLabels().count, 6)
        let lead = app.staticTexts["you.lead"]
        XCTAssertGreaterThan(lead.frame.height, 120, "the lead wraps onto several lines, never truncates")
        // The same 0.01 of rounding as the chip test: the accessibility frame carries float noise.
        for chip in app.buttons.matching(identifier: "you.tag").allElementsBoundByIndex { XCTAssertGreaterThanOrEqual(chip.frame.height, 44 - 0.01) }
    }

    @MainActor
    func testEveryLineWithARecordingHasAPlayControl() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        XCTAssertEqual(app.buttons["you.lead.play"].label, "Hear yourself say it, 4 seconds", "the length in words for VoiceOver; the visible text keeps 0:04")
        XCTAssertEqual(app.buttons.matching(identifier: "you.play").count, 7, "six lines and one idea with a recording; the other idea has none")
        let first = app.buttons.matching(identifier: "you.play").firstMatch
        XCTAssertEqual(first.label, "Hear yourself say it")
        XCTAssertEqual(first.value as? String, "I'm the oldest of two", "the value tells identical controls apart")
        let idea = { (title: String) in app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", title)).firstMatch }
        let plays = app.buttons.matching(identifier: "you.play").allElementsBoundByIndex
        let besides = { (title: String) -> Int in
            // A missing row has an empty frame, which no control is beside: say so instead of counting 0.
            XCTAssertTrue(idea(title).exists, "the idea row “\(title)” exists")
            XCTAssertFalse(plays.isEmpty, "the play controls exist")
            return plays.filter { $0.frame.midY >= idea(title).frame.minY && $0.frame.midY <= idea(title).frame.maxY }.count
        }
        XCTAssertEqual(besides("Saying yes to things"), 1, "an idea with a telling plays it, beside its link")
        XCTAssertEqual(besides("Telling the truth"), 0, "an idea with no span has no control")
    }

    @MainActor
    func testEveryPlayControlIsFullSize() {
        let app = XCUIApplication.launchWithPortrait(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.openYou()
        for play in app.buttons.matching(identifier: "you.play").allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(play.frame.width, 44); XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        }
        XCTAssertGreaterThanOrEqual(app.buttons["you.lead.play"].frame.height, 44)
    }

    @MainActor
    func testAMissingRecordingSaysSoAndKeepsThePage() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()   // the seed never writes seed.m4a
        app.buttons.matching(identifier: "you.play").firstMatch.tap()
        let error = app.any("you.error")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.hasPrefix("Could not play this: "))
        XCTAssertEqual(app.youLineLabels().count, 6, "the page stays as it was")
        XCTAssertEqual(app.buttons.matching(identifier: "you.play").firstMatch.label, "Hear yourself say it", "nothing is playing")
        XCTAssertEqual(error.label, "Could not play this: the recording could not be found.")
    }

    @MainActor
    func testAFailedLeadPlayShowsItsErrorWhereYouLook() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        app.buttons["you.lead.play"].tap()
        let error = app.any("you.error")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.isHittable, "the error is on screen without scrolling")
        // The one slot pinned above the record bar (final review, item 2), not under the lead.
        XCTAssertLessThanOrEqual(error.frame.maxY, app.buttons["home.start"].frame.minY, "it sits above the record bar")
    }

    @MainActor
    func testAFailedPlayFarDownShowsItsErrorWhereYouLook() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()   // the seed never writes seed.m4a
        let play = app.buttons.matching(identifier: "you.play").matching(NSPredicate(format: "value == %@", "I want to take Maya to Lisbon someday")).firstMatch
        XCTAssertTrue(app.scrollIntoView(play), "the lowest line's play control, scrolled to")
        play.tap()
        let error = app.any("you.error")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Could not play this: the recording could not be found.")
        XCTAssertTrue(error.isHittable, "the error is on screen without scrolling back up")
        XCTAssertLessThanOrEqual(error.frame.maxY, app.buttons["home.start"].frame.minY, "it sits above the record bar")
    }

    @MainActor
    func testHidingALineFarDownShowsUndoWithoutScrolling() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        let line = app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I want to take Maya to Lisbon someday")).firstMatch
        XCTAssertTrue(app.scrollIntoView(line), "the lowest line, scrolled to")
        line.press(forDuration: 1.0)
        app.buttons["you.hide"].tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5))
        let undo = app.buttons["you.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.waitHittable(undo, timeout: 5), "Undo is on screen without scrolling")
        XCTAssertLessThanOrEqual(undo.frame.maxY, app.buttons["home.start"].frame.minY, "it sits above the record bar")
        undo.tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5), "Undo brings the line back")
    }

    @MainActor
    func testCancelOnTheDeleteDialogKeepsTheLine() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        let before = app.youLineLabels()
        let line = app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I'm the oldest of two")).firstMatch
        line.press(forDuration: 1.0); app.buttons["you.delete"].tap()
        XCTAssertTrue(app.buttons["row.confirmDelete"].firstMatch.waitForExistence(timeout: 5))
        // The iOS 26 dialog is a popover: its Cancel is a tap outside it (the dismiss region); a sheet has the button.
        let outside = app.otherElements["PopoverDismissRegion"].firstMatch
        if outside.exists { outside.tap() } else { app.buttons["Cancel"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["row.confirmDelete"].firstMatch.waitForNonExistence(timeout: 5), "the dialog goes")
        XCTAssertTrue(line.exists, "Cancel keeps the line")
        XCTAssertEqual(app.youLineLabels(), before, "nothing moved")
    }

    @MainActor
    func testALineCanBeHidden() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        let line = app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I'm the oldest of two")).firstMatch
        line.press(forDuration: 1.0)
        app.buttons["you.hide"].tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.youLineLabels().count, 5)
    }

    @MainActor
    func testAHiddenLineCanBeTakenBack() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        let before = app.youLineLabels()
        let line = app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I'm the oldest of two")).firstMatch
        line.press(forDuration: 1.0)
        app.buttons["you.hide"].tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.any("you.hidden").label, "Hidden.", "the person is told, and can take it back")
        XCTAssertGreaterThanOrEqual(app.buttons["you.undo"].frame.height, 44 - 0.01, "Undo is a full-size control")
        app.buttons["you.undo"].tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5), "Undo brings the line back")
        XCTAssertEqual(app.youLineLabels(), before, "in the same place")
        XCTAssertFalse(app.any("you.hidden").exists, "the notice goes with the undo")
    }

    @MainActor
    func testTheHiddenNoticeGoesAfterSixSeconds() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I'm the oldest of two")).firstMatch.press(forDuration: 1.0)
        app.buttons["you.hide"].tap()
        XCTAssertTrue(app.any("you.hidden").waitForExistence(timeout: 5))
        XCTAssertTrue(app.any("you.hidden").waitForNonExistence(timeout: 12), "the notice does not stay")
    }

    @MainActor
    func testALineIsDeletedOnlyAfterAsking() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        let line = app.buttons.matching(identifier: "you.line").matching(NSPredicate(format: "label == %@", "I want to take Maya to Lisbon someday")).firstMatch
        line.press(forDuration: 1.0); app.buttons["you.delete"].tap()
        // The iOS 26 dialog is a popover whose button appears twice in the tree: the first match is the one to tap.
        let confirm = app.buttons["row.confirmDelete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "Delete “Lisbon”")
        confirm.tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["What you're hoping for"].exists, "a part with nothing does not show")
    }

    @MainActor
    func testAboutIsNotOnTimeline() {
        let app = XCUIApplication.launchWithPortrait(); app.openTab("Timeline")
        XCTAssertTrue(app.any("timeline.summary").waitForExistence(timeout: 5))
        XCTAssertTrue(app.any("timeline.summary").label.contains("and 10 things about your life"), "the summary counts the visible ones, the hidden fact not")
        // The List is lazy: scroll to its last row, so a section below it would be in the tree.
        app.scrollTimelineToItsEnd(last: app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label CONTAINS %@", "Moving into Hemenway Street")).firstMatch)
        XCTAssertFalse(app.any("timeline.about").exists)
        XCTAssertFalse(app.buttons.matching(identifier: "about.row").firstMatch.exists)
    }

    @MainActor
    func testShowHiddenDoesNotCountAHiddenFactTimelineCannotShow() {
        let app = XCUIApplication.launchWithPortrait(); app.openTab("Timeline")
        let summary = app.any("timeline.summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.hasSuffix("and 10 things about your life"), "was “\(summary.label)”")
        app.buttons["timeline.more"].tap()
        let toggle = app.any("timeline.showHidden")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.hasSuffix("and 10 things about your life"), "the hidden fact is not on Timeline, so it is not counted; was “\(summary.label)”")
    }

    @MainActor
    func testTheTimelineTagMenuOffersOnlyTagsAMomentCarries() {
        // "Family" and "School" are on facts only (they are chips on You); no moment carries a tag.
        let app = XCUIApplication.launchWithPortrait(); app.openTab("Timeline")
        XCTAssertTrue(app.any("timeline.summary").waitForExistence(timeout: 5))
        app.buttons["timeline.more"].tap()
        XCTAssertTrue(app.any("timeline.showHidden").waitForExistence(timeout: 5), "the menu is open")
        XCTAssertFalse(app.buttons["timeline.tagFilter"].exists, "no tag to filter moments by")
        XCTAssertFalse(app.buttons["Family"].exists, "a tag only a fact carries is not offered")
    }
}
