import UIKit
import XCTest

/// A class in the UI test bundle, so `Bundle(for:)` finds the bundled fixtures.
private final class FixtureBundle {}

extension XCUIApplication {
    /// First open: "Add a little context" then Skip, which saves an empty profile and leads home.
    func skipFirstOpen() {
        XCTAssertTrue(waitHittable(buttons["firstOpen.context"], timeout: 15), "the first-open context button is tappable")
        buttons["firstOpen.context"].tap()
        XCTAssertTrue(waitHittable(buttons["aboutYou.skip"], timeout: 15), "the Skip button is tappable")
        buttons["aboutYou.skip"].tap()
    }

    /// Start a quick story and, by default, open the Transcript & memories view where the
    /// transcript and the cards live (Listen is the quiet default).
    func startSession(review: Bool = true) {
        XCTAssertTrue(waitHittable(buttons["home.start"], timeout: 10), "the Start button is on screen and tappable")
        buttons["home.start"].tap()
        XCTAssertTrue(buttons["session.finish"].waitForExistence(timeout: 5))
        if review { openReview() }
    }

    /// Finish, then leave the landing with "Done for now" (a session with no words has no landing).
    func finishSession() {
        buttons["session.finish"].tap()
        let done = buttons["landing.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "the landing appears at once after Finish")
        done.tap()
        XCTAssertTrue(waitHittable(buttons["home.start"], timeout: 10), "Done for now leads back to the timeline")
    }

    /// Elements under a full-screen cover still "exist"; only a hittable one is really on screen.
    func waitHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        // Asking isHittable of an element mid-transition records a failure instead of answering no,
        // so ask only once its frame is on screen and has held still for a poll.
        var last = CGRect.null
        func settled() -> Bool {
            guard element.exists else { last = .null; return false }
            let frame = element.frame
            defer { last = frame }
            return !frame.isEmpty && frame == last && self.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if settled() && element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return settled() && element.isHittable
    }

    /// Lists are lazy: a row below the fold is not in the tree until it scrolls into view.
    func reveal(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists { return true }
            swipeUp()
        }
        return element.waitForExistence(timeout: 2)
    }

    /// Timeline is a lazy List: scrolls until `last`, the row known to be its last, is on screen and stays there
    /// after one more swipe. Anything below it would then be in the tree, so its absence can be asserted.
    func scrollTimelineToItsEnd(last: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(reveal(last, swipes: 8), "the Timeline's last row exists", file: file, line: line)
        swipeUp()
        XCTAssertTrue(waitHittable(last, timeout: 5), "the last row stays on screen: this is the end of the list", file: file, line: line)
    }

    /// A plain ScrollView holds every element, so existing says nothing about being on screen: swipes up until
    /// the element is hittable.
    func scrollIntoView(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists, waitHittable(element, timeout: 1) { return true }
            swipeUp()
        }
        return waitHittable(element, timeout: 2)
    }

    /// Any element with this identifier, whatever its type.
    func any(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func openReview() {
        let segment = segmentedControls["session.view"].buttons["Transcript & memories"]
        if segment.waitForExistence(timeout: 3) { segment.tap() } else { buttons["Transcript & memories"].firstMatch.tap() }
    }

    func openListen() {
        let segment = segmentedControls["session.view"].buttons["Listen"]
        if segment.waitForExistence(timeout: 3) { segment.tap() } else { buttons["Listen"].firstMatch.tap() }
    }

    // MARK: - The invented family

    /// Launches with `-uiTesting-seedPeople`: Jordan with Maya, Dad, Sam, Lena and Alder Street. The seed saves a
    /// profile, so first open is done; do not call `skipFirstOpen()`.
    static func launchWithPeople(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTesting-seedPeople"] + extra
        app.launch()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 15), "the seeded app lands on the timeline")
        return app
    }

    /// Launches with `-uiTesting-seedPortrait`: the invented family, then Jordan's own facts, feelings and a goal
    /// (born 1990 in Dayton). First open is done; do not call `skipFirstOpen()`.
    static func launchWithPortrait(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTesting-seedPortrait"] + extra
        app.launch()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 15), "the seeded app lands on the timeline")
        return app
    }

    /// Launches with `-uiTesting-seedPhotos`: the invented family, then generated photos. Maya has two (a dated
    /// landscape cover, then an undated portrait), "The tree house" one, Jordan one; Dad, Sam and Lena none.
    /// First open is done; do not call `skipFirstOpen()`.
    static func launchWithPhotos(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTesting-seedPhotos"] + extra
        app.launch()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 15), "the seeded app lands on the timeline")
        return app
    }

    /// Launches with `-uiTesting-seedPhotoStory`: the family, then two landed photo sessions. The first has the kept memories
    /// "The beach" (unplaced; Maya and Dad) and "The drive home" (stated 2012; Dad), both holding a photo dated 14 June 2012, which
    /// Keep put on Maya's and Dad's pages by a story link. The second has no kept memory, and its photo has no other home.
    /// `opening` leaves that session unlanded, so the app opens on its landing. First open is done.
    static func launchWithPhotoStory(opening: String? = nil, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTesting-seedPhotoStory"] + (opening.map { ["-uiTesting-photoStoryLanding", $0] } ?? []) + extra
        app.launch()
        if opening == nil {
            XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 15), "the seeded app lands on the timeline")
        } else {
            XCTAssertTrue(app.staticTexts["landing.headline"].waitForExistence(timeout: 15), "the seeded app resumes on the landing")
        }
        return app
    }

    /// Maya's page, her cover in the viewer, then "Tell its story": a live photo session about her dated photo.
    func tellMayasCoversStory() {
        openEntityPage("Maya")
        XCTAssertTrue(waitHittable(buttons["photo.header"], timeout: 10), "Maya's cover is on screen")
        buttons["photo.header"].tap()
        let tell = buttons["photo.tellStory"]
        XCTAssertTrue(waitHittable(tell, timeout: 5), "the viewer offers Tell its story")
        XCTAssertEqual(tell.label, "Tell its story")
        tell.tap()
        XCTAssertTrue(buttons["session.finish"].waitForExistence(timeout: 10), "the session starts")
    }

    /// Launches with `-uiTesting-seedSpine`: Jordan (born 1990) with six placed moments, a gap of three years, one named
    /// chapter, one chapter without a title and one undated moment. First open is done; do not call `skipFirstOpen()`.
    static func launchWithSpine(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTesting-seedSpine"] + extra
        app.launch()
        XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 15), "the seeded app lands on the timeline")
        return app
    }

    /// Launches with `-uiTesting-seedGuesses`: Robin Okafor guessed for "Robin" in two moments of the latest session,
    /// with two older moments of his own; Tomas (new) and Danielle (said) in a third; Priya, made by a guess, in one
    /// older moment. With `landing` the latest session's landing is open; otherwise the app is on the timeline.
    /// First open is done; do not call `skipFirstOpen()`.
    static func launchWithGuesses(landing: Bool = false, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTesting-seedGuesses"] + (landing ? ["-uiTesting-guessesLanding"] : []) + extra
        app.launch()
        if landing {
            XCTAssertTrue(app.buttons["landing.done"].waitForExistence(timeout: 15), "the seeded session's landing is open")
        } else {
            XCTAssertTrue(app.waitHittable(app.buttons["home.start"], timeout: 15), "the seeded app lands on the timeline")
        }
        return app
    }

    /// A copy of a bundled fixture in the temporary folder, for a launch argument such as `-uiTesting-pickPhoto`.
    static func fixturePath(_ name: String, ext: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: ext), "fixture \(name).\(ext) in the UI test bundle")
        let dest = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: url, to: dest)
        return dest.path
    }

    /// Opens a page's "…" menu, then taps "Add a photo" in it.
    func addPhotoFromMenu(_ menu: String, _ item: String) {
        let more = buttons[menu]
        XCTAssertTrue(waitHittable(more, timeout: 10), "the page's menu is on screen")
        more.tap()
        let add = buttons[item]
        XCTAssertTrue(waitHittable(add, timeout: 5), "Add a photo is in the menu")
        add.tap()
    }

    /// The 0xRRGGBB of the pixel at a unit point (0...1 each way) of the element's screenshot.
    func colour(of element: XCUIElement, at unit: CGPoint) -> Int {
        guard let image = element.screenshot().image.cgImage,
              let pixel = Self.pixel(of: image, x: Int(unit.x * CGFloat(image.width - 1)), y: Int(unit.y * CGFloat(image.height - 1)))
        else { XCTFail("the element has a screenshot to sample"); return -1 }
        return pixel
    }

    /// Whether two 0xRRGGBB values are within 24 per channel (the copy is JPEG in Display P3).
    func isNear(_ a: Int, _ b: Int) -> Bool {
        guard a >= 0, b >= 0 else { return false }
        return [16, 8, 0].allSatisfy { abs(((a >> $0) & 0xFF) - ((b >> $0) & 0xFF)) <= 24 }
    }

    /// Redraws one pixel into sRGB, so the comparison does not depend on the screenshot's colour space.
    private static func pixel(of image: CGImage, x: Int, y: Int) -> Int? {
        guard let one = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drew = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drew ? Int(rgba[0]) << 16 | Int(rgba[1]) << 8 | Int(rgba[2]) : nil
    }

    /// The You tab, once its header is up.
    func openYou() {
        openTab("You")
        XCTAssertTrue(staticTexts["you.name"].waitForExistence(timeout: 10), "the portrait's header is up")
    }

    /// The `you.line` labels on You, top to bottom. A fact or a goal is a button; a feeling is its text.
    func youLineLabels() -> [String] {
        let lines = (buttons.matching(identifier: "you.line").allElementsBoundByIndex + staticTexts.matching(identifier: "you.line").allElementsBoundByIndex)
            .filter { $0.exists && !$0.frame.isEmpty }
        return lines.sorted { $0.frame.minY < $1.frame.minY }.map(\.label)
    }

    /// The `entities.row` labels, top to bottom, then leading to trailing.
    func entityRowLabels() -> [String] {
        let rows = buttons.matching(identifier: "entities.row").allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty }
        return rows.sorted { a, b in
            let (fa, fb) = (a.frame, b.frame)
            return abs(fa.minY - fb.minY) > 1 ? fa.minY < fb.minY : fa.minX < fb.minX
        }.map(\.label)
    }

    /// People, then the row with this label, then wait for the page's title.
    func openEntityPage(_ title: String) {
        openTab("People")
        let row = buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(waitHittable(row, timeout: 10), "the \(title) row is on screen")
        row.tap()
        XCTAssertTrue(staticTexts["entity.title"].waitForExistence(timeout: 10), "the \(title) page is up")
    }

    // MARK: - Routes through the tabs

    /// Select a tab by its title. Tapping the tab the app is already on is harmless.
    func openTab(_ title: String) {
        let tab = tabBars.buttons[title]
        XCTAssertTrue(waitHittable(tab, timeout: 10), "the \(title) tab is on screen")
        tab.tap()
    }

    /// The entity list for a type: People, Places or Things have a tab; Ideas are listed on You.
    func openEntities(_ type: String) {
        openTab(type == "Ideas" ? "You" : type)
    }

    /// You, then the Settings button.
    func openSettings() {
        openTab("You")
        let settings = buttons["home.settings"]
        XCTAssertTrue(waitHittable(settings, timeout: 10), "Settings is on the You tab")
        settings.tap()
    }

    /// Timeline, then the Sessions button.
    func openSessions() {
        openTab("Timeline")
        let sessions = buttons["timeline.sessions"]
        XCTAssertTrue(waitHittable(sessions, timeout: 10), "Sessions is on the Timeline tab")
        sessions.tap()
        XCTAssertTrue(navigationBars["Sessions"].waitForExistence(timeout: 5), "the Sessions screen is up")
    }

    /// People, the overflow menu, then "Names you mentioned".
    func openNamesQueue() {
        openTab("People")
        let more = buttons["people.more"]
        XCTAssertTrue(waitHittable(more, timeout: 10), "the People overflow menu is on screen")
        more.tap()
        let names = buttons["home.people"]
        XCTAssertTrue(waitHittable(names, timeout: 5), "Names you mentioned is in the menu")
        names.tap()
    }

    /// Timeline, its overflow menu, then the "Show hidden memories" toggle.
    func toggleShowHiddenMemories() {
        openTab("Timeline")
        let more = buttons["timeline.more"]
        XCTAssertTrue(waitHittable(more, timeout: 10), "the Timeline overflow menu is on screen")
        more.tap()
        let toggle = any("timeline.showHidden")
        XCTAssertTrue(waitHittable(toggle, timeout: 5), "Show hidden memories is in the menu")
        toggle.tap()
    }

    /// The record bar's menu, then "Settle in".
    func startSettleIn() {
        let more = buttons["home.more"]
        XCTAssertTrue(waitHittable(more, timeout: 10), "the record bar's menu is on screen")
        more.tap()
        let settle = buttons["home.settleIn"]
        XCTAssertTrue(waitHittable(settle, timeout: 5), "Settle in is in the bar's menu")
        settle.tap()
        XCTAssertTrue(buttons["session.finish"].waitForExistence(timeout: 5))
    }
}

// MARK: - The Timeline's whole spine

extension XCUIApplication {
    /// Calls `visit` on every screen of the lazy Timeline, from its top to its last row, "The blue kite" (the spine seed).
    func eachScreenOfTheTimeline(_ visit: () -> Void) {
        let app = self
        func memoryRow(_ title: String) -> XCUIElement {
            app.buttons.matching(identifier: "timeline.memory").matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        }
        let first = memoryRow("The tree house")
        for _ in 0..<10 where !(first.exists && app.waitHittable(first, timeout: 1)) { app.swipeDown() }
        let last = memoryRow("The blue kite")
        for _ in 0..<10 {
            visit()
            if last.exists && app.waitHittable(last, timeout: 1) { break }
            app.swipeUp()
        }
        visit()
        XCTAssertTrue(last.exists, "the scroll reached the last row, so every row above it was on screen once")
    }

    /// Every tag on the whole Timeline as (row title: tag label). A tag belongs to the row whose top is the nearest above it.
    func tagsOnTheWholeTimeline() -> [String: String] {
        let app = self
        var seen: [String: String] = [:]
        eachScreenOfTheTimeline {
            let rows = app.buttons.matching(identifier: "timeline.memory").allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
                .map { (title: $0.label.components(separatedBy: " · ")[0], y: $0.frame.minY) }
            let tags = app.descendants(matching: .any).matching(identifier: "timeline.tag")
            for tag in tags.allElementsBoundByIndex where tag.exists && !tag.frame.isEmpty {
                guard let row = rows.filter({ $0.y <= tag.frame.minY }).max(by: { $0.y < $1.y }) else { continue }
                seen[row.title] = tag.label
            }
        }
        return seen
    }
}
