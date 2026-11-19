import Testing
@testable import LifelineKit

@Suite struct LifeMapRowLayoutTests {
    private let width = 350.0
    private let inside = LifeMapRowLayout.insidePadding

    @Test func aNameThatFitsStaysInsideWhole() {
        let layout = LifeMapRowLayout.place(start: 0.2, end: 0.8, width: width, nameWidth: 80)
        #expect(layout.namePlace == .inside)
        #expect(layout.nameWidth >= 80)
    }

    @Test func aBarOverTheWholeAxisKeepsALongNameInsideTruncated() {
        let layout = LifeMapRowLayout.place(start: 0, end: 1, width: width, nameWidth: 500)
        #expect(layout.namePlace == .inside)
        #expect(layout.nameWidth == width - 2 * inside)
        #expect(layout.nameX == inside)
    }

    @Test func aWideBarAtTheRightEdgeKeepsTheNameInsideNotInTheSmallSpaceBefore() {
        // The bar starts 20 points in and runs to now; the name is wider than the bar.
        let layout = LifeMapRowLayout.place(start: 20 / width, end: 1, width: width, nameWidth: 400)
        #expect(layout.namePlace == .inside)
        #expect(layout.nameWidth == layout.barWidth - 2 * inside)
        #expect(layout.nameWidth > 300)
    }

    @Test func aShortBarWithRoomAfterPutsTheNameAfterWhole() {
        let layout = LifeMapRowLayout.place(start: 0.1, end: 0.15, width: width, nameWidth: 90)
        #expect(layout.namePlace == .after)
        #expect(layout.nameWidth >= 90)
        #expect(layout.nameX == layout.barX + layout.barWidth + LifeMapRowLayout.gap)
    }

    @Test func aShortBarAtTheRightEdgePutsTheNameBeforeWhole() {
        let layout = LifeMapRowLayout.place(start: 0.9, end: 1, width: width, nameWidth: 90)
        #expect(layout.namePlace == .before)
        #expect(layout.nameWidth == 90)
        #expect(layout.nameX + layout.nameWidth + LifeMapRowLayout.gap == layout.barX)
    }

    @Test func aBarIsNeverNarrowerThanTheSmallestWidth() {
        let layout = LifeMapRowLayout.place(start: 1, end: 1, width: width, nameWidth: 50)
        #expect(layout.barWidth == LifeMapRowLayout.minimumBarWidth)
        #expect(layout.barX + layout.barWidth == width)
    }
}
