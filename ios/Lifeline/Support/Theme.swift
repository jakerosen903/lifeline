import SwiftUI

/// Palette and type from docs/design. Fraunces is not bundled in M1; the serif system
/// design stands in for titles.
enum Theme {
    static let linen = Color(red: 0xF6 / 255, green: 0xF0 / 255, blue: 0xE4 / 255)
    static let sand = Color(red: 0xEC / 255, green: 0xE3 / 255, blue: 0xD2 / 255)
    static let ink = Color(red: 0x33 / 255, green: 0x2A / 255, blue: 0x23 / 255)
    static let stone = Color(red: 0xA8 / 255, green: 0x9A / 255, blue: 0x85 / 255)
    static let olive = Color(red: 0x5F / 255, green: 0x70 / 255, blue: 0x46 / 255)
    static let ochre = Color(red: 0xC8 / 255, green: 0x89 / 255, blue: 0x3F / 255)
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
