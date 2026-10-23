import Foundation
import LifelineKit

/// What a tap on a card does, shared by the session screen, the session detail and People.
/// A "Who's this?" card may stand on a candidate (live session) or on an open mention row
/// (People queue); either way one mention row answers it, created at most once.
@MainActor
@Observable
final class CardHandler {
    private(set) var error: String?
    /// The card dismissed moments ago, while Undo is still offered.
    private(set) var undoCard: Card?
    static let undoWindow: Duration = .seconds(6)
    private var recentDismiss = DismissUndo<Card>(window: CardHandler.undoWindow)
    private var undoTimer: Task<Void, Never>?
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

    /// Keep: the memory is created and returned, so Change… can open on it at once.
    func keep(_ card: Card) -> Memory? {
        guard case .memory(let candidate, _) = card else { return nil }
        var memory: Memory?
        _ = attempt("Could not keep that") { memory = try deps.actions.acceptMemory(candidate).memory }
        return memory
    }

    /// Returns true when the card is done with.
    func accept(_ card: Card) -> Bool {
        switch card {
        case .memory:
            return keep(card) != nil
        case .hint(let candidate, _):
            return attempt("Could not file that") { _ = try deps.actions.acceptHint(candidate) }
        case .whoIsThis:
            return false
        }
    }

    /// Dismiss never touches the recording; for a few seconds it can be undone.
    func dismiss(_ card: Card) -> Bool {
        let done = attempt("Could not dismiss that") {
            switch card {
            case .memory(let candidate, _), .hint(let candidate, _):
                try deps.actions.dismiss(candidate)
            case .whoIsThis:
                try deps.actions.resolveMention(try mention(for: card).id, to: .notAPerson)
            }
        }
        if done {
            recentDismiss.dismissed(card, at: .now)
            undoCard = card
            undoTimer?.cancel()
            undoTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.undoWindow)
                guard !Task.isCancelled else { return }
                self?.undoCard = nil
            }
        }
        return done
    }

    /// Brings the last dismissed card back, exactly as it was. Returns it for the caller's stack.
    func undo() -> Card? {
        guard let card = recentDismiss.take(at: .now) else { undoCard = nil; return nil }
        undoTimer?.cancel()
        undoCard = nil
        let done = attempt("Could not bring that back") {
            switch card {
            case .memory(let candidate, _), .hint(let candidate, _):
                try deps.actions.restore(candidate)
            case .whoIsThis:
                try deps.actions.restoreMention(try mention(for: card).id)
            }
        }
        return done ? card : nil
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
