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

    func guessInputs(card: CandidateID?, segment: SegmentID?) throws -> GuessInputs {
        let relations = try segment.map { segment in
            try store.candidates.candidates(for: segment).compactMap { row -> (text: String, relation: String)? in
                guard row.kind == .person, let mention = CandidatePayload.mention(row),
                      let relation = mention.relationText?.trimmingCharacters(in: .whitespacesAndNewlines), !relation.isEmpty else { return nil }
                return (mention.text, relation)
            }
        } ?? []
        return GuessInputs(known: try store.personLinks.known(), contacts: contactsForGuess(),
                           choices: try card.map { try store.personLinks.choices(for: $0) } ?? [],
                           owner: try store.people.ownerNames(), card: card, mentionRelations: relations)
    }

    /// The link for one said name, or nil when the owner said it is not a person or it names
    /// nothing. The caller filters the owner's name and group phrases. A stored choice is the
    /// owner's answer, so it wins with origin `confirmed`; otherwise `PersonGuess` decides.
    func guessedLink(for said: SaidName, _ inputs: GuessInputs, plan: inout EntityRepository.Write) -> GuessedLink? {
        if let stored = inputs.choices.first(where: { $0.saidKey == SaidName.key(said.raw) }) {
            if stored.notAPerson { return nil }
            let aliases = [said.name, said.relation].compactMap { $0 }   // R8: the owner's answer teaches both halves
            switch stored.choice {
            case .person(let id): return GuessedLink(person: id, origin: .confirmed, aliases: aliases)
            // PC-b links the new person to the contact; until then a contact choice is a new person.
            case .newPerson, .contact:
                return plannedPerson(for: said, createdByGuess: false, card: inputs.card, plan: &plan)
                    .map { GuessedLink(person: $0, origin: .confirmed, aliases: aliases) }
            case nil: return nil   // `choices(for:)` gives no choice only for "not a person", handled above
            }
        }
        let result = PersonGuess.guess(said, people: inputs.known, contacts: inputs.contacts)
        switch result.choice {
        case .person(let id):
            return GuessedLink(person: id, origin: result.origin, aliases: result.origin == .said ? [said.relation].compactMap { $0 } : [])
        // PC-b replaces `.contact` with a person linked to that contact (rules 3 and 5).
        case .newPerson, .contact:
            return plannedPerson(for: said, createdByGuess: true, card: inputs.card, plan: &plan)
                .map { GuessedLink(person: $0, origin: .new, aliases: []) }
        }
    }

    /// A new person for a said name, planned once: a second ref with the same name in this
    /// card reaches the person already planned. Their name is the said name, or the relation
    /// phrase when no name was said; it becomes their alias when the plan is written.
    /// Nil when the ref holds no words.
    private func plannedPerson(for said: SaidName, createdByGuess: Bool, card: CandidateID?, plan: inout EntityRepository.Write) -> PersonID? {
        let name = (said.name ?? said.relation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = SaidName.key(name)
        guard !key.isEmpty else { return nil }
        if let planned = plan.persons.first(where: { SaidName.key($0.displayName) == key }) { return planned.id }
        let person = Person(id: .init(), displayName: name, notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                            nameOrigin: .said, createdByGuess: createdByGuess)
        plan.entities.append(Entity(id: person.entityID, type: .person, title: name, createdFromCandidateID: card))
        plan.persons.append(person)
        return person.id
    }
}
