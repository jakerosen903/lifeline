import XCTest

// MARK: - A Timeline row clear of the pinned card and the record bar

/// The Timeline's rows scroll under the pinned card at the top (timeline spec, "The pinned card" 1) and under
/// the record bar at the bottom. A row there still exists and XCUITest still finds it, but a tap on it lands
/// on the card (the life map opens) or on the bar (a session starts). A coordinate tap never scrolls first.
/// So a test that taps a Timeline row first brings the row into the clear band between the two.
@MainActor
extension XCUIApplication {
    /// More than the card grows when its "During" line comes as the list moves: one line at the default text size.
    private static let cardGrowth: CGFloat = 40
    /// Room between the row and the record bar's glass.
    private static let barMargin: CGFloat = 12

    /// Drags the list, without momentum, until `row` sits whole between the pinned card and the record bar
    /// and holds still there. False when the row is gone or does not settle in the band.
    func bringClearOfTheCardAndBar(_ row: XCUIElement, tries: Int = 6) -> Bool {
        for _ in 0..<tries {
            guard row.waitForExistence(timeout: 2), let frame = settledFrame(of: row) else { return false }
            let band = clearBand()
            if frame.minY >= band.lowerBound && frame.maxY <= band.upperBound { return true }
            // Toward the band's middle: a drag only a few points long moves nothing (the scroll's touch slop).
            dragList(by: (band.lowerBound + band.upperBound) / 2 - frame.midY)
        }
        guard let frame = settledFrame(of: row) else { return false }
        let band = clearBand()
        return frame.minY >= band.lowerBound && frame.maxY <= band.upperBound
    }

    /// From under the pinned card (or the navigation bar, with no card) to above the record bar (or the tab bar).
    private func clearBand() -> ClosedRange<CGFloat> {
        let card = descendants(matching: .any).matching(identifier: "timeline.card").firstMatch
        let top = card.exists && !card.frame.isEmpty ? card.frame.maxY + Self.cardGrowth : navigationBars.firstMatch.frame.maxY
        let bar = buttons["home.start"]
        let bottom = bar.exists && !bar.frame.isEmpty ? bar.frame.minY - Self.barMargin : tabBars.firstMatch.frame.minY
        return top...max(top, bottom)
    }

    /// The element's frame once it has held still for one poll; nil if it never does within the timeout.
    /// The list can still be moving: a swipe's momentum, or the card growing as other years come on screen.
    private func settledFrame(of element: XCUIElement, timeout: TimeInterval = 3) -> CGRect? {
        var last = CGRect.null
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            guard element.exists else { return nil }
            let frame = element.frame
            if !frame.isEmpty && frame == last { return frame }
            last = frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    /// A press, a drag of `offset` points (positive moves the rows down) and a hold, so the list does not coast.
    /// At least 40 points and at most a third of the screen per drag, from the middle of the screen.
    private func dragList(by offset: CGFloat) {
        let limit = frame.height / 3
        let distance = (offset < 0 ? -1 : 1) * min(max(abs(offset), 40), limit)
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: distance))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }
}
