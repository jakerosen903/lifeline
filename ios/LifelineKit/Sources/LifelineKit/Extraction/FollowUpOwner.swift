import Foundation

extension Card {
    /// A follow-up is asked under the memory it came from, never as a card of its own: a hint,
    /// an entity, or a fresh "Who's this?" from the live session. A memory, or a mention row from
    /// the People queue, is not one.
    public var isFollowUp: Bool {
        switch self {
        case .hint, .entity, .whoIsThis(.candidate, _): true
        case .memory, .whoIsThis(.mention, _), .kept: false
        }
    }
}

/// Pure: which memory a follow-up is asked under.
public enum FollowUpOwner {
    /// The candidate id of the owning memory, or nil when no memory refers to the follow-up.
    /// `memories` may come in any order; "first" is the lowest ordinal among those from the
    /// follow-up's segment. `excluding` holds dismissed memory candidate ids, which never own.
    public static func owner(of followUp: Card, among memories: [(Candidate, MemoryOut)], excluding: Set<String>) -> String? {
        if case .hint(_, let hint) = followUp {
            return excluding.contains(hint.memoryCandidateID) ? nil : hint.memoryCandidateID
        }
        guard let (candidate, mention) = source(of: followUp) else { return nil }
        let text = PeopleRepository.normalize(mention.text)
        return memories
            .filter { $0.0.segmentID == candidate.segmentID && !excluding.contains($0.0.id.rawValue) }
            .sorted { $0.0.ordinal < $1.0.ordinal }
            .first { refers($0.1, to: mention, normalizedText: text) }?.0.id.rawValue
    }

    private static func source(of card: Card) -> (Candidate, MentionOut)? {
        switch card {
        case .entity(let c, let m): (c, m)
        case .whoIsThis(.candidate(let c), _): CandidatePayload.mention(c).map { (c, $0) }
        default: nil
        }
    }

    private static func refers(_ memory: MemoryOut, to mention: MentionOut, normalizedText text: String) -> Bool {
        if let about = memory.aboutRef, about == mention.ref { return true }
        if mention.kind == .person { return memory.peopleRefs.contains { PeopleRepository.normalize($0) == text } }
        return memory.allEntityRefs.contains { $0.kind == mention.kind && PeopleRepository.normalize($0.text) == text }
    }
}
