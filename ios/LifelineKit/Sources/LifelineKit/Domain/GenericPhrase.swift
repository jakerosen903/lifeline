import Foundation

/// A place the person did not name: "a restaurant", "somewhere up north". Such a phrase stays in
/// the person's words and never becomes a place of its own (audit F13). A possessive ("our
/// house") or a definite phrase ("the lake") is not generic: the person means one place.
///
/// A name can start with the same letters: "A Coruña", "An Loc". So a phrase is generic only
/// when it starts with an indefinite word and no later word is capitalised. A capital later in
/// the phrase means the person named something, and a name is never dropped.
public enum GenericPhrase {
    private static let openers: Set<String> = ["a", "an", "some", "somewhere"]

    public static func isGeneric(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard let first = words.first, openers.contains(MatchKey.of(String(first))) else { return false }
        return !words.dropFirst().contains { $0.first?.isUppercase ?? false }
    }
}
