import Foundation

/// What the Things shelf shows, read in a fixed number of statements (S7).
public struct ThingShelfSource: Sendable {
    public var birthYear: Int?
    /// Visible things, from `summaries(type: .thing)`.
    public var things: [EntitySummary]
    /// The key photo of each visible thing.
    public var keyPhotos: [EntityID: Photo]
    /// May hold keys of hidden things: look it up by the ids of `things` only.
    public var details: [EntityID: [Memory]]
    /// The first telling of every told, visible memory, for the heavy-session rule.
    public var tellings: [MemoryID: Telling]
    public var heavySessions: Set<SessionID>
}

extension ExtractionStore {
    /// Five reads, none per thing. Hidden things, hidden memories and untold stand-ins are left out
    /// by the filters those reads already use.
    public func thingShelfSource() throws -> ThingShelfSource {
        ThingShelfSource(
            birthYear: try profile.ownerBirthDate()?.year,
            things: try entities.summaries(type: .thing),
            keyPhotos: try photos.covers(type: .thing),
            details: try entities.details(type: .thing),
            tellings: try memories.firstTellings(kinds: Set(MemoryKind.allCases)),
            heavySessions: try sessions.heavySessionIDs())
    }
}
