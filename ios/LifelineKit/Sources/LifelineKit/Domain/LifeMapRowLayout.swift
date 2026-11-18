/// Where a life map row's bar and name go across the map's width, in points. Pure.
public struct LifeMapRowLayout: Sendable, Equatable {
    public enum NamePlace: Sendable, Equatable { case inside, after, before }

    /// A one-year chapter, or one that starts after now, is still a bar you can see.
    public static let minimumBarWidth = 8.0
    public static let gap = 6.0
    public static let insidePadding = 8.0

    public let barX: Double
    public let barWidth: Double
    public let namePlace: NamePlace
    public let nameX: Double
    /// The room the name has; a longer name truncates on one line.
    public let nameWidth: Double

    /// `start` and `end` are 0...1 along the axis. The name goes where it fits whole: inside the bar,
    /// else after it, else before it. When it fits nowhere whole, it goes where it has the most room,
    /// inside the bar on a tie, and truncates there. So a bar always carries its name.
    public static func place(start: Double, end: Double, width: Double, nameWidth: Double) -> LifeMapRowLayout {
        let barWidth = min(max((end - start) * width, minimumBarWidth), width)
        let barX = min(max(start * width, 0), width - barWidth)
        let insideRoom = max(barWidth - 2 * insidePadding, 0)
        let after = max(width - (barX + barWidth) - gap, 0)
        let before = max(barX - gap, 0)

        func layout(_ place: NamePlace, room: Double) -> LifeMapRowLayout {
            let shown = place == .inside ? room : min(nameWidth, room)
            let x: Double = switch place {
            case .inside: barX + insidePadding
            case .after: barX + barWidth + gap
            case .before: barX - gap - shown
            }
            return LifeMapRowLayout(barX: barX, barWidth: barWidth, namePlace: place, nameX: x, nameWidth: shown)
        }

        if nameWidth <= insideRoom { return layout(.inside, room: insideRoom) }
        if nameWidth <= after { return layout(.after, room: after) }
        if nameWidth <= before { return layout(.before, room: before) }
        if insideRoom >= after && insideRoom >= before { return layout(.inside, room: insideRoom) }
        return after >= before ? layout(.after, room: after) : layout(.before, room: before)
    }
}
