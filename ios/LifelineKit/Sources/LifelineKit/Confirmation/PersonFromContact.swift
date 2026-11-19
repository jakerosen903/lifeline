import Foundation

extension Person {
    /// The one way the app makes a person from a contact: Keep's guess (rules 3 and 5), the owner's choice stored
    /// before Keep, and a move to a contact. The name is the contact's trimmed full name, with `name_origin` contact,
    /// and the contact's fields set; the caller saves the said name as the alias, never this name (PB10).
    /// `createdByGuess` is true only for the app's own guess (PB3). Nil when the full name is empty: there is no name
    /// to give the person. Pure.
    static func fromContact(_ contact: PersonGuess.Contact, createdByGuess: Bool) -> Person? {
        let name = contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return Person(id: .init(), displayName: name, notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                      nameOrigin: .contact, createdByGuess: createdByGuess, contactIdentifier: contact.identifier,
                      contactName: name, contactState: Person.contactLinked)
    }
}
