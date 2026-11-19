import XCTest

/// Search (S5), from every tab's Search button (ruling R4): names find people, places, things and ideas; the record bar stays; nothing typed is kept.
final class SearchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSearchIsOnEveryTab() {
        let app = XCUIApplication.launchWithSearch()
        for title in ["Timeline", "People", "Places", "Things", "You"] {
            app.openTab(title)
            XCTAssertTrue(app.buttons["shell.search"].waitForExistence(timeout: 5), "a Search button on \(title)")
            XCTAssertTrue(app.waitHittable(app.buttons["shell.search"], timeout: 5), "the Search button on \(title) is tappable")
            let size = app.buttons["shell.search"].frame.size
            XCTAssertGreaterThanOrEqual(size.width, 44, "the Search button on \(title) is at least 44 points wide")
            XCTAssertGreaterThanOrEqual(size.height, 44, "the Search button on \(title) is at least 44 points high")
        }
        XCTAssertFalse(app.tabBars.buttons["More"].exists, "five tabs fit: none folds into More (ruling R4)")
        XCTAssertFalse(app.tabBars.buttons["Search"].exists, "search is not a tab (ruling R4)")
    }
    @MainActor
    func testTheEmptyFieldShowsOneLineAndNoResults() {
        let app = XCUIApplication.launchWithSearch(); app.openSearch()
        XCTAssertTrue(app.staticTexts["search.prompt"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["search.prompt"].label, "Search by a name, or by words you said.")
        XCTAssertEqual(app.searchFields.firstMatch.placeholderValue, "Memories, people, places, things")
        XCTAssertFalse(app.buttons["search.result"].exists)
        XCTAssertFalse(app.staticTexts["search.none"].exists, "an empty field is not a failed search")
    }
    @MainActor
    func testANameFindsThePersonAndOpensTheirPage() {
        let app = XCUIApplication.launchWithSearch(); app.search("maya")
        let maya = app.searchResult("Maya")
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        XCTAssertEqual(maya.value as? String, "my sister")
        maya.tap()
        XCTAssertTrue(app.staticTexts["entity.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entity.title"].label, "Maya")
        XCTAssertTrue(app.waitForLabel(app.buttons["home.start"], "Tell a story about Maya"), "the bar names the page (decision 16)")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 5), "back returns to the results")
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "maya")
    }
    @MainActor
    func testCaseDiacriticsAndApostrophesDoNotMatter() {
        let app = XCUIApplication.launchWithSearch(); app.search("ZOE")
        XCTAssertTrue(app.searchResult("Zoë").waitForExistence(timeout: 5))
        app.clearSearch(); app.search("dads volvo")
        XCTAssertTrue(app.searchResult("Dad's Volvo").waitForExistence(timeout: 5))
    }
    @MainActor
    func testAnAliasFindsThePersonAndShowsTheAlias() {
        let app = XCUIApplication.launchWithSearch(); app.search("linny")
        XCTAssertTrue(app.searchResult("Lena").waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchResult("Lena").value as? String, "Linny")
    }
    @MainActor
    func testResultsGroupByKindInOrder() {
        let app = XCUIApplication.launchWithSearch(); app.search("dad")
        XCTAssertTrue(app.searchResult("Dad").waitForExistence(timeout: 5))
        let headings = app.staticTexts.matching(identifier: "search.heading").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Array(headings.prefix(2)), ["People", "Things"], "a group with no result does not show")
        XCTAssertLessThan(app.searchResult("Dad").frame.minY, app.searchResult("Dad's Volvo").frame.minY)
    }
    @MainActor
    func testTheOwnerIsNotAResult() {
        let app = XCUIApplication.launchWithSearch(); app.search("jordan")
        XCTAssertFalse(app.searchResult("Jordan").waitForExistence(timeout: 3))
    }
    @MainActor
    func testTheBarStartsAStoryFromSearchAndTheQueryStays() {
        let app = XCUIApplication.launchWithSearch(); app.search("maya")
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 5))
        app.dismissSearchKeyboard()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 5))
        XCTAssertEqual(app.buttons["home.start"].label, "Tell a story")
        app.buttons["home.start"].tap()
        XCTAssertTrue(app.buttons["session.finish"].waitForExistence(timeout: 5))
        app.finishSession()
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 10), "the results are read again under the same query")
    }
    @MainActor
    func testTheQueryIsGoneAfterARelaunch() {
        let app = XCUIApplication.launchWithSearch(["-uiTesting-db", NSTemporaryDirectory() + "search-relaunch-\(UUID().uuidString)"]); app.search("maya")
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.openSearch()
        XCTAssertTrue(app.staticTexts["search.prompt"].waitForExistence(timeout: 10), "nothing typed is kept (decision 19)")
    }
    @MainActor
    func testANameRowIsFullSizeAtTheLargestText() {
        let app = XCUIApplication.launchWithSearch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.search("maya")
        let maya = app.searchResult("Maya")
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(maya.frame.height, 44)
        XCTAssertEqual(maya.value as? String, "my sister", "the own words still read")
    }

    @MainActor
    func testLeavingSearchTakesOneTap() {
        let app = XCUIApplication.launchWithSearch(); app.search("maya")
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 5))
        app.leaveSearch()
        XCTAssertTrue(app.waitHittable(app.buttons["shell.search"], timeout: 5), "one tap leads back to the tab (ruling R5)")
        XCTAssertFalse(app.buttons["search.result"].exists)
    }

    @MainActor
    func testLeavingSearchAfterReturnTakesOneTap() {
        let app = XCUIApplication.launchWithSearch(); app.search("maya")
        XCTAssertTrue(app.searchResult("Maya").waitForExistence(timeout: 5))
        app.dismissSearchKeyboard()
        app.leaveSearch()
        XCTAssertTrue(app.waitHittable(app.buttons["shell.search"], timeout: 5), "with the keyboard gone, one tap still leads back (ruling R5)")
        XCTAssertFalse(app.buttons["search.result"].exists)
    }

    // MARK: - Memories (Task 6)

    @MainActor
    func testWordsYouSaidFindTheMemoryAndShowThem() {
        let app = XCUIApplication.launchWithSearch(); app.search("harmonica")
        let drive = app.searchResult("The long drive")
        XCTAssertTrue(drive.waitForExistence(timeout: 5))
        XCTAssertEqual(drive.value as? String, "2004. \u{201C}…night and he kept an old harmonica in the glove box\u{201D}")
        XCTAssertEqual(app.staticTexts.matching(identifier: "search.heading").allElementsBoundByIndex.map(\.label), ["Memories"])
        drive.tap()
        XCTAssertTrue(app.any("memory.range").waitForExistence(timeout: 5), "the memory page is up")
        XCTAssertTrue(app.waitForLabel(app.buttons["home.start"], "Tell a story"), "the bar reads Tell a story on the memory page")
    }
    @MainActor
    func testATitleMatchShowsNoSnippet() {
        let app = XCUIApplication.launchWithSearch(); app.search("long drive")
        XCTAssertTrue(app.searchResult("The long drive").waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchResult("The long drive").value as? String, "2004")
    }
    @MainActor
    func testAGuessedDateReadsAsAGuess() {
        let app = XCUIApplication.launchWithSearch(); app.search("kite")
        XCTAssertTrue(app.searchResult("The red kite").waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchResult("The red kite").value as? String, "around 1998")
    }
    @MainActor
    func testAFactShowsItsWordsAsTheHeading() {
        let app = XCUIApplication.launchWithSearch(); app.search("radios")
        XCTAssertTrue(app.searchResult("\u{201C}I was always the kid who dismantled radios\u{201D}").waitForExistence(timeout: 5))
        app.clearSearch(); app.search("took")
        XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5), "a title no screen shows finds nothing (decision 3)")
    }
    @MainActor
    func testAHiddenMemoryIsNotFound() {
        let app = XCUIApplication.launchWithSearch(); app.search("accordion")
        XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5))
        app.clearSearch(); app.search("attic")
        XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5), "not by its title either")
    }
    @MainActor
    func testAMemoryKeptFromAIIsFound() {
        let app = XCUIApplication.launchWithSearch(); app.search("quiet year")
        XCTAssertTrue(app.searchResult("The quiet year").waitForExistence(timeout: 5), "decision 6")
    }
    @MainActor
    func testNothingFoundSaysWhatSearchLooksAt() {
        let app = XCUIApplication.launchWithSearch(); app.search("xylophone")
        XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["search.none"].label, "Nothing found")
        XCTAssertTrue(app.staticTexts["Search looks at names and at the words of memories you kept."].exists)
        XCTAssertFalse(app.buttons["search.result"].exists)
    }
    @MainActor
    func testPunctuationAloneIsNotASearch() {
        let app = XCUIApplication.launchWithSearch(); app.search("…!")
        XCTAssertTrue(app.staticTexts["search.prompt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["search.none"].exists)
    }
    @MainActor
    func testARenameShowsOnReturn() {
        let app = XCUIApplication.launchWithSearch(); app.search("volvo")
        XCTAssertTrue(app.searchResult("Dad's Volvo").waitForExistence(timeout: 5))
        app.searchResult("Dad's Volvo").tap()
        app.renameEntity(to: "The green Volvo")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.searchResult("The green Volvo").waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchResult("Dad's Volvo").exists)
    }
    @MainActor
    func testADeletedMemoryLeavesTheResults() {
        // Hide is the change a memory page offers; Delete lives on the Timeline row. Search is pushed on People (ruling R4),
        // so it stays on that tab's stack, with its query, while the Timeline tab deletes the memory.
        let app = XCUIApplication.launchWithSearch(); app.openTab("People"); app.search("harmonica")
        XCTAssertTrue(app.searchResult("The long drive").waitForExistence(timeout: 5))
        app.deleteTimelineMemory("The long drive")
        app.openTab("People"); app.openSearch()
        XCTAssertTrue(app.staticTexts["search.none"].waitForExistence(timeout: 5), "the screen reads again when it appears; the query is kept")
    }
    @MainActor
    func testAMemoryRowReadsInFullAtTheLargestText() {
        let app = XCUIApplication.launchWithSearch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.search("harmonica")
        let drive = app.searchResult("The long drive")
        XCTAssertTrue(drive.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(drive.frame.height, 44)
        XCTAssertTrue((drive.value as? String)?.contains("harmonica") == true)
        XCTAssertLessThanOrEqual(drive.frame.maxX, app.windows.firstMatch.frame.maxX, "nothing runs off the edge")
    }
}
