import Foundation

/// Where a line of the person's own words can be heard: the first span that holds it, with the
/// session's audio file and when the session began (S3).
public struct Telling: Sendable, Equatable {
    public var sessionID: SessionID
    /// File name inside the audio directory, as in `Session.audioPath`.
    public var audioPath: String
    public var range: MsRange
    /// The session's `started_at`: when it was said, which the app knows. Not a guess.
    public var toldAt: Date

    public init(sessionID: SessionID, audioPath: String, range: MsRange, toldAt: Date) {
        self.sessionID = sessionID; self.audioPath = audioPath; self.range = range; self.toldAt = toldAt
    }
}

/// A person, place or thing a fact, feeling or goal is linked to, and how.
public struct AboutLink: Sendable, Equatable {
    public var entity: Entity
    public var relation: EntityRelation

    public init(entity: Entity, relation: EntityRelation) {
        self.entity = entity; self.relation = relation
    }
}
