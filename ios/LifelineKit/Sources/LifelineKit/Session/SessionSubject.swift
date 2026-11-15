import Foundation

/// The person, place or thing a session is about: it is where the person tapped "Tell a story".
/// The session's opening asks about it and links nothing; what is said is sorted afterwards as always.
public struct SessionSubject: Sendable, Equatable {
    public var entityID: EntityID
    public var title: String
    /// The subject is the owner themself, so the copy says "yourself" rather than their name.
    public var isOwner: Bool

    public init(entityID: EntityID, title: String, isOwner: Bool) {
        self.entityID = entityID; self.title = title; self.isOwner = isOwner
    }

    /// The record bar's label: it names the page the person is on.
    public static func barLabel(_ subject: SessionSubject?) -> String {
        guard let subject else { return "Tell a story" }
        return subject.isOwner ? "Tell a story about yourself" : "Tell a story about \(subject.title)"
    }

    /// The opening question when the subject has no question of its own waiting.
    var openingText: String {
        isOwner ? "Tell me something about yourself." : "Tell me about \(title)."
    }
}
