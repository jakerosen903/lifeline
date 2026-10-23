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
    /// "Same story" moments ago, while Undo is still offered.
    private(set) var mergedNotice: String?
    private var recentMerge: (card: Card, receipt: MergeReceipt)?
    private var mergeTimer: Task<Void, Never>?
    private var suggestions: [String: MemoryMatch?] = [:]
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

    // MARK: - Same story (M4.1)

    /// The memory this card looks like a retelling of, or nil. Read once per card.
    func suggestion(for card: Card) -> MemoryMatch? {
        guard case .memory(_, let out) = card else { return nil }
        if let cached = suggestions[card.id] { return cached }
        let match = try? deps.matcher.suggestion(for: out, extractorSameAs: out.sameAsMemoryID.map(MemoryID.init(rawValue:)))
        suggestions[card.id] = .some(match)
        return match
    }

    /// "Which one?": the nearest few, with the suggested one first.
    func pickerMatches(for card: Card) -> [MemoryMatch] {
        guard case .memory(_, let out) = card else { return [] }
        let text = MemoryMatcher.text(title: out.title, quote: out.quote)
        var matches = (try? deps.matcher.picker(for: text, excluding: [], includeHidden: false)) ?? []
        if let suggested = suggestion(for: card), !matches.contains(where: { $0.memoryID == suggested.memoryID }) { matches.insert(suggested, at: 0) }
        return matches
    }

    func isStrong(_ match: MemoryMatch) -> Bool { deps.matcher.isStrong(match) }

    /// The card becomes a later telling of `target`. Undo stays open for the usual window.
    func sameStory(_ card: Card, into target: MemoryID) -> Bool {
        guard case .memory(let candidate, _) = card else { return false }
        var merged: CandidateActions.MergedCandidate?
        let done = attempt("Could not add that") { merged = try deps.actions.mergeCandidate(candidate, into: target) }
        guard done, let merged else { return false }
        recentMerge = (card, merged.receipt)
        mergedNotice = "Added to \(merged.receipt.targetTitle)."
        suggestions[card.id] = nil
        mergeTimer?.cancel()
        mergeTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.mergedNotice = nil
            self?.recentMerge = nil
        }
        return true
    }

    /// Takes the last Same story back; the card returns for the caller's stack.
    func undoMerge() -> Card? {
        guard let recent = recentMerge else { return nil }
        mergeTimer?.cancel()
        mergedNotice = nil
        recentMerge = nil
        let done = attempt("That can't be undone any more") { try deps.actions.unmerge(recent.receipt) }
        return done ? recent.card : nil
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
