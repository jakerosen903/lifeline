import Foundation
import LifelineKit

/// What a tap on a card does, shared by the session screen, the session detail and People.
/// A "Who's this?" card may stand on a candidate (live session) or on an open mention row
/// (People queue); either way one mention row answers it, created at most once.
@MainActor
@Observable
final class CardHandler {
    private(set) var error: String?
    private var mentions: [String: Mention] = [:]
    private var rankedChoices: [String: [Person]] = [:]
    private let deps: Dependencies

    init(deps: Dependencies) { self.deps = deps }

    /// Called when a card is first shown. Writes the mention row for a who-is-this card so the
    /// People queue survives a kill before the person answers.
    func shown(_ card: Card) {
        guard case .whoIsThis(let source, _) = card, mentions[card.id] == nil else { return }
        switch source {
        case .candidate(let candidate): mentions[card.id] = try? deps.actions.acceptMention(candidate)
        case .mention(let mention): mentions[card.id] = mention
        }
    }

    /// Returns true when the card is done with.
    func accept(_ card: Card) -> Bool {
        guard case .memory(let candidate, _) = card else { return false }
        return attempt("Could not add that") { _ = try deps.actions.acceptMemory(candidate) }
    }

    func dismiss(_ card: Card) -> Bool {
        attempt("Could not dismiss that") {
            switch card {
            case .memory(let candidate, _):
                try deps.actions.dismiss(candidate)
            case .whoIsThis:
                try deps.actions.resolveMention(try mention(for: card).id, to: .notAPerson)
            }
        }
    }

    func resolve(_ card: Card, _ choice: MentionChoice) -> Bool {
        guard case .whoIsThis = card else { return false }
        let done = attempt("Could not save that") { try deps.actions.resolveMention(try mention(for: card).id, to: choice) }
        if done { rankedChoices.removeAll() }
        return done
    }

    /// Everyone but the owner, closest names first, so a known person is always reachable.
    /// Cached per name until a resolve changes the people.
    func peopleChoices(for text: String) -> [Person] {
        let key = PeopleRepository.normalize(text)
        if let cached = rankedChoices[key] { return cached }
        let repo = deps.extractionStore.people
        let people = ((try? repo.people()) ?? []).filter { !$0.isOwner }
        var aliases: [PersonID: [String]] = [:]
        for person in people { aliases[person.id] = (try? repo.aliases(of: person.id))?.map(\.text) ?? [] }
        let ranked = PersonMatcher.rank(people, aliases: aliases, for: text)
        rankedChoices[key] = ranked
        return ranked
    }

    private func mention(for card: Card) throws -> Mention {
        if let known = mentions[card.id] { return known }
        guard case .whoIsThis(let source, _) = card else { throw CandidateActions.Error.wrongKind }
        let row: Mention
        switch source {
        case .candidate(let candidate): row = try deps.actions.acceptMention(candidate)
        case .mention(let mention): row = mention
        }
        mentions[card.id] = row
        return row
    }

    private func attempt(_ message: String, _ work: () throws -> Void) -> Bool {
        do {
            try work()
            error = nil
            return true
        } catch {
            self.error = "\(message): \(error.localizedDescription)"
            return false
        }
    }
}
