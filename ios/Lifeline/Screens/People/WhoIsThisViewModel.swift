import Foundation
import LifelineKit

/// The "Who is this?" sheet for one said name. It reads who the name could be (the people on file, then the free
/// contacts that fit), holds the owner's selection, and on "Done" settles the link, moves it, or stores the choice for
/// a card that still waits. A contact picked in the search becomes the selection; only "Done" moves.
@MainActor
@Observable
final class WhoIsThisViewModel {
    enum Source {
        case link(PersonLink)
        case waiting(candidate: Candidate, chip: PreviewChip)
    }

    enum Outcome {
        case unchanged, settled, moved(PersonMoveReceipt), stored, failed(String)
    }

    private(set) var options: WhoIsThisOptions
    var selected: PersonLinkActions.Target
    /// What the app may do with the contacts: the search row asks, searches, or sends the owner to Settings.
    private(set) var access: ContactsAccess
    /// The person who holds each linked contact, by identifier. Picking that contact is a move to them.
    private let holders: [String: Person]
    var heldNames: [String: String] { holders.mapValues(\.displayName) }
    let deps: Dependencies
    /// "Also change the other moments": on by default.
    var wholeGroup = true
    /// Every person's key photo, for the faces.
    let covers: [EntityID: Photo]
    let photoImages: PhotoImageCache

    private let source: Source
    private let actions: PersonLinkActions
    /// The origins of the tapped link's group (itself included), read when the sheet opens. "Done" with the
    /// same person settles when any link in the chosen scope is still open (M6); the write re-reads them.
    private let groupOrigins: [LinkOrigin?]

    init(source: Source, deps: Dependencies) {
        self.source = source
        self.deps = deps
        self.actions = deps.personLinkActions()
        self.photoImages = deps.photoImages
        let store = deps.extractionStore
        covers = (try? store.photos.covers(type: .person)) ?? [:]

        let saidName: String, quote: String?, current: PersonID?, isGuess: Bool, others: Int
        switch source {
        case .link(let link):
            saidName = link.saidName ?? link.person.displayName
            quote = (try? store.memories.fetch(link.memoryID))?.summaryQuote
            current = link.person.id
            isGuess = link.isGuess
            let group = (try? store.personLinks.group(of: link)) ?? [link]
            groupOrigins = group.map(\.origin)
            others = max(0, group.count - 1)
        case .waiting(let candidate, let chip):
            saidName = chip.saidName
            quote = CandidatePayload.memory(candidate)?.quote
            current = chip.person
            isGuess = chip.origin == .assumed
            groupOrigins = []
            others = 0
        }
        let people = ((try? store.people.people()) ?? []).map { person in
            let stories = ((try? store.personLinks.links(to: person.id)) ?? []).filter { $0.relation == .mention }.count
            return (person, stories: stories)
        }
        holders = Dictionary(people.compactMap { entry in entry.0.contactIdentifier.map { ($0, entry.0) } }, uniquingKeysWith: { first, _ in first })
        let access = deps.contacts.access()
        self.access = access
        let cards = WhoIsThisOptions.offered(deps.contactsCache.cards, access: access)
        // The same guess Keep runs, with no contacts: the people it found, minus the one already chosen.
        let guess = PersonGuess.guess(SaidName(ref: saidName), people: (try? store.personLinks.known()) ?? [], contacts: [])
        let candidates: [PersonID] = ([guess.choice] + guess.others).compactMap { choice in
            if case .person(let id) = choice, id != current { return id }
            return nil
        }
        var built = WhoIsThisOptions.build(saidName: saidName, quote: quote, current: current, currentIsGuess: isGuess,
                                           candidates: candidates, people: people, contacts: cards, otherMoments: others)
        if case .waiting(_, let chip) = source, chip.isNotAPerson {
            selected = .notAPerson   // the way back (R37): the sheet opens on the answer the owner gave
        } else if case .waiting(let candidate, let chip) = source, let chosen = Self.storedContact(for: chip, on: candidate, in: cards, deps: deps) {
            // A contact chosen before: the sheet opens on it, so "Done" does not quietly replace it with "Someone new".
            built = built.adding(chosen, heldBy: nil)
            selected = .contact(chosen)
        } else if case .waiting(_, let chip) = source, chip.person == nil, let identifier = chip.contactIdentifier,
                  let guessed = cards.first(where: { $0.identifier == identifier }) {
            // Keep would make the person from this contact (rules 3 and 5): the sheet opens on it, so "Done" with
            // nothing changed keeps the contact rather than "Someone new" (I-1). A contact gone from the cache since
            // the chip was made falls to "Someone new", as Keep would then.
            built = built.withCurrentContact(guessed)
            selected = .contact(guessed)
        } else {
            selected = current.map { .person($0) } ?? .someoneNew
        }
        options = built
    }

    /// The contact the owner chose for this said name on a waiting card, while the app can still see it.
    private static func storedContact(for chip: PreviewChip, on candidate: Candidate, in cards: [ContactCard], deps: Dependencies) -> ContactCard? {
        let choices = (try? deps.extractionStore.personLinks.choices(for: candidate.id)) ?? []
        guard case .contact(let identifier)? = choices.first(where: { $0.saidKey == chip.id })?.choice else { return nil }
        return cards.first { $0.identifier == identifier }
    }

    /// "Search your contacts": with access not asked, the one system prompt first (the same path as the landing's,
    /// so the "asked" flag and the cache behave the same). True when the search can open.
    func prepareSearch() async -> Bool {
        if access == .notAsked { access = await ContactsAccessPrompt(deps: deps).ask() }
        return access == .full || access == .limited
    }

    /// A contact picked in the search becomes a row and the selection. Picking moves nothing.
    func pick(_ card: ContactCard) {
        options = options.adding(card, heldBy: holders[card.identifier]?.displayName)
        selected = .contact(card)
    }

    /// The selection as the move will apply it: a contact a person holds is that person.
    private var target: PersonLinkActions.Target {
        if case .contact(let card) = selected, let holder = holders[card.identifier] { return .person(holder.id) }
        return selected
    }

    func cover(of person: PersonID) -> Photo? { covers[EntityID(rawValue: person.rawValue)] }

    /// The contact's picture for the person the move made, off the main actor. The move's Undo still works after it.
    private func copyPicture(for person: PersonID) {
        let links = deps.contactLinks
        Task.detached(priority: .utility) {
            // A picture that cannot be read or stored is dropped: the next check copies a missing picture (PB16).
            try? await links.copyPicture(for: person)
        }
    }

    func done() -> Outcome {
        let whole = wholeGroup && options.otherMoments > 0
        do {
            switch source {
            case .link(let link):
                let scope = whole ? groupOrigins : [link.origin]
                let target = self.target
                switch WhoIsThisDone.decide(keepsPerson: target == .person(link.person.id), scope: scope) {
                case .nothing: return .unchanged
                case .settle:
                    try actions.settle(link, wholeGroup: whole)
                    return .settled
                case .move:
                    let receipt = try actions.move(link, to: target, wholeGroup: whole)
                    if case .contact = target, let made = receipt.createdPerson { copyPicture(for: made) }
                    return .moved(receipt)
                }
            case .waiting(let candidate, let chip):
                try actions.choose(selected, for: chip.saidName, on: candidate.id)
                return .stored
            }
        } catch is PersonLinkActions.Error {
            return .failed(PersonChipLine.staleUndo)
        } catch {
            return .failed("Could not change this.")
        }
    }
}
