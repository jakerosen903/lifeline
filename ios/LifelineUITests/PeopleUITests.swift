import XCTest

final class PeopleUITests: XCTestCase {
    @MainActor
    func testTheSeedReachesEveryList() {
        let app = XCUIApplication.launchWithPeople()
        app.openTab("People")
        XCTAssertTrue(app.buttons.matching(identifier: "entities.row").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(Set(app.entityRowLabels()), ["Maya", "Dad", "Sam", "Lena"], "the owner, Jordan, is never a row")
        app.openTab("Places")
        XCTAssertTrue(app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "Alder Street")).firstMatch.waitForExistence(timeout: 5))
    }
}
