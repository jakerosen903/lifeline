import Foundation

/// Finds contacts by what the owner types. Pure.
public enum ContactSearch {
    /// Cards where the text is a prefix of any word of the full, given, family or nickname. Sorted by full name.
    public static func results(_ text: String, in cards: [ContactCard]) -> [ContactCard] {
        let query = SaidName.key(text)
        guard !query.isEmpty else { return [] }
        return cards
            .filter { card in
                [card.fullName, card.givenName, card.familyName, card.nickname].contains { field in
                    SaidName.key(field).split(separator: " ").contains { $0.hasPrefix(query) }
                }
            }
            .sorted { SaidName.key($0.fullName) < SaidName.key($1.fullName) }
    }
}
