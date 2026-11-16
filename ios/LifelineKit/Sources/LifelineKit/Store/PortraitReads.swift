import Foundation

/// Everything the You portrait shows, read in a fixed number of queries (S3).
/// The app turns it into parts and lines; nothing here decides what leads or where a line goes.
public struct PortraitSource: Sendable {
    public var profile: Profile?
    public var owner: Entity?
    public var birth: CivilDate?
    /// The owner's own moments, for the life strip.
    public var ownerMoments: [Memory]
    /// Told, visible facts, feelings and goals, by `created_at`. `Portrait` sorts them by when they were told.
    public var aboutMemories: [Memory]
    public var links: [MemoryID: [AboutLink]]
    /// Memory tags by `MemoryID.rawValue`, for every memory: not filtered to the listed ones, and it can hold
    /// ids of memories that are gone. `Portrait` reads only the ids it lists.
    public var memoryTags: [String: [String]]
    public var memoryTellings: [MemoryID: Telling]
    public var ideas: [Entity]
    public var ideaTellings: [EntityID: Telling]
    /// Sessions with a heavy moment (a disclosure, a wish to stop). A line first told in one never leads.
    public var heavySessions: Set<SessionID> = []
}

extension ExtractionStore {
    private static let aboutKinds: Set<MemoryKind> = [.fact, .feeling, .goal]

    public func portraitSource() throws -> PortraitSource {
        let owner = try profile.owner().flatMap { try entities.entity(id: $0.entityID) }
        return PortraitSource(
            profile: try profile.fetch(),
            owner: owner,
            birth: try profile.ownerBirthDate(),
            ownerMoments: try owner.map { try entities.moments(of: $0.id) } ?? [],
            aboutMemories: try memories.aboutMemories(includingHidden: false),
            links: try entities.aboutLinks(kinds: Self.aboutKinds),
            memoryTags: try tags.tagsByElement(.memory),
            memoryTellings: try memories.firstTellings(kinds: Self.aboutKinds),
            ideas: try entities.entities(type: .idea),
            ideaTellings: try entities.firstTellings(type: .idea),
            heavySessions: try sessions.heavySessionIDs())
    }
}
