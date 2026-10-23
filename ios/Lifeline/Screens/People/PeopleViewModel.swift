import Foundation
import LifelineKit

@MainActor
@Observable
final class PeopleViewModel {
    struct PersonRow: Identifiable {
        let person: Person
        let aliases: [String]
        let relation: String?
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
            // Every open mention is a question, whether it came from a mention candidate or from a
            // memory's people. One card per name; answering it resolves the name everywhere.
            var seen = Set<String>()
            queue = try store.people.mentions(status: .unresolved)
                .filter { seen.insert(PeopleRepository.normalize($0.text)).inserted }
                .map(Card.init)
            people = try store.people.people().filter { !$0.isOwner }.map { person in
                let aliases = try store.people.aliases(of: person.id)
                return PersonRow(person: person,
                                 aliases: aliases.map(\.text).filter { $0 != person.displayName },
                                 relation: PeopleRepository.relationLabel(aliases: aliases))
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func resolve(_ card: Card, _ choice: MentionChoice) { if cards.resolve(card, choice) { refresh() } }
    func dismiss(_ card: Card) { if cards.dismiss(card) { refresh() } }

    /// Fixes a spelling. The old spelling stays as an alias so later transcripts still link.
    func rename(_ person: Person, to name: String) {
        do {
            try deps.extractionStore.people.rename(person.id, to: name)
            error = nil
            refresh()
        } catch {
            self.error = "Could not rename: \(error.localizedDescription)"
        }
    }
}
