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

    public var id: String {
        switch self {
        case .memory(let c, _), .hint(let c, _), .entity(let c, _): c.id.rawValue
        case .whoIsThis(.candidate(let c), _): c.id.rawValue
        case .whoIsThis(.mention(let m), _): m.id.rawValue
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

/// Pure: turns extraction events into the cards on screen, in order. After a heavy moment (a
/// disclosure, a wish to stop) no organizational prompt of any kind appears for the rest of the
/// session; the candidates are still stored and wait on the timeline afterwards.
public struct CardQueue: Equatable, Sendable {
    public private(set) var cards: [Card] = []
    public private(set) var suppressed = false
    /// Hint cards waiting for their memory, keyed by the memory candidate's id.
    private var heldHints: [String: [Card]] = [:]

    public init() {}

    public var heldHintCount: Int { heldHints.values.reduce(0) { $0 + $1.count } }

    /// "N possible memories" on the Listen view: memory cards not yet kept or dismissed.
    public var possibleMemoryCount: Int {
        cards.reduce(0) { if case .memory = $1 { $0 + 1 } else { $0 } }
    }

    public mutating func apply(_ event: ExtractionEvent) {
        switch event {
        case .flags(let flags, _):
            if flags.isHeavy { suppressed = true }
        case .candidates(let candidates, _):
            for candidate in candidates {
                guard let card = Card(candidate) else { continue }
                // A card emitted again carries a changed payload (a continuation, M5): same place, new words.
                if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card; continue }
                // A heavy moment suppresses every organizational prompt, who-is-this included.
                if suppressed { continue }
                if case .hint(_, let out) = card {
                    heldHints[out.memoryCandidateID, default: []].append(card)
                    continue
                }
                cards.append(card)
            }
        case .failed, .skipped:
            break
        }
    }

    /// Cards for candidates still pending after a session: a hint shows only once its memory
    /// was accepted, and never when the memory was declined or is unknown.
    public static func waitingCards(pending: [Candidate], statusOf: (CandidateID) -> CandidateStatus?) -> [Card] {
        pending.compactMap { candidate in
            guard let card = Card(candidate) else { return nil }
            if case .hint(_, let out) = card {
                return statusOf(CandidateID(rawValue: out.memoryCandidateID)) == .accepted ? card : nil
            }
            return card
        }
    }

    /// The memory was added: its hints become cards.
    public mutating func memoryAccepted(_ memoryCandidateID: String) {
        guard let hints = heldHints.removeValue(forKey: memoryCandidateID) else { return }
        for hint in hints where !cards.contains(where: { $0.id == hint.id }) { cards.append(hint) }
    }

    /// The memory was declined: its hints are dropped unseen.
    public mutating func memoryDismissed(_ memoryCandidateID: String) {
        heldHints[memoryCandidateID] = nil
    }

    /// Undo: a card dismissed moments ago comes back at the end of the stack.
    public mutating func restore(_ card: Card) {
        guard !cards.contains(where: { $0.id == card.id }) else { return }
        cards.append(card)
    }

    public mutating func remove(_ id: String) {
        cards.removeAll { $0.id == id }
    }
}
