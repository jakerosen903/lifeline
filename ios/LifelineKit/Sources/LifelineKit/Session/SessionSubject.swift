import Foundation

/// The person, place or thing a session is about: it is where the person tapped "Tell a story".
/// The session's opening asks about it and links nothing; what is said is sorted afterwards as always.
public struct SessionSubject: Sendable, Equatable {
    public var entityID: EntityID
    public var title: String
    /// The subject is the owner themself, so the copy says "yourself" rather than their name.
    public var isOwner: Bool
    /// The person kept this entity from the AI: its title must not reach the interviewer's opening.
    public var excludedFromAI: Bool

    public init(entityID: EntityID, title: String, isOwner: Bool, excludedFromAI: Bool = false) {
        self.entityID = entityID; self.title = title; self.isOwner = isOwner; self.excludedFromAI = excludedFromAI
    }

    /// The record bar's label: it names the page the person is on.
    public static func barLabel(_ subject: SessionSubject?) -> String {
        guard let subject else { return "Tell a story" }
        return subject.isOwner ? "Tell a story about yourself" : "Tell a story about \(subject.title)"
    }

    /// The opening question when the subject has no question of its own waiting.
    /// The title is never empty: `EntityRepository.rename` rejects an empty one.
    var openingText: String {
        isOwner ? "Tell me something about yourself." : "Tell me about \(title)."
    }
}
