import Foundation
import LifelineKit

@MainActor
@Observable
final class PeopleViewModel {
    struct PersonRow: Identifiable {
        let person: Person
        let aliases: [String]
        var id: PersonID { person.id }
    }

    private(set) var queue: [Card] = []
    private(set) var people: [PersonRow] = []
    private(set) var error: String?
    let cards: CardHandler
    private let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
        cards = CardHandler(deps: deps)
        refresh()
    }

    func refresh() {
        do {
            let store = deps.extractionStore
            // Unresolved mentions become who-is-this cards through their person candidates, so one
            // tap here resolves them the same way as in the session.
            let unresolvedTexts = Set(try store.people.mentions(status: .unresolved).map { PeopleRepository.normalize($0.text) })
            var seen = Set<String>()
            queue = try store.sessions.listSessions().flatMap { session in
                try store.candidates.pending(in: session.id) + acceptedMentionCandidates(in: session.id)
            }.compactMap { candidate -> Card? in
                guard case .whoIsThis(_, let mention)? = Card(candidate) else { return nil }
                let key = PeopleRepository.normalize(mention.text)
                guard unresolvedTexts.contains(key), seen.insert(key).inserted else { return nil }
                return Card(candidate)
            }
            people = try store.people.people().filter { !$0.isOwner }.map { person in
                PersonRow(person: person, aliases: try store.people.aliases(of: person.id).map(\.text).filter { $0 != person.displayName })
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Mention candidates already shown once (status accepted) whose mention is still open.
    private func acceptedMentionCandidates(in session: SessionID) throws -> [Candidate] {
        try deps.sessions.segments(in: session).flatMap { segment in
            try deps.extractionStore.candidates.candidates(for: segment.id).filter { $0.kind == .person && $0.status == .accepted }
        }
    }

    func resolve(_ card: Card, _ choice: MentionChoice) { if cards.resolve(card, choice) { refresh() } }
    func dismiss(_ card: Card) { if cards.dismiss(card) { refresh() } }
}
