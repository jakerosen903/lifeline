import Foundation

/// Whether a list row counts as on screen, for the Timeline card's frame. Pure; the row keeps
/// its last answer and passes it back.
///
/// A row comes on screen when at least half of it is inside the area (half of the area, for a
/// row taller than it). It goes off only when it is inside by less than that half less `slack`,
/// or not inside at all. The screen passes a slack larger than the most its own pinned card can
/// change height: the card's height moves the area, and without the slack one row near the
/// threshold could flip the card, and the card flip the row, without end.
public enum RowVisibility {
    /// `row` and `area` are vertical extents, top...bottom, in one coordinate space. An area with
    /// no height has not been measured yet, and holds no row. A negative slack counts as none.
    public static func isOnScreen(wasOnScreen: Bool, row: ClosedRange<Double>, area: ClosedRange<Double>, slack: Double) -> Bool {
        let rowHeight = row.upperBound - row.lowerBound, areaHeight = area.upperBound - area.lowerBound
        guard rowHeight > 0, areaHeight > 0 else { return false }
        let inside = min(row.upperBound, area.upperBound) - max(row.lowerBound, area.lowerBound)
        guard inside > 0 else { return false }
        let half = min(rowHeight, areaHeight) / 2
        return inside >= (wasOnScreen ? half - max(slack, 0) : half)
    }
}
