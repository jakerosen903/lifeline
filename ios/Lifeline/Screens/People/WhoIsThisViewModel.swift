import Foundation
import LifelineKit

/// The "Who is this?" sheet for one said name. It reads who the name could be, holds the owner's selection,
/// and on "Done" settles the link, moves it, or stores the choice for a card that still waits.
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
        self.actions = PersonLinkActions(store: deps.extractionStore)
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
        // The same guess Keep runs, with no contacts: the people it found, minus the one already chosen.
        let guess = PersonGuess.guess(SaidName(ref: saidName), people: (try? store.personLinks.known()) ?? [], contacts: [])
        let candidates: [PersonID] = ([guess.choice] + guess.others).compactMap { choice in
            if case .person(let id) = choice, id != current { return id }
            return nil
        }
        options = WhoIsThisOptions.build(saidName: saidName, quote: quote, current: current, currentIsGuess: isGuess,
                                         candidates: candidates, people: people, otherMoments: others)
        if case .waiting(_, let chip) = source, chip.isNotAPerson {
            selected = .notAPerson   // the way back (R37): the sheet opens on the answer the owner gave
        } else {
            selected = current.map { .person($0) } ?? .someoneNew
        }
    }

    func cover(of person: PersonID) -> Photo? { covers[EntityID(rawValue: person.rawValue)] }

    func done() -> Outcome {
        let whole = wholeGroup && options.otherMoments > 0
        do {
            switch source {
            case .link(let link):
                let scope = whole ? groupOrigins : [link.origin]
                switch WhoIsThisDone.decide(keepsPerson: selected == .person(link.person.id), scope: scope) {
                case .nothing: return .unchanged
                case .settle:
                    try actions.settle(link, wholeGroup: whole)
                    return .settled
                case .move: return .moved(try actions.move(link, to: selected, wholeGroup: whole))
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
