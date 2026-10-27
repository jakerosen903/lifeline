import Foundation

/// Where a "Who's this?" card comes from: a fresh candidate in the live session, or a mention
/// row that is still open (the People queue, names a memory listed without a mention).
public enum WhoSource: Equatable, Sendable {
    case candidate(Candidate)
    case mention(Mention)
}

/// A card the person can act on.
public enum Card: Identifiable, Equatable, Sendable {
    case memory(Candidate, MemoryOut)
    case whoIsThis(WhoSource, text: String)
    case hint(Candidate, HintOut)
    /// "Sounds like a thing you had" / a place / something you think (M7).
    case entity(Candidate, MentionOut)
    /// A memory after Keep, still asking its follow-ups.
    case kept(KeptCard)

    public var id: String {
        switch self {
        case .memory(let c, _), .hint(let c, _), .entity(let c, _): c.id.rawValue
        case .whoIsThis(.candidate(let c), _): c.id.rawValue
        case .whoIsThis(.mention(let m), _): m.id.rawValue
        case .kept(let k): k.memoryCandidateID
        }
    }

    public init?(_ candidate: Candidate) {
        switch candidate.kind {
        case .memory:
            guard let out = CandidatePayload.memory(candidate) else { return nil }
            self = .memory(candidate, out)
        case .person:
            guard let out = CandidatePayload.mention(candidate) else { return nil }
            self = .whoIsThis(.candidate(candidate), text: out.text)
        case .hint:
            guard let out = CandidatePayload.hint(candidate) else { return nil }
            self = .hint(candidate, out)
        case .entity:
            guard let out = CandidatePayload.mention(candidate) else { return nil }
            self = .entity(candidate, out)
        case .place, .flag:
            return nil
        }
    }

    public init(_ mention: Mention) {
        self = .whoIsThis(.mention(mention), text: mention.text)
    }
}

/// Pure: turns extraction events into the cards on screen, in order. A follow-up is never a card
/// of its own: it is held under its owner memory (`FollowUpOwner`) and shows as a chip once that
/// memory is kept. After a heavy moment (a disclosure, a wish to stop) no organizational prompt of
/// any kind appears for the rest of the session, chips included; the candidates are still stored
/// and wait on the timeline afterwards.
public struct CardQueue: Equatable, Sendable {
    public private(set) var cards: [Card] = []
    public private(set) var suppressed = false
    /// Every memory candidate seen, by id: ownership and the titles of kept cards come from here.
    private var memories: [String: RememberedMemory] = [:]
    /// Follow-ups not yet on a kept card, in emitted order. Never dropped: a dismissed owner passes
    /// them on or leaves them hidden.
    private var held: [Card] = []
    private var accepted: Set<String> = []
    private var dismissed: Set<String> = []

    public init() {}

    /// "N possible memories" on the Listen view: memory cards not yet kept or dismissed.
    public var possibleMemoryCount: Int {
        cards.reduce(0) { if case .memory = $1 { $0 + 1 } else { $0 } }
    }

    public mutating func apply(_ event: ExtractionEvent) {
        switch event {
        case .flags(let flags, _):
            if flags.isHeavy { suppressed = true }
        case .candidates(let candidates, _):
            for card in candidates.compactMap(Card.init) { take(card) }
            release()
        case .failed, .skipped:
            break
        }
    }

    /// The cards waiting after a session, as a queue the app keeps and closes with the same calls as
    /// the live session. A pending memory shows with its pending follow-ups held; follow-ups whose
    /// memory was already kept show as one kept card for it; those whose memory was dismissed, or
    /// that have none, do not show. `segmentMemories` gives a segment's candidates of any status;
    /// `candidate` looks one up by id (a continuation's hint names a memory from another segment).
    public static func waiting(pending: [Candidate], segmentMemories: (SegmentID) -> [Candidate],
                               candidate: (CandidateID) -> Candidate?) -> CardQueue {
        var queue = CardQueue()
        var segments = Set<SegmentID>()
        for segment in pending.map(\.segmentID) where segments.insert(segment).inserted {
            for memory in segmentMemories(segment) { queue.remember(memory) }
        }
        let cards = pending.compactMap(Card.init)
        for case .hint(_, let hint) in cards where queue.memories[hint.memoryCandidateID] == nil {
            if let memory = candidate(CandidateID(rawValue: hint.memoryCandidateID)) { queue.remember(memory) }
        }
        func status(_ id: String) -> CandidateStatus? { candidate(CandidateID(rawValue: id))?.status }
        queue.dismissed = Set(queue.memories.keys.filter { status($0) == .dismissed })
        let owners = cards.filter(\.isFollowUp).compactMap(queue.owner)
        queue.accepted = Set(owners.filter { status($0) == .accepted })
        for card in cards {
            queue.take(card)
            queue.release()
        }
        return queue
    }

    /// The memory was kept (or joined an earlier one): it becomes a kept card in place when it has
    /// follow-ups, and leaves otherwise. After a heavy moment it always leaves; its follow-ups stay
    /// held and pending in the store.
    public mutating func memoryAccepted(_ memoryCandidateID: String) {
        accepted.insert(memoryCandidateID)
        release()
        if let i = cards.firstIndex(where: { $0.id == memoryCandidateID }), case .memory = cards[i] { cards.remove(at: i) }
    }

    /// The memory was declined: its card leaves and its follow-ups pass to the next memory that
    /// refers to them, or stay hidden.
    public mutating func memoryDismissed(_ memoryCandidateID: String) {
        dismissed.insert(memoryCandidateID)
        remove(memoryCandidateID)
        release()
    }

    /// Undo: a card dismissed moments ago comes back at the end of the stack. A memory takes its
    /// follow-ups back; one that had become a kept card turns back into the memory card in place.
    public mutating func restore(_ card: Card) {
        if case .memory(let candidate, let out) = card {
            accepted.remove(card.id); dismissed.remove(card.id)
            memories[card.id] = RememberedMemory(candidate: candidate, out: out)
            if let i = keptIndex(card.id), case .kept(let k) = cards[i] {
                held = k.unanswered + held
                cards[i] = card
                return
            }
        }
        guard !cards.contains(where: { $0.id == card.id }) else { return }
        cards.append(card)
    }

    /// A chip on a kept card was answered. Returns whether every chip on it now is.
    public mutating func answered(_ followUpID: String, in memoryCandidateID: String) -> Bool {
        guard let i = keptIndex(memoryCandidateID), case .kept(var k) = cards[i] else { return false }
        k.answered.insert(followUpID)
        cards[i] = .kept(k)
        return k.isComplete
    }

    /// "Done", or every chip answered: the kept card leaves; what was left unanswered comes back.
    public mutating func closeKept(_ memoryCandidateID: String) -> KeptClose {
        guard let i = keptIndex(memoryCandidateID), case .kept(let k) = cards.remove(at: i) else { return KeptClose() }
        return KeptClose(closing: k)
    }

    /// Another memory card was acted on: every open kept card closes as if "Done" was tapped.
    public mutating func closeAllKept() -> KeptClose {
        var close = KeptClose()
        while let k = cards.first(where: { if case .kept = $0 { true } else { false } }) { close.append(closeKept(k.id)) }
        return close
    }

    public mutating func remove(_ id: String) {
        cards.removeAll { $0.id == id }
    }

    // MARK: - Holding follow-ups

    /// One card from an event: a memory is remembered and shown; a follow-up is held, or replaced
    /// where it already is (a continuation re-emits a card with a changed payload).
    private mutating func take(_ card: Card) {
        if case .memory(let candidate, _) = card { remember(candidate) }
        if card.isFollowUp {
            if let i = held.firstIndex(where: { $0.id == card.id }) { held[i] = card } else if !replaceChip(card) { held.append(card) }
            return
        }
        if let i = cards.firstIndex(where: { $0.id == card.id }) {
            // Same place, new words; a kept card keeps its chips and takes the new title.
            if case .kept(var k) = cards[i] { k.title = title(of: k.memoryCandidateID); cards[i] = .kept(k) } else { cards[i] = card }
            return
        }
        // A memory already kept or dismissed is settled: a continuation never brings its card back.
        if accepted.contains(card.id) || dismissed.contains(card.id) { return }
        // A heavy moment suppresses every organizational prompt.
        if !suppressed { cards.append(card) }
    }

    /// Moves every held follow-up whose owner was kept onto that memory's kept card: the open one,
    /// the memory card itself (turned kept in place), or a new kept card at the end.
    private mutating func release() {
        guard !suppressed else { return }
        var still: [Card] = []
        for followUp in held {
            // An owner the queue never saw has no title to show: the follow-up stays held.
            guard let owner = owner(of: followUp), accepted.contains(owner), memories[owner] != nil else { still.append(followUp); continue }
            if let i = keptIndex(owner), case .kept(var k) = cards[i] {
                k.followUps.append(followUp)
                cards[i] = .kept(k)
            } else {
                let k = Card.kept(KeptCard(memoryCandidateID: owner, title: title(of: owner), followUps: [followUp]))
                if let i = cards.firstIndex(where: { $0.id == owner }) { cards[i] = k } else { cards.append(k) }
            }
        }
        held = still
    }

    /// Replaces a follow-up already showing as a chip. Returns false when it is not on any kept card.
    private mutating func replaceChip(_ card: Card) -> Bool {
        for (i, shown) in cards.enumerated() {
            guard case .kept(var k) = shown, let j = k.followUps.firstIndex(where: { $0.id == card.id }) else { continue }
            k.followUps[j] = card
            cards[i] = .kept(k)
            return true
        }
        return false
    }

    private mutating func remember(_ candidate: Candidate) {
        guard candidate.kind == .memory, let out = CandidatePayload.memory(candidate) else { return }
        memories[candidate.id.rawValue] = RememberedMemory(candidate: candidate, out: out)
    }

    private func owner(of followUp: Card) -> String? {
        FollowUpOwner.owner(of: followUp, among: memories.values.map { ($0.candidate, $0.out) }, excluding: dismissed)
    }

    /// Only called for remembered memories; the empty fallback is never shown.
    private func title(of memoryCandidateID: String) -> String { memories[memoryCandidateID]?.out.title ?? "" }

    private func keptIndex(_ memoryCandidateID: String) -> Int? {
        cards.firstIndex { if case .kept(let k) = $0 { k.memoryCandidateID == memoryCandidateID } else { false } }
    }
}

/// A memory candidate as the queue last saw it.
private struct RememberedMemory: Equatable, Sendable {
    var candidate: Candidate
    var out: MemoryOut
}
