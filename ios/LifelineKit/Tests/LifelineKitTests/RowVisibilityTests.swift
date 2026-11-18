import Testing
@testable import LifelineKit

/// Extents are top...bottom in points, as the screen measures them. The row is 100 points tall unless a test says
/// otherwise; the slack of 25 stands for the most the card's height can change.
@Suite struct RowVisibilityTests {
    private let row = 0.0...100.0
    private let slack = 25.0

    private func onScreen(was: Bool, row: ClosedRange<Double>? = nil, areaTop: Double, areaBottom: Double = 800) -> Bool {
        RowVisibility.isOnScreen(wasOnScreen: was, row: row ?? self.row, area: areaTop...areaBottom, slack: slack)
    }

    // MARK: Coming on screen

    @Test func aRowHalfInsideComesOnScreen() {
        #expect(onScreen(was: false, areaTop: 50))
    }
    @Test func aRowJustUnderHalfInsideStaysOff() {
        #expect(!onScreen(was: false, areaTop: 51))
    }

    // MARK: The card's own height cannot flip a row

    @Test func aRowAtHalfStaysOnWhenTheAreaTopMovesDownByLessThanTheSlack() {
        #expect(onScreen(was: false, areaTop: 50))
        // The card grew by 20 points: the row is 30 points inside, under half, but it is on.
        #expect(onScreen(was: true, areaTop: 70))
    }
    @Test func aRowThatIsOnStaysOnWhileTheCardCoversItWithinTheSlack() {
        // The area's top is 24 points below the row's bottom: the row is hidden, but inside the area widened by 25.
        #expect(onScreen(was: true, areaTop: 124))
    }
    @Test func aRowThatIsOnGoesOffOnlyWhenItIsWhollyOutsideTheWidenedArea() {
        #expect(onScreen(was: true, areaTop: 124))
        #expect(!onScreen(was: true, areaTop: 125))
        #expect(onScreen(was: true, row: 900.0...1_000.0, areaTop: 100, areaBottom: 876))
        #expect(!onScreen(was: true, row: 900.0...1_000.0, areaTop: 100, areaBottom: 875))
    }
    @Test func aRowThatIsOffStaysOffWhenTheAreaTopMovesUpByLessThanTheSlack() {
        // Off, the row was wholly out of the widened area; the card shrank by 20 points: still under half inside.
        #expect(!onScreen(was: false, areaTop: 105))
        #expect(!onScreen(was: false, areaTop: 51))
    }

    // MARK: Edges

    @Test func aRowTallerThanTheAreaIsOnWhenItFillsHalfTheArea() {
        let tall = 0.0...2_000.0
        #expect(onScreen(was: false, row: tall, areaTop: 100, areaBottom: 800))
        #expect(onScreen(was: false, row: 450.0...3_000.0, areaTop: 100, areaBottom: 800))
        #expect(!onScreen(was: false, row: 451.0...3_000.0, areaTop: 100, areaBottom: 800))
    }
    @Test func anAreaNotYetMeasuredHoldsNoRow() {
        #expect(!onScreen(was: true, areaTop: 0, areaBottom: 0))
        #expect(!onScreen(was: false, areaTop: 0, areaBottom: 0))
    }
    @Test func aRowThatIsOffAndWhollyOutsideIsOffWhateverTheSlack() {
        #expect(!RowVisibility.isOnScreen(wasOnScreen: false, row: 900.0...1_000.0, area: 100.0...800.0, slack: 1_000))
        #expect(!RowVisibility.isOnScreen(wasOnScreen: false, row: -200.0...(-100.0), area: 100.0...800.0, slack: 1_000))
    }
    @Test func aTallRowThatIsOnStaysOnWhileAnyPartIsInside() {
        #expect(onScreen(was: true, row: 0.0...2_000.0, areaTop: 100, areaBottom: 800))
        #expect(onScreen(was: true, row: 790.0...3_000.0, areaTop: 100, areaBottom: 800))
    }
    @Test func aRowWithNoHeightIsOff() {
        #expect(!onScreen(was: true, row: 300.0...300.0, areaTop: 100))
    }
    @Test func aNegativeSlackCountsAsNone() {
        #expect(onScreen(was: false, areaTop: 50))
        #expect(RowVisibility.isOnScreen(wasOnScreen: true, row: row, area: 99.0...800.0, slack: -10))
        #expect(!RowVisibility.isOnScreen(wasOnScreen: true, row: row, area: 100.0...800.0, slack: -10))
    }

    // MARK: The closed loop: the card's height follows the row

    /// One row at the top edge is the only row that brings a chapter into the "During" line, so the card is `d` taller
    /// exactly while the row is on, and the area's top moves down by `d`. The rows do not move. The row's bottom is `x`
    /// points below the area's top without the line. From every start the answer must stop changing within a few steps.
    @Test func aRowAtTheCardsEdgeSettlesWhateverItsHeightAndTheCardsChange() {
        let top = 100.0, bottom = 900.0
        var loops: [String] = []
        for d in [26.0, 44.0, 68.0] {
            let slack = d + 1
            for rowHeight in stride(from: 1.0, through: 400.0, by: 1.0) {
                for x in stride(from: -slack - 2, through: rowHeight + slack + 2, by: 1.0) {
                    for startOn in [false, true] {
                        var on = startOn, settled = false
                        for _ in 0..<4 {
                            let next = RowVisibility.isOnScreen(wasOnScreen: on, row: (top + x - rowHeight)...(top + x),
                                                                area: (top + (on ? d : 0))...bottom, slack: slack)
                            if next == on { settled = true; break }
                            on = next
                        }
                        if !settled { loops.append("row \(rowHeight) pt, card change \(d) pt, x \(x)") }
                    }
                }
            }
        }
        let count = loops.count, first = loops.prefix(3).joined(separator: "; ")
        #expect(count == 0, "\(count) starts never settle, first: \(first)")
    }
    @Test func aSpineRowOfFortyFourPointsSettlesAtTheDefaultTextSize() {
        // The case the review found: a row with no voice span is 44 points; the card grows by 26 with its "During" line.
        let d = 26.0, slack = 27.0, rowHeight = 44.0
        for x in stride(from: 0.0, through: rowHeight, by: 1.0) {
            var on = false
            var answers: [Bool] = []
            for _ in 0..<4 {
                on = RowVisibility.isOnScreen(wasOnScreen: on, row: (100 + x - rowHeight)...(100 + x),
                                              area: (100 + (on ? d : 0))...900, slack: slack)
                answers.append(on)
            }
            #expect(answers[2] == answers[3], "x \(x): \(answers)")
        }
    }
}
