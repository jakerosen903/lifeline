import Foundation

/// Decides who a said name most likely means. Pure: it reads the people on file and the
/// contacts it is given and writes nothing. The seven rules are in
/// `docs/specs/2026-11-18-people-contacts.md`, "Matching a said name". A group phrase never
/// reaches `guess`; the caller filters it.
public enum PersonGuess {
    public struct Known: Sendable, Equatable {
        public var id: PersonID; public var name: String; public var aliases: [String]
        public var lastLinked: Date?; public var contactIdentifier: String?
        public init(id: PersonID, name: String, aliases: [String], lastLinked: Date?, contactIdentifier: String?) {
            self.id = id; self.name = name; self.aliases = aliases
            self.lastLinked = lastLinked; self.contactIdentifier = contactIdentifier
        }
    }

    public struct Contact: Sendable, Equatable {
        public var identifier: String; public var fullName: String; public var givenName: String; public var nickname: String
        public init(identifier: String, fullName: String, givenName: String, nickname: String) {
            self.identifier = identifier; self.fullName = fullName; self.givenName = givenName; self.nickname = nickname
        }
    }

    public enum Choice: Sendable, Equatable, Hashable { case person(PersonID), contact(String), newPerson }

    public struct Result: Sendable, Equatable {
        public var choice: Choice; public var origin: LinkOrigin; public var rule: Int
        /// Every other candidate, persons first, in the order the sheet shows them.
        public var others: [Choice]
    }

    public static func guess(_ said: SaidName, people: [Known], contacts: [Contact]) -> Result {
        let nameKey = said.name.map(SaidName.key) ?? ""
        let relationKey = said.relation.map(SaidName.key) ?? ""
        let linkedContacts = Set(people.compactMap(\.contactIdentifier))
        let freeContacts = contacts.filter { !linkedContacts.contains($0.identifier) }

        // With a name, the name picks the candidates. Without one, the relation phrase does.
        let persons: [Known]
        let contactCandidates: [Contact]
        if !nameKey.isEmpty {
            let wanted = Set(SaidName.keyParts(of: said.raw)).union([nameKey])
            let viaContact = Set(contacts.filter { matches($0, wanted) }.map(\.identifier))
            persons = people.filter { holds($0, wanted) || ($0.contactIdentifier.map(viaContact.contains) ?? false) }
                .sorted(by: moreRecent)
            contactCandidates = freeContacts.filter { matches($0, wanted) }.sorted(by: contactOrder)
        } else {
            persons = relationKey.isEmpty ? [] : people.filter { holds($0, [relationKey]) }.sorted(by: moreRecent)
            contactCandidates = []
        }
        let everyone: [Choice] = persons.map { .person($0.id) } + contactCandidates.map { .contact($0.identifier) }
        func result(_ choice: Choice, _ origin: LinkOrigin, _ rule: Int) -> Result {
            Result(choice: choice, origin: origin, rule: rule, others: everyone.filter { $0 != choice })
        }

        // 1. Name and relation both held by exactly one person.
        if !nameKey.isEmpty, !relationKey.isEmpty {
            let both = persons.filter { holds($0, [relationKey]) }
            if both.count == 1 { return result(.person(both[0].id), .said, 1) }
        }
        // 2. A relation phrase alone, held by exactly one person.
        if nameKey.isEmpty, persons.count == 1 { return result(.person(persons[0].id), .said, 2) }
        // 3. A fuller name equal to exactly one candidate's full name.
        if nameKey.contains(" ") {
            let fullNames: [Choice] = persons.filter { SaidName.key($0.name) == nameKey }.map { .person($0.id) }
                + contactCandidates.filter { SaidName.key($0.fullName) == nameKey }.map { .contact($0.identifier) }
            if fullNames.count == 1 { return result(fullNames[0], .assumed, 3) }
        }
        // 4. A person on file, the most recently linked one first.
        if let first = persons.first { return result(.person(first.id), .assumed, 4) }
        // 5. Exactly one contact and no person.
        if contactCandidates.count == 1 { return result(.contact(contactCandidates[0].identifier), .assumed, 5) }
        // 6 and 7. A new person; the contacts, if any, stay on the sheet.
        return result(.newPerson, .new, contactCandidates.isEmpty ? 7 : 6)
    }

    private static func holds(_ person: Known, _ keys: Set<String>) -> Bool {
        ([person.name] + person.aliases).contains { text in
            let key = SaidName.key(text)
            return !key.isEmpty && keys.contains(key)
        }
    }

    private static func matches(_ contact: Contact, _ keys: Set<String>) -> Bool {
        [contact.fullName, contact.givenName, contact.nickname].contains { text in
            let key = SaidName.key(text)
            return !key.isEmpty && keys.contains(key)
        }
    }

    /// Greatest `lastLinked` first, never-linked last, then name, then id, so the order never varies.
    private static func moreRecent(_ a: Known, _ b: Known) -> Bool {
        switch (a.lastLinked, b.lastLinked) {
        case let (x?, y?) where x != y: return x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        let byName = a.name.caseInsensitiveCompare(b.name)
        return byName == .orderedSame ? a.id.rawValue < b.id.rawValue : byName == .orderedAscending
    }

    private static func contactOrder(_ a: Contact, _ b: Contact) -> Bool {
        let byName = a.fullName.caseInsensitiveCompare(b.fullName)
        return byName == .orderedSame ? a.identifier < b.identifier : byName == .orderedAscending
    }
}
