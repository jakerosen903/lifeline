import Foundation

/// The form search compares: decision 8. The stored text never changes.
public enum SearchFold {
    public static let maxQueryLength = 200

    /// Lower case, no diacritics, half-width, apostrophes removed, every other non-letter and non-digit a space, one space between words.
    public static func fold(_ text: String) -> String {
        words(text).joined(separator: " ")
    }

    /// The folded words of a text, in order.
    public static func words(_ text: String) -> [String] {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        var words: [String] = []
        var current = ""
        for character in folded {
            if apostrophes.contains(character) { continue }
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// The folded words of a query: cut at `maxQueryLength` characters first. Empty when the query has no letter or digit.
    public static func queryWords(_ query: String) -> [String] {
        words(String(query.prefix(maxQueryLength)))
    }

    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{02BC}"]
}
