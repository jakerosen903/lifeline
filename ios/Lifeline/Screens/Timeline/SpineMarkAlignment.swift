import SwiftUI

extension VerticalAlignment {
    private enum SpineMarkLine: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
    }

    /// The line a spine row's mark, margin years and title share: the middle of the title's first line.
    static let spineMark = VerticalAlignment(SpineMarkLine.self)
}

extension View {
    /// Puts the spine's mark at this text's first line, however far the text wraps. Off the spine it does nothing.
    func spineMarkOnFirstLine() -> some View { modifier(SpineMarkOnFirstLine()) }
}

/// The `spineMark` guide on a text: its first baseline, raised by about half a capital to the line's middle.
private struct SpineMarkOnFirstLine: ViewModifier {
    @ScaledMetric(relativeTo: .headline) private var lift: CGFloat = 6

    func body(content: Content) -> some View {
        content.alignmentGuide(.spineMark) { [lift] in $0[.firstTextBaseline] - lift }
    }
}
