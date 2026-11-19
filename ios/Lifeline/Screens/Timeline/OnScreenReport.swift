import LifelineKit
import SwiftUI

/// Where the Timeline's rows can be seen, in global coordinates: the List's own frame, below the
/// pinned card and the title, above the record bar. The rows scroll under those too, so a row
/// must be inside this frame to count as on screen.
struct ScreenArea: Equatable {
    var frame: CGRect = .zero
    /// More than the card's height can change (its "During" line comes and goes, one or two lines).
    /// The card's height moves `frame`; `RowVisibility` uses this so the card cannot flip a row.
    var slack: CGFloat = 0
}

extension View {
    /// Reports whether this row is on screen (`RowVisibility`), each time that changes and again
    /// each time the row appears.
    func reportsOnScreen(in area: ScreenArea, onChange: @escaping (Bool) -> Void) -> some View {
        modifier(OnScreenReport(area: area, onChange: onChange))
    }
}

/// Not `onScrollVisibilityChange`: in this List it never reported a row leaving, and it counts a
/// row under the pinned card as on screen. A rotation or a size change measures again.
private struct OnScreenReport: ViewModifier {
    let area: ScreenArea
    let onChange: (Bool) -> Void
    @State private var isOnScreen = false
    /// Counts appearances, so a row that comes back (the tab left and entered again) reports
    /// again even when its place on screen is what it was.
    @State private var appearance = 0

    private struct Report: Equatable { let onScreen: Bool; let appearance: Int }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Report.self) { [area, isOnScreen, appearance] proxy in
                let row = proxy.frame(in: .global)
                let onScreen = RowVisibility.isOnScreen(wasOnScreen: isOnScreen, row: Double(row.minY)...Double(row.maxY),
                                                        area: Double(area.frame.minY)...Double(area.frame.maxY),
                                                        slack: Double(area.slack))
                return Report(onScreen: onScreen, appearance: appearance)
            } action: { report in
                isOnScreen = report.onScreen
                onChange(report.onScreen)
            }
            .onAppear { appearance += 1 }
            // A cell the list takes away (scrolled far off, the row deleted, the tab left) is off screen.
            .onDisappear {
                isOnScreen = false
                onChange(false)
            }
    }
}
