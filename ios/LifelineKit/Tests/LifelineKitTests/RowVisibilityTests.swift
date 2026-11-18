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
        // The card grew by 20 points: the row is 30 points inside, under half, but within the slack.
        #expect(onScreen(was: true, areaTop: 70))
    }
    @Test func aRowJustOffStaysOffWhenTheAreaTopMovesUpByLessThanTheSlack() {
        // 24 points inside is under half less the slack: the row goes off.
        #expect(!onScreen(was: true, areaTop: 76))
        // The card shrank by 20 points: 44 points inside, still under half.
        #expect(!onScreen(was: false, areaTop: 56))
    }
    @Test func aRowGoesOffWhenItIsInsideByLessThanHalfLessTheSlack() {
        #expect(onScreen(was: true, areaTop: 75))
        #expect(!onScreen(was: true, areaTop: 76))
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
    @Test func aRowWhollyOutsideIsOffWhateverTheSlack() {
        #expect(!RowVisibility.isOnScreen(wasOnScreen: true, row: 900.0...1_000.0, area: 100.0...800.0, slack: 1_000))
        #expect(!RowVisibility.isOnScreen(wasOnScreen: true, row: -200.0...(-100.0), area: 100.0...800.0, slack: 1_000))
    }
    @Test func aRowWithNoHeightIsOff() {
        #expect(!onScreen(was: true, row: 300.0...300.0, areaTop: 100))
    }
    @Test func aNegativeSlackCountsAsNone() {
        #expect(onScreen(was: false, areaTop: 50))
        #expect(RowVisibility.isOnScreen(wasOnScreen: true, row: row, area: 50.0...800.0, slack: -10))
        #expect(!RowVisibility.isOnScreen(wasOnScreen: true, row: row, area: 51.0...800.0, slack: -10))
    }
}
