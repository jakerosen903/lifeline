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
            XCTAssertGreaterThanOrEqual(chip.frame.height, 44, "a chip is a full-size control")
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
        for chip in app.buttons.matching(identifier: "you.tag").allElementsBoundByIndex { XCTAssertGreaterThanOrEqual(chip.frame.height, 44) }
    }

    @MainActor
    func testEveryLineWithARecordingHasAPlayControl() {
        let app = XCUIApplication.launchWithPortrait(); app.openYou()
        XCTAssertEqual(app.buttons["you.lead.play"].label, "Hear yourself say it, 0:04")
        XCTAssertEqual(app.buttons.matching(identifier: "you.play").count, 6, "six lines with a recording; the idea has none")
        XCTAssertEqual(app.buttons.matching(identifier: "you.play").firstMatch.label, "Hear yourself say it")
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
    }
}
