import Foundation

/// A place the person did not name: "a restaurant", "somewhere up north". Such a phrase stays in
/// the person's words and never becomes a place of its own (audit F13). A possessive ("our
/// house") or a definite phrase ("the lake") is not generic: the person means one place.
public enum GenericPhrase {
    private static let openers: Set<String> = ["a", "an", "some", "somewhere"]

    public static func isGeneric(_ text: String) -> Bool {
        guard let first = text.split(whereSeparator: \.isWhitespace).first else { return false }
        return openers.contains(MatchKey.of(String(first)))
    }
}
