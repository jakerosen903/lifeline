import Foundation

/// A memory card after Keep, while it still has follow-ups to ask: "Kept", the memory's title,
/// one chip per follow-up in the order the extractor emitted them, and "Done".
public struct KeptCard: Equatable, Sendable {
    public var memoryCandidateID: String
    public var title: String
    public var followUps: [Card]
    /// Ids of the follow-ups the person answered on this card.
    public var answered: Set<String>

    public init(memoryCandidateID: String, title: String, followUps: [Card], answered: Set<String> = []) {
        self.memoryCandidateID = memoryCandidateID; self.title = title; self.followUps = followUps; self.answered = answered
    }

    /// Every chip answered: the card closes by itself.
    public var isComplete: Bool { followUps.allSatisfy { answered.contains($0.id) } }

    /// The follow-ups still open, in chip order.
    var unanswered: [Card] { followUps.filter { !answered.contains($0.id) } }
}

/// What closing a kept card leaves for the app to do with the chips nobody answered: hints and
/// entities are dismissed, as "Not quite" did; a person becomes an open mention for the People queue.
public struct KeptClose: Equatable, Sendable {
    public var dismiss: [Card]
    public var openAsMention: [Card]

    public init(dismiss: [Card] = [], openAsMention: [Card] = []) {
        self.dismiss = dismiss; self.openAsMention = openAsMention
    }

    init(closing card: KeptCard) {
        self.init()
        for followUp in card.unanswered {
            if case .whoIsThis(.candidate, _) = followUp { openAsMention.append(followUp) } else { dismiss.append(followUp) }
        }
    }

    mutating func append(_ other: KeptClose) {
        dismiss += other.dismiss; openAsMention += other.openAsMention
    }
}
