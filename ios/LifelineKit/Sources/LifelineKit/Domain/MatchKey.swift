import Foundation

/// The form of a name that the app compares to decide that two names are the same: lower case,
/// with no punctuation or space at either end, and one space between words. The stored name
/// never changes; only the comparison does. "Ohio." and "ohio" share a key. "St. Louis" keeps
/// its inner full stop.
public enum MatchKey {
    private static let edges = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)

    /// Empty when the text has nothing but punctuation and space. An empty key matches nothing.
    public static func of(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: edges)
    }
}
