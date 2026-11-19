import Foundation

/// Keep's use of `PersonGuess` (PC-a, Task 3): each said name on a card becomes a link that
/// records how it was made. Nothing here looks a person up by name. The guess reads the people
/// on file once per card and writes nothing; a new person is only planned, and lands in the
/// memory's own transaction with its link, so a kill leaves both or neither.
extension CandidateActions {
    /// What one card's guesses read, once per card.
    struct GuessInputs {
        /// Everyone on file but the owner.
        var known: [PersonGuess.Known]
        var contacts: [PersonGuess.Contact]
        /// The owner's answers stored with the card before Keep.
        var choices: [PersonChoice]
        var owner: OwnerNames
        /// The card a new person is created from.
        var card: CandidateID?
        /// The relation phrase each person card of the segment gave with its name (plan decision 4).
        var mentionRelations: [(text: String, relation: String)]
        /// Who each handle became in the kept memories of this recording, newest first (PC-d). Empty for a card with no handles.
        var handleLinks: [PersonLinkRepository.HandleLink] = []

        /// The owner's stored answer under `key` (`ChoiceKey`).
        func choice(_ key: String) -> PersonChoice? { choices.first { $0.saidKey == key } }

        /// The said name for a ref, with the relation phrase a person card of the segment gave it.
        func saidName(_ ref: String) -> SaidName {
            SaidName(ref: ref, mentionRelation: mentionRelations.first { CandidateActions.same($0.text, ref) }?.relation)
        }
    }

    /// Who a said name means on Keep and how the link is made.
    struct GuessedLink: Equatable {
        var person: PersonID
        var origin: LinkOrigin
        /// The owner's words to save as aliases: only from `said` or `confirmed` (a guess teaches no name).
        var aliases: [String]
    }

    /// What each handle of one telling became on this Keep: the card's and each continuation row's. A continuation's
    /// handles are on the earlier card and on its own row too (D8), so a handle is decided once and then read here.
    struct HandlePlan {
        struct Entry {
            var handle: String
            /// `SaidName.key` of the handle's said name.
            var saidKey: String
            /// Nil: the owner said "Not a person", or the said name holds no words.
            var link: GuessedLink?
            /// The contact of a person this Keep plans from a contact, so another handle of the same said name skips it.
            var contact: String?
        }
        var entries: [Entry] = []
        /// Every handle of the telling (the card's and each continuation row's), so the owner's stored answers are
        /// known before any guess runs, whatever the order of the handles.
        var telling: [PersonOut] = []
        func entry(_ handle: String) -> Entry? { entries.first { $0.handle == handle } }
    }

    /// `readingHandles`: the card has handles, so the recording's handle links are read (one query, skipped otherwise).
    func guessInputs(card: CandidateID?, segment: SegmentID?, readingHandles: Bool = false) throws -> GuessInputs {
        let relations = try segment.map { segment in
            try store.candidates.candidates(for: segment).compactMap { row -> (text: String, relation: String)? in
                guard row.kind == .person, let mention = CandidatePayload.mention(row),
                      let relation = mention.relationText?.trimmingCharacters(in: .whitespacesAndNewlines), !relation.isEmpty else { return nil }
                return (mention.text, relation)
            }
        } ?? []
        let handleLinks = readingHandles ? try segment.map { try store.personLinks.handleLinks(inSessionOf: $0) } ?? [] : []
        return GuessInputs(known: try store.personLinks.known(), contacts: contactsForGuess(),
                           choices: try card.map { try store.personLinks.choices(for: $0) } ?? [],
                           owner: try store.people.ownerNames(), card: card, mentionRelations: relations, handleLinks: handleLinks)
    }

    /// The link for one handle of the card (PC-d), or nil for "not a person". The first step that applies decides:
    /// 1. the owner's answer stored for this handle (`ChoiceKey`), origin `confirmed`;
    /// 2. the person this handle already has on this Keep, or in a kept memory of this recording (decision 7);
    /// 3. the guess, where a person another handle of the same said name holds is no candidate, and the model's
    ///    person id decides inside rule 4 (decision 6).
    func handleLink(for person: PersonOut, _ inputs: GuessInputs, handles: inout HandlePlan, plan: inout EntityRepository.Write) -> GuessedLink? {
        if let done = handles.entry(person.handle) { return done.link }
        let said = SaidName(ref: person.saidName, mentionRelation: person.relationText)
        let key = SaidName.key(person.saidName)
        let link: GuessedLink?
        if let stored = inputs.choice(ChoiceKey.text(saidName: person.saidName, handle: person.handle)) {
            link = storedLink(stored, for: said, handle: person.handle, inputs, plan: &plan)
        } else if let earlier = inputs.handleLinks.first(where: { $0.handle == person.handle }) {
            link = GuessedLink(person: earlier.person, origin: Self.carried(earlier.origin), aliases: [])
        } else {
            // Two handles of one said name are two people: what the others hold is taken, a planned person's contact too,
            // and what the owner chose for another handle of the telling, decided yet or not.
            let others = handles.entries.filter { $0.handle != person.handle && $0.saidKey == key }
            let chosen = Self.ownersChoices(otherThan: person.handle, saidKey: key, in: handles.telling, inputs)
            let taken = Set(inputs.handleLinks.filter { $0.handle != person.handle && $0.saidKey == key }.map(\.person)
                            + others.compactMap(\.link?.person) + chosen.persons)
            let takenContacts = Set(others.compactMap(\.contact) + chosen.contacts)
            var free = inputs
            free.contacts = inputs.contacts.filter { !takenContacts.contains($0.identifier) }
            let result = PersonGuess.guess(said, people: inputs.known, contacts: free.contacts,
                                           modelPick: person.personID.map(PersonID.init(rawValue:)), taken: taken)
            link = guessedLink(from: result, for: said, handle: person.handle, free, plan: &plan)
        }
        let contact = link.flatMap { link in plan.persons.first { $0.id == link.person }?.contactIdentifier }
        handles.entries.append(.init(handle: person.handle, saidKey: key, link: link, contact: contact))
        return link
    }

    /// The persons and contacts the owner's stored answers give the other handles of the telling with this said key.
    /// A contact a person holds is that person; a contact no one holds will be a person made from it.
    static func ownersChoices(otherThan handle: String, saidKey key: String, in telling: [PersonOut],
                              _ inputs: GuessInputs) -> (persons: [PersonID], contacts: [String]) {
        var persons: [PersonID] = [], contacts: [String] = []
        for other in telling where other.handle != handle && SaidName.key(other.saidName) == key {
            switch inputs.choice(ChoiceKey.text(saidName: other.saidName, handle: other.handle))?.choice {
            case .person(let id)?: persons.append(id)
            case .contact(let identifier)?:
                if let holder = inputs.known.first(where: { $0.contactIdentifier == identifier }) { persons.append(holder.id) }
                else { contacts.append(identifier) }
            case .newPerson?, nil: break
            }
        }
        return (persons, contacts)
    }

    /// Decision 7: a handle keeps its person, but not the owner's answer. `said` and `new` stay; anything else is the
    /// app's guess now (`assumed`), a `confirmed` link included: only the owner's own action confirms a link.
    static func carried(_ origin: LinkOrigin?) -> LinkOrigin {
        origin == .said || origin == .new ? origin ?? .assumed : .assumed
    }

    /// The link for one said name, or nil when the owner said it is not a person or it names
    /// nothing. The caller filters the owner's name and group phrases. A stored choice is the
    /// owner's answer, so it wins with origin `confirmed`; otherwise `PersonGuess` decides.
    func guessedLink(for said: SaidName, _ inputs: GuessInputs, plan: inout EntityRepository.Write) -> GuessedLink? {
        if let stored = inputs.choice(ChoiceKey.text(saidName: said.raw, handle: nil)) {
            return storedLink(stored, for: said, handle: nil, inputs, plan: &plan)
        }
        return guessedLink(from: PersonGuess.guess(said, people: inputs.known, contacts: inputs.contacts), for: said, handle: nil, inputs, plan: &plan)
    }

    /// The owner's stored answer as a link, origin `confirmed`; nil for "not a person".
    private func storedLink(_ stored: PersonChoice, for said: SaidName, handle: String?, _ inputs: GuessInputs,
                            plan: inout EntityRepository.Write) -> GuessedLink? {
        if stored.notAPerson { return nil }
        let aliases = [said.name, said.relation].compactMap { $0 }   // R8: the owner's answer teaches both halves
        switch stored.choice {
        case .person(let id): return GuessedLink(person: id, origin: .confirmed, aliases: aliases)
        case .contact(let identifier):
            // The owner chose this contact. A person who holds it now is that choice; a contact the app can still see
            // makes a person the owner chose (PB3). A contact gone from view since falls back to the said name.
            if let holder = inputs.known.first(where: { $0.contactIdentifier == identifier }) {
                return GuessedLink(person: holder.id, origin: .confirmed, aliases: aliases)
            }
            if let contact = inputs.contacts.first(where: { $0.identifier == identifier }),
               let person = plannedPerson(from: contact, alias: nil, createdByGuess: false, card: inputs.card, plan: &plan) {
                return GuessedLink(person: person, origin: .confirmed, aliases: aliases)
            }
            return plannedPerson(for: said, handle: handle, createdByGuess: false, card: inputs.card, plan: &plan)
                .map { GuessedLink(person: $0, origin: .confirmed, aliases: aliases) }
        case .newPerson:
            return plannedPerson(for: said, handle: handle, createdByGuess: false, card: inputs.card, plan: &plan)
                .map { GuessedLink(person: $0, origin: .confirmed, aliases: aliases) }
        case nil: return nil   // `choices(for:)` gives no choice only for "not a person", handled above
        }
    }

    /// The guess's choice as a link: a person on file, a person planned from a contact, or a new person.
    private func guessedLink(from result: PersonGuess.Result, for said: SaidName, handle: String?, _ inputs: GuessInputs,
                             plan: inout EntityRepository.Write) -> GuessedLink? {
        switch result.choice {
        case .person(let id):
            return GuessedLink(person: id, origin: result.origin, aliases: result.origin == .said ? [said.relation].compactMap { $0 } : [])
        case .contact(let identifier):
            // Rules 3 and 5: a person linked to the one contact that fits. The guess only picks a contact
            // it was given, so the lookup cannot miss; if it ever did, a new person is the safe answer.
            // A contact matches only by a said name, so one is always there; the guard keeps an empty one out.
            if let contact = inputs.contacts.first(where: { $0.identifier == identifier }),
               let alias = said.name?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty,
               let person = plannedPerson(from: contact, alias: alias, createdByGuess: true, card: inputs.card, plan: &plan) {
                return GuessedLink(person: person, origin: result.origin, aliases: [])
            }
            return newGuessedPerson(for: said, handle: handle, inputs, plan: &plan)
        case .newPerson:
            return newGuessedPerson(for: said, handle: handle, inputs, plan: &plan)
        }
    }

    /// Rules 6 and 7: a person with the said name and no contact, origin `new`.
    private func newGuessedPerson(for said: SaidName, handle: String?, _ inputs: GuessInputs, plan: inout EntityRepository.Write) -> GuessedLink? {
        plannedPerson(for: said, handle: handle, createdByGuess: true, card: inputs.card, plan: &plan)
            .map { GuessedLink(person: $0, origin: .new, aliases: []) }
    }

    /// A new person linked to `contact` (`Person.fromContact`), planned once: a second ref in this card that reaches
    /// the same contact reaches this person. `alias` is the said name Keep's guess saves with the plan ("The person's
    /// name"), so the context packet has the owner's words for them; the owner's stored choice passes nil and saves
    /// its said names as that link's aliases. The picture is copied after Keep, outside this plan. The caller never
    /// passes a contact a person holds, so the unique index is not reached here.
    private func plannedPerson(from contact: PersonGuess.Contact, alias: String?, createdByGuess: Bool, card: CandidateID?,
                               plan: inout EntityRepository.Write) -> PersonID? {
        if let index = plan.persons.firstIndex(where: { $0.contactIdentifier == contact.identifier }) {
            // The owner's stored choice reaching a person the guess planned makes them the owner's (PB3, M-1).
            if !createdByGuess { plan.persons[index].createdByGuess = false }
            return plan.persons[index].id
        }
        guard let person = Person.fromContact(contact, createdByGuess: createdByGuess) else { return nil }
        plan.entities.append(Entity(id: person.entityID, type: .person, title: person.displayName, createdFromCandidateID: card))
        plan.persons.append(person)
        if let alias { plan.aliases.append(Alias(personID: person.id, text: alias)) }
        return person.id
    }

    /// A new person for a said name, planned once: a second ref with the same name in this
    /// card reaches the person already planned. Their name is the said name, or the relation
    /// phrase when no name was said; it becomes their alias when the plan is written.
    /// With a handle the person is that handle's alone (PC-d): a handle is decided once per Keep (`HandlePlan`),
    /// so it always plans a new person, and no said name reaches a person planned for a handle.
    /// Nil when the ref holds no words.
    private func plannedPerson(for said: SaidName, handle: String?, createdByGuess: Bool, card: CandidateID?,
                               plan: inout EntityRepository.Write) -> PersonID? {
        let name = (said.name ?? said.relation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = SaidName.key(name)
        guard !key.isEmpty else { return nil }
        // A person planned from a contact is reached by that contact only (PB13), never by a said name.
        if handle == nil, let index = plan.persons.firstIndex(where: {
            $0.contactIdentifier == nil && !plan.handlePersons.contains($0.id) && SaidName.key($0.displayName) == key
        }) {
            if !createdByGuess { plan.persons[index].createdByGuess = false }   // as for a contact (M-1)
            return plan.persons[index].id
        }
        let person = Person(id: .init(), displayName: name, notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                            nameOrigin: .said, createdByGuess: createdByGuess)
        plan.entities.append(Entity(id: person.entityID, type: .person, title: name, createdFromCandidateID: card))
        plan.persons.append(person)
        if handle != nil { plan.handlePersons.insert(person.id) }
        return person.id
    }
}
