import Foundation

/// Whether a list row counts as on screen, for the Timeline card's frame. Pure; the row keeps
/// its last answer and passes it back.
///
/// A row comes on screen when at least half of it is inside the area (half of the area, for a
/// row taller than it). A row that is on stays on while any part of it is inside the area
/// widened by `slack` at both edges. The screen passes a slack larger than the most its own
/// pinned card can change height. The card's height moves the area's top: without the slack,
/// one row near an edge could flip the card, and the card flip the row, without end. A row the
/// taller card covers entirely is still inside the widened area, so it stays on.
public enum RowVisibility {
    /// `row` and `area` are vertical extents, top...bottom, in one coordinate space. An area with
    /// no height has not been measured yet, and holds no row. A negative slack counts as none.
    public static func isOnScreen(wasOnScreen: Bool, row: ClosedRange<Double>, area: ClosedRange<Double>, slack: Double) -> Bool {
        let rowHeight = row.upperBound - row.lowerBound, areaHeight = area.upperBound - area.lowerBound
        guard rowHeight > 0, areaHeight > 0 else { return false }
        if wasOnScreen {
            let widen = max(slack, 0)
            return overlap(row, (area.lowerBound - widen)...(area.upperBound + widen)) > 0
        }
        return overlap(row, area) >= min(rowHeight, areaHeight) / 2
    }

    /// How many points of `a` are inside `b`; zero or less when they do not meet.
    private static func overlap(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>) -> Double {
        min(a.upperBound, b.upperBound) - max(a.lowerBound, b.lowerBound)
    }
}
