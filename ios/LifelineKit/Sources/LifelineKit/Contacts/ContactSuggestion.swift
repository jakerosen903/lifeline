import Foundation

/// A contact that appears later (spec, PC4): which contact, if any, a person with no contact is offered. Pure.
public enum ContactSuggestion {
    /// The one card that is not linked to anyone, not declined for this person, and whose full name, given name or
    /// nickname equals the person's name or an alias by `SaidName.key`. Nil for none or for two or more.
    public static func pick(name: String, aliases: [String], cards: [ContactCard], linked: Set<String>, declined: Set<String>) -> ContactCard? {
        let keys = Set(([name] + aliases).map(SaidName.key).filter { !$0.isEmpty })
        var fits: [ContactCard] = []
        for card in cards where !linked.contains(card.identifier) && !declined.contains(card.identifier)
            && !fits.contains(where: { $0.identifier == card.identifier }) && hasName(card, in: keys) {
            fits.append(card)
        }
        return fits.count == 1 ? fits[0] : nil
    }

    /// The names a said name reaches a contact by in `PersonGuess` (rule 5): full name, given name, nickname.
    static func hasName(_ card: ContactCard, in keys: Set<String>) -> Bool {
        [card.fullName, card.givenName, card.nickname].contains { text in
            let key = SaidName.key(text)
            return !key.isEmpty && keys.contains(key)
        }
    }
}
