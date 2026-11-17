import Foundation

/// A phrase for more than one person: "our parents", "my grandparents", "the kids". It is not
/// one person's name. Who it means depends on the story, so it is never saved as a name for
/// anyone. The list is short on purpose: it catches the common kin words, and the extractor's
/// prompt carries the general rule.
public enum GroupPhrase {
    private static let plurals: Set<String> = ["parents", "grandparents", "folks", "kids", "children", "siblings",
                                               "brothers", "sisters", "cousins", "aunts", "uncles", "friends"]

    public static func isGroup(_ text: String) -> Bool {
        guard let last = text.split(whereSeparator: \.isWhitespace).last else { return false }
        return plurals.contains(MatchKey.of(String(last)))
    }
}
