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

    /// The name the interviewer's model may hear in the opening (`NameForModel`). nil for a person whose
    /// name came from a contact and who has no said name: the opening is then the plain tab opening (PB10).
    public var modelTitle: String?

    /// A subject whose title the model may hear: a place, thing or idea, or a person whose name is the owner's.
    public init(entityID: EntityID, title: String, isOwner: Bool, excludedFromAI: Bool = false) {
        self.init(entityID: entityID, title: title, isOwner: isOwner, excludedFromAI: excludedFromAI, modelTitle: title)
    }

    public init(entityID: EntityID, title: String, isOwner: Bool, excludedFromAI: Bool = false, modelTitle: String?) {
        self.entityID = entityID; self.title = title; self.isOwner = isOwner; self.excludedFromAI = excludedFromAI
        self.modelTitle = modelTitle
    }

    /// The record bar's label: it names the page the person is on.
    public static func barLabel(_ subject: SessionSubject?) -> String {
        guard let subject else { return "Tell a story" }
        return subject.isOwner ? "Tell a story about yourself" : "Tell a story about \(subject.title)"
    }

    /// The opening question when the subject has no question of its own waiting. The opening goes to the
    /// interviewer's model, so it names the subject by `modelTitle`; nil when there is no such name.
    var openingText: String? {
        if isOwner { return "Tell me something about yourself." }
        guard let name = modelTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return "Tell me about \(name)."
    }
}
