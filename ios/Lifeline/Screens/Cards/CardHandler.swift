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
    /// "Changed to {name}." with Undo, after the "Who is this?" sheet moved a name on a card.
    let personMove: PersonMoveUndo
    /// Read while a card renders, so they must not be observed. `peopleVersion` is, and a change to who is
    /// linked bumps it, so the chips are read again.
    @ObservationIgnored private var previews: [String: [PreviewChip]] = [:]
    /// The memory each kept card stands for. Its links are read on every render (one query).
    @ObservationIgnored private var keptMemories: [String: MemoryID] = [:]
    private var peopleVersion = 0
    let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
        personMove = PersonMoveUndo(actions: deps.personLinkActions())
        watchContacts()
    }

    /// A waiting card's chips come from the contacts cache. When a check refilled it, or the owner just gave access,
    /// they are read again, so a chip says what Keep will write (M-3). Each watch ends at the first notice after
    /// this handler is gone.
    private func watchContacts() {
        for name in [ContactsCheck.finished, ContactsAccessPrompt.accessGiven] {
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name).map({ _ in () }) {
                    guard let self else { return }
                    self.peopleChanged()
                }
            }
        }
    }

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
        if let memory {
            Task { await deps.duplicates.requestRun() }
            copyContactPictures(of: [memory.id])
        }
        return memory
    }

    /// Keep and "Same story" can make a person from a contact; the picture is copied after the write, off the main
    /// actor (I-2). The chips read again when a copy lands, so a face shows the picture.
    private func copyContactPictures(of memories: [MemoryID]) {
        let links = deps.contactLinks
        Task { [weak self] in
            var copied = false
            for memory in memories {
                let people = await Task.detached(priority: .utility) { await links.copyMissingPictures(of: memory) }.value
                copied = copied || !people.isEmpty
            }
            if copied { self?.peopleChanged() }
        }
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

    /// Keep on a memory card, the only card with one. Returns true when the card is done with.
    func accept(_ card: Card) -> Bool { keep(card) != nil }

    /// Keep on an entity card, as what it heard or as the type the person chose (M7).
    /// Returns the entity so the caller can open its page.
    func acceptEntity(_ card: Card, as type: EntityType?) -> Entity? {
        guard case .entity(let candidate, _) = card else { return nil }
        var kept: Entity?
        _ = attempt("Could not keep that") { kept = try deps.actions.acceptEntity(candidate, as: type) }
        return kept
    }

    // MARK: - Follow-ups on a kept card

    /// Follow-ups answered with "Not any of these", so their chips read as declined, not checked.
    private(set) var declined: Set<String> = []

    /// One tap on a hint, thing, place or idea chip: accepted as "Yes" or "Keep" did, or as the
    /// type chosen from its menu. Never opens a page. Returns true when the chip is answered.
    func acceptFollowUp(_ card: Card, as type: EntityType?) -> Bool {
        switch card {
        case .hint(let candidate, _):
            return attempt("Could not file that") { _ = try deps.actions.acceptHint(candidate) }
        case .entity:
            return acceptEntity(card, as: type) != nil
        case .memory, .whoIsThis, .kept:
            return false
        }
    }

    /// "Not any of these" on a chip: the follow-up is let go, with no undo notice.
    func declineFollowUp(_ card: Card) -> Bool {
        guard case .entity(let candidate, _) = card else { return false }
        let done = attempt("Could not dismiss that") { try deps.actions.dismiss(candidate) }
        if done { declined.insert(card.id) }
        return done
    }

    /// Suggestions dismissed moments ago by a kept card's close, while Undo is still offered.
    var keptClosedNotice: String? { recentKeptClose.notice }
    private var recentKeptClose = KeptCloseUndo()
    private var keptCloseTimer: Task<Void, Never>?

    /// A kept card closed: the hints and entities nobody answered are dismissed in one write, as
    /// "Not quite" did; a person nobody answered becomes an open mention for the People queue.
    /// When anything was dismissed the notice offers Undo for the usual window, because a card
    /// can close on another card's tap and the person must be able to take that back. A second
    /// close inside the window adds to the first and restarts the window, so one Undo takes both
    /// back. A close that dismissed nothing shows nothing and leaves an earlier notice standing.
    func close(_ closing: KeptClose) {
        let candidates = closing.dismiss.compactMap { card -> Candidate? in
            switch card {
            case .hint(let candidate, _), .entity(let candidate, _): candidate
            case .memory, .whoIsThis, .kept: nil
            }
        }
        var dismissed: [Candidate] = []
        if !candidates.isEmpty {
            _ = attempt("Could not dismiss that") { dismissed = try deps.actions.dismissAll(candidates) }
        }
        for card in closing.openAsMention { shown(card) }
        guard !dismissed.isEmpty else { return }
        recentKeptClose.add(cards: closing.undoable, dismissed: dismissed)
        keptCloseTimer?.cancel()
        keptCloseTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.recentKeptClose = KeptCloseUndo()
        }
    }

    /// Takes the recent closes back: every suggestion they dismissed waits again, in one write,
    /// and the kept cards are returned for the caller's stack. When the write fails nothing
    /// changes and the notice stays, so the person can try again inside the window. A name that
    /// went to the People queue stays there too; its chip answers the same mention.
    func undoKeptClose() -> [KeptCard] {
        let recent = recentKeptClose
        guard !recent.isEmpty, attempt("Could not bring that back", { try deps.actions.restoreAll(recent.dismissed) }) else { return [] }
        keptCloseTimer?.cancel()
        recentKeptClose = KeptCloseUndo()
        return recent.cards
    }

    /// Dismiss never touches the recording; for a few seconds it can be undone.
    func dismiss(_ card: Card) -> Bool {
        let done = attempt("Could not dismiss that") {
            switch card {
            case .memory(let candidate, _), .hint(let candidate, _), .entity(let candidate, _):
                try deps.actions.dismiss(candidate)
            case .whoIsThis:
                try deps.actions.resolveMention(try mention(for: card).id, to: .notAPerson)
            case .kept:
                // A kept card closes with Done; it is never dismissed.
                throw CandidateActions.Error.wrongKind
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
            case .kept:
                throw CandidateActions.Error.wrongKind
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
        copyContactPictures(of: [merged.receipt.target])
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

    // MARK: - Person chips

    /// What Keep would link for a memory card that waits, from Keep's own code path. Writes nothing.
    func previewChips(for card: Card) -> [PreviewChip] {
        _ = peopleVersion
        guard case .memory(let candidate, let out) = card else { return [] }
        // A continuation that arrives later grows the card; its names may add a chip.
        let key = "\(card.id)|\(out.extraSpans.count)"
        if let cached = previews[key] { return cached }
        let chips = (try? deps.personLinkActions().preview(candidate)) ?? []
        previews[key] = chips
        return chips
    }

    /// The people of a kept memory, the owner included when linked (R2).
    func personLinks(for memory: MemoryID) -> [PersonLink] {
        (try? deps.extractionStore.personLinks.links(of: memory)) ?? []
    }

    /// The people of the memory a kept card stands for: the one Keep made, or the one "Same story" joined.
    func personLinks(for kept: KeptCard) -> [PersonLink] {
        _ = peopleVersion
        let memory: MemoryID
        if let known = keptMemories[kept.memoryCandidateID] {
            memory = known
        } else {
            let candidate = CandidateID(rawValue: kept.memoryCandidateID)
            let memories = deps.extractionStore.memories
            guard let found = (try? memories.memory(createdFrom: candidate)) ?? (try? memories.memory(withSpanFrom: candidate)) else { return [] }
            memory = found.id
            keptMemories[kept.memoryCandidateID] = memory
        }
        // Read on every render, not cached: Change… edits a kept memory's people outside this handler.
        return personLinks(for: memory)
    }

    /// What "Done" in the sheet did: anything but `.unchanged` may change who a card shows.
    func personSheetDone(_ outcome: WhoIsThisViewModel.Outcome) {
        if case .unchanged = outcome { return }
        personMove.note(outcome)
        peopleChanged()
    }

    /// Undo under "Changed to {name}.". Returns true when the move was taken back.
    func undoPersonMove() -> Bool {
        let done = personMove.undo()
        if done { peopleChanged() }
        return done
    }

    /// Who is linked may have changed: every chip is read again on the next render. Called here after each
    /// write, and by a host when Change… closes, because that sheet edits a memory's people on its own.
    func peopleChanged() {
        previews.removeAll()
        keptMemories.removeAll()
        peopleVersion += 1
    }

    func resolve(_ card: Card, _ choice: MentionChoice) -> Bool { resolvePerson(card, choice).done }

    /// Resolve, and who the name turned out to be: nobody for "Not a person".
    func resolvePerson(_ card: Card, _ choice: MentionChoice) -> (done: Bool, person: Person?) {
        guard case .whoIsThis = card else { return (false, nil) }
        var person: Person?
        let done = attempt("Could not save that") { person = try deps.actions.resolveMention(try mention(for: card).id, to: choice) }
        if done { rankedChoices.removeAll() }
        return (done, person)
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
            // Keep, Same story, an answer or an undo can each change who a card's chips name.
            peopleChanged()
            return true
        } catch {
            self.error = "\(message): \(error.localizedDescription)"
            return false
        }
    }
}
