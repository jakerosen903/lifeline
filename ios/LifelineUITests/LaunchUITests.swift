import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Lifeline"].waitForExistence(timeout: 5))
    }
}
