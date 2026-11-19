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
}
