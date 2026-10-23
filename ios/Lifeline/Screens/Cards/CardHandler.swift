import Foundation
import LifelineKit

/// What a tap on a card does, shared by the session screen and the session detail.
/// Keeps the mention row for each "Who's this?" card so resolving never creates a second one.
@MainActor
@Observable
final class CardHandler {
    private(set) var error: String?
    private var mentions: [CandidateID: Mention] = [:]
    private let deps: Dependencies

    init(deps: Dependencies) { self.deps = deps }

    /// Called when a card is first shown. Writes the mention row for a who-is-this card so the
    /// People queue survives a kill before the person answers.
    func shown(_ card: Card) {
        guard case .whoIsThis(let candidate, _) = card, mentions[card.id] == nil else { return }
        mentions[card.id] = try? deps.actions.acceptMention(candidate)
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
            case .whoIsThis(let candidate, _):
                let mention = try mentions[card.id] ?? deps.actions.acceptMention(candidate)
                try deps.actions.resolveMention(mention.id, to: .notAPerson)
            }
        }
    }

    func resolve(_ card: Card, _ choice: MentionChoice) -> Bool {
        guard case .whoIsThis(let candidate, _) = card else { return false }
        return attempt("Could not save that") {
            let mention = try mentions[card.id] ?? deps.actions.acceptMention(candidate)
            try deps.actions.resolveMention(mention.id, to: choice)
        }
    }

    /// People to offer on a "Who's this?" card: up to three, owner excluded.
    func peopleChoices() -> [Person] {
        ((try? deps.extractionStore.people.people()) ?? []).filter { !$0.isOwner }.prefix(3).map { $0 }
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
