import Foundation

/// The words on a tile, and what VoiceOver reads. Pure.
public enum ThingTileText {
    public static let guessLine = "Placed by a guess"

    /// "1 moment", "3 moments"; nil for 0.
    public static func countLine(_ moments: Int) -> String? {
        switch moments {
        case ..<1: return nil
        case 1: return "1 moment"
        default: return "\(moments) moments"
        }
    }

    /// The count, the guess line and the quote in curly quotes, joined by ". ". Empty when there is none.
    public static func accessibilityValue(moments: Int, placedByGuess: Bool, quote: String?) -> String {
        var parts: [String] = []
        if let count = countLine(moments) { parts.append(count) }
        if placedByGuess { parts.append(guessLine) }
        if let quote { parts.append("“\(quote)”") }
        return parts.joined(separator: ". ")
    }
}
