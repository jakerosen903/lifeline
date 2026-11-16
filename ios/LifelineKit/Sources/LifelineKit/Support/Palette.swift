import Foundation

/// The app's colours as 0xRRGGBB values, kept free of SwiftUI so contrast can be tested.
/// Text colours must reach 4.5:1 (WCAG AA) on every surface they sit on.
public enum Palette {
    // Surfaces
    public static let linen = 0xF6F0E4
    public static let sand = 0xECE3D2
    public static let card = 0xFBF7EE
    // Text
    public static let ink = 0x332A23
    public static let secondaryText = 0x6D6153
    public static let ochreText = 0x8F5A1C
    public static let oliveText = 0x56663F
    // Marks and lines. Stone is too light for text.
    public static let stone = 0xA89A85
    public static let olive = 0x5F7046
    public static let ochre = 0xC8893F
    /// The three quiet tints behind a person's monogram. `ink` must pass 4.5:1 on each.
    public static let monogramTints = [0xE3DCC6, 0xDDE2D3, 0xEADBCB]

    /// WCAG contrast ratio between two colours, from 1 to 21.
    public static func contrast(_ a: Int, _ b: Int) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ hex: Int) -> Double {
        func linear(_ shift: Int) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }
}
