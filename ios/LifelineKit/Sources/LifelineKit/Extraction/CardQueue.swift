import Foundation

/// A card the person can act on.
public enum Card: Identifiable, Equatable, Sendable {
    case memory(Candidate, MemoryOut)
    case whoIsThis(Candidate, MentionOut)

    public var id: CandidateID {
        switch self {
        case .memory(let c, _), .whoIsThis(let c, _): c.id
        }
    }

    public var candidate: Candidate {
        switch self {
        case .memory(let c, _), .whoIsThis(let c, _): c
        }
    }

    public init?(_ candidate: Candidate) {
        switch candidate.kind {
        case .memory:
            guard let out = CandidatePayload.memory(candidate) else { return nil }
            self = .memory(candidate, out)
        case .person:
            guard let out = CandidatePayload.mention(candidate) else { return nil }
            self = .whoIsThis(candidate, out)
        case .place, .flag:
            return nil
        }
    }
}

/// Pure: turns extraction events into the cards on screen, in order. After a serious
/// disclosure no new memory cards appear for the session (the fixed response is M4);
/// "Who's this?" cards still do, since they ask about a name, not a memory.
public struct CardQueue: Equatable, Sendable {
    public private(set) var cards: [Card] = []
    public private(set) var suppressed = false

    public init() {}

    public mutating func apply(_ event: ExtractionEvent) {
        switch event {
        case .flags(let flags, _):
            if flags.seriousDisclosure { suppressed = true }
        case .candidates(let candidates, _):
            for candidate in candidates {
                guard let card = Card(candidate), !cards.contains(where: { $0.id == card.id }) else { continue }
                if suppressed, case .memory = card { continue }
                cards.append(card)
            }
        case .failed, .skipped:
            break
        }
    }

    public mutating func remove(_ id: CandidateID) {
        cards.removeAll { $0.id == id }
    }
}
