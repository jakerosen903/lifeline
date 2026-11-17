import Foundation

/// The form of a name that the app compares to decide that two names are the same: lower case,
/// with no sentence punctuation, quotation mark or space at either end, and one space between
/// words. The stored name never changes; only the comparison does. "Ohio." and "ohio" share a
/// key. "St. Louis" keeps its inner full stop.
///
/// Only marks that end or wrap a sentence are removed. A symbol can be part of a name: "C++" and
/// "C#" must stay two names, because stories with one key are joined without a question.
public enum MatchKey {
    private static let edges = CharacterSet(charactersIn: ".,!?;:…'\"‘’“”").union(.whitespacesAndNewlines)

    /// Empty when the text has nothing but those marks and space. An empty key matches nothing.
    public static func of(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: edges)
    }
}
