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
    private var suggestionCache: [String: [MemoryMatch]] = [:]
    /// Cards whose "Not part of it" was tapped: Keep lands them with no story (M5).
    private var optedOutOfStory: Set<String> = []
    /// Cards whose story line was rendered: Keep joins a story only when the card showed it.
    /// Written while a card renders, so it must not be observed or the render would loop.
    @ObservationIgnored private var storyLineShown: Set<String> = []
    /// "Are these the same?" answered moments ago, while Undo is still offered (M5).
    private(set) var pairNotice: String?
    private var recentPair: (pair: DuplicatePair, receipt: MergeReceipt?, grouped: CandidateActions.GroupedPair?)?
    private var pairTimer: Task<Void, Never>?
    /// Plays one side of a pair card.
    let pairPlayer = SegmentPlayer()
    private(set) var pairPlaying: MemoryID?
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

    /// Keep: the memory is created and returned, so Change… can open on it at once. The story
    /// membership the card showed rides along unless "Not part of it" was tapped. A little
    /// later the duplicate pass looks at what was just kept.
    func keep(_ card: Card) -> Memory? {
        guard case .memory(let candidate, _) = card else { return nil }
        var memory: Memory?
        let join = storyLineShown.contains(card.id) && !optedOutOfStory.contains(card.id)
        _ = attempt("Could not keep that") { memory = try deps.actions.acceptMemory(candidate, joinStory: join).memory }
        if memory != nil { Task { await deps.duplicates.requestRun() } }
        return memory
    }

    // MARK: - Stories on a card (M5)

    /// "Part of: X" or "Part of a new story with: Y", or nil when the card names no story the
    /// person could recognise. `cards` are the other cards on screen, for a story not yet kept.
    func storyLine(for card: Card, among cards: [Card]) -> String? {
        guard case .memory(_, let out) = card, let ref = out.storyRef, !optedOutOfStory.contains(card.id) else { return nil }
        let stories = deps.extractionStore.stories
        var line: String?
        if let story = try? stories.story(id: StoryID(rawValue: ref)), let members = try? stories.members(of: story.id), !members.isEmpty {
            line = "Part of: " + (story.title ?? members[0].title)
        } else {
            let other = cards.first { other in
                guard other.id != card.id, !optedOutOfStory.contains(other.id), case .memory(_, let o) = other else { return false }
                return o.storyRef == ref
            }
            if case .memory(_, let o)? = other { line = "Part of a new story with: " + o.title }
        }
        if line != nil { storyLineShown.insert(card.id) } else { storyLineShown.remove(card.id) }
        return line
    }

    func notPartOfStory(_ card: Card) { optedOutOfStory.insert(card.id) }

    /// Returns true when the card is done with.
    func accept(_ card: Card) -> Bool {
        switch card {
        case .memory:
            return keep(card) != nil
        case .hint(let candidate, _):
            return attempt("Could not file that") { _ = try deps.actions.acceptHint(candidate) }
        case .entity:
            return acceptEntity(card, as: nil) != nil
        case .whoIsThis:
            return false
        }
    }

    /// Keep on an entity card, as what it heard or as the type the person chose (M7).
    /// Returns the entity so the caller can open its page.
    func acceptEntity(_ card: Card, as type: EntityType?) -> Entity? {
        guard case .entity(let candidate, _) = card else { return nil }
        var kept: Entity?
        _ = attempt("Could not keep that") { kept = try deps.actions.acceptEntity(candidate, as: type) }
        return kept
    }

    /// Dismiss never touches the recording; for a few seconds it can be undone.
    func dismiss(_ card: Card) -> Bool {
        let done = attempt("Could not dismiss that") {
            switch card {
            case .memory(let candidate, _), .hint(let candidate, _), .entity(let candidate, _):
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
            case .memory(let candidate, _), .hint(let candidate, _), .entity(let candidate, _):
                try deps.actions.restore(candidate)
            case .whoIsThis:
                try deps.actions.restoreMention(try mention(for: card).id)
            }
        }
        return done ? card : nil
    }

    // MARK: - Same story (M4.1)

    /// The memory this card looks like a retelling of, or nil. Read once per card.
    func suggestion(for card: Card) -> MemoryMatch? { suggestions(for: card).first }

    /// Every memory the card names, then a strong vector match ("Same as X and n more?", M5).
    func suggestions(for card: Card) -> [MemoryMatch] {
        guard case .memory(_, let out) = card else { return [] }
        if let cached = suggestionCache[card.id] { return cached }
        let matches = (try? deps.matcher.suggestions(for: out, extractorSameAs: out.sameAsMemoryIDs.map(MemoryID.init(rawValue:)))) ?? []
        suggestionCache[card.id] = matches
        return matches
    }

    /// "Which one?": the nearest few, with the suggested one first.
    func pickerMatches(for card: Card) -> [MemoryMatch] {
        guard case .memory(_, let out) = card else { return [] }
        let text = MemoryMatcher.text(title: out.title, quote: out.quote)
        var matches = (try? deps.matcher.picker(for: text, excluding: [], includeHidden: false)) ?? []
        // Every suggested memory leads, in suggestion order, so a group's named ones are all listed.
        for suggested in suggestions(for: card).reversed() where !matches.contains(where: { $0.memoryID == suggested.memoryID }) { matches.insert(suggested, at: 0) }
        return matches
    }

    func isStrong(_ match: MemoryMatch) -> Bool { deps.matcher.isStrong(match) }

    /// The card becomes a later telling of the one memory named, or of the oldest of several
    /// (which the others fold into first). Undo stays open for the usual window.
    func sameStory(_ card: Card, into targets: [MemoryID]) -> Bool {
        guard case .memory(let candidate, _) = card, let first = targets.first else { return false }
        var merged: CandidateActions.MergedCandidate?
        let done = attempt("Could not add that") {
            merged = targets.count > 1 ? try deps.actions.mergeGroup(candidate, into: targets) : try deps.actions.mergeCandidate(candidate, into: first)
        }
        guard done, let merged else { return false }
        recentMerge = (card, merged.receipt)
        mergedNotice = "Added to \(merged.receipt.targetTitle)."
        suggestionCache[card.id] = nil
        mergeTimer?.cancel()
        mergeTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.mergedNotice = nil
            self?.recentMerge = nil
        }
        return true
    }

    // MARK: - Pairs (M5)

    /// Same story on a pair: the newer memory folds into the older. "Merged." with Undo.
    func samePair(_ pair: DuplicatePair) -> Bool {
        var receipt: MergeReceipt?
        let done = attempt("Could not merge those") { receipt = try deps.actions.samePair(pair) }
        if done { notePair(pair, receipt: receipt, grouped: nil, text: "Merged.") }
        return done
    }

    /// Keep separate: remembered, never asked again. "Kept separate." with Undo.
    func separatePair(_ pair: DuplicatePair) -> Bool {
        let done = attempt("Could not save that") { try deps.actions.separatePair(pair) }
        if done { notePair(pair, receipt: nil, grouped: nil, text: "Kept separate.") }
        return done
    }

    /// "Sounds like one story": both memories in one story.
    func groupPair(_ pair: DuplicatePair) -> Bool {
        var grouped: CandidateActions.GroupedPair?
        let done = attempt("Could not group those") { grouped = try deps.actions.groupPair(pair) }
        if done { notePair(pair, receipt: nil, grouped: grouped, text: "Grouped as one story.") }
        return done
    }

    /// Takes the last pair answer back: a merge comes apart, a separate or group is open again.
    func undoPair() -> Bool {
        guard let recent = recentPair else { return false }
        pairTimer?.cancel()
        pairNotice = nil
        recentPair = nil
        return attempt("That can't be undone any more") {
            if let receipt = recent.receipt {
                try deps.actions.undoPair(receipt, pair: recent.pair)
            } else if let grouped = recent.grouped {
                try deps.actions.ungroupPair(grouped)
            } else {
                try deps.extractionStore.pairs.setStatus(recent.pair.id, .open)
            }
        }
    }

    private func notePair(_ pair: DuplicatePair, receipt: MergeReceipt?, grouped: CandidateActions.GroupedPair?, text: String) {
        recentPair = (pair, receipt, grouped)
        pairNotice = text
        pairTimer?.cancel()
        pairTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.pairNotice = nil
            self?.recentPair = nil
        }
    }

    /// Play on a pair card: the memory's first telling; a second tap stops.
    func togglePairPlayback(_ memory: MemoryID) {
        if pairPlayer.isPlaying, pairPlaying == memory { pairPlayer.stop(); pairPlaying = nil; return }
        let store = deps.extractionStore
        _ = attempt("Could not play that") {
            guard let span = try store.memories.spans(of: memory).first,
                  let segment = try store.sessions.fetchSegment(span.segmentID),
                  let session = try store.sessions.fetch(segment.sessionID) else { return }
            try deps.activatePlayback()
            try pairPlayer.play(url: try deps.audioURL(for: session), range: MsRange(start: span.startMs, end: span.endMs))
            pairPlaying = memory
        }
    }

    func isPairPlaying(_ memory: MemoryID) -> Bool { pairPlayer.isPlaying && pairPlaying == memory }

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
