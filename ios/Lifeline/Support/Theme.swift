import LifelineKit
import SwiftUI

/// Palette and type from docs/design. Fraunces is not bundled in M1; the serif system
/// design stands in for titles.
enum Theme {
    static let linen = color(Palette.linen)
    static let sand = color(Palette.sand)
    static let card = color(Palette.card)
    static let ink = color(Palette.ink)
    /// Secondary text and meaningful symbols. Passes 4.5:1 on linen, sand and card.
    static let secondaryText = color(Palette.secondaryText)
    /// Dividers, borders, strokes and decorative shapes. Too light for text.
    static let hairline = color(Palette.stone)
    static let olive = color(Palette.olive)
    /// Olive for text. Passes 4.5:1 on linen, sand and card; `olive` is for fills and large marks.
    static let oliveText = color(Palette.oliveText)
    /// Ochre marks that are not text: bands, lines, dots.
    static let ochre = color(Palette.ochre)
    /// Ochre for text. Passes 4.5:1 on linen, sand and card.
    static let ochreText = color(Palette.ochreText)

    private static func color(_ hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    func linenBackground() -> some View {
        background(Theme.linen.ignoresSafeArea())
    }

    func titleStyle() -> some View {
        font(.system(.largeTitle, design: .serif)).foregroundStyle(Theme.ink)
    }
}

enum Format {
    /// "m:ss" or "h:mm:ss".
    static func duration(ms: Int) -> String {
        let total = max(0, ms) / 1_000
        let h = total / 3_600, m = (total % 3_600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func duration(from start: Date, to end: Date) -> String {
        duration(ms: Int(end.timeIntervalSince(start) * 1_000))
    }
}
