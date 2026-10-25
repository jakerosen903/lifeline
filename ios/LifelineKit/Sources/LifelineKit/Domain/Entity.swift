import Foundation


/// The four kinds of thing a life is about, beside its moments (M7). Possessions, buildings,
/// vehicles, objects and made things are all things.
public enum EntityType: String, Codable, Sendable, CaseIterable {
    case person, place, thing, idea

    /// The segment's label on the entities screen.
    public var screenTitle: String {
        switch self {
        case .person: "People"
        case .place: "Places"
        case .thing: "Things"
        case .idea: "Ideas"
        }
    }

    /// The heading of the card that proposes one. A person keeps the Who's-this card.
    public var cardHeading: String {
        switch self {
        case .person: "Who's this?"
        case .place: "Sounds like a place"
        case .thing: "Sounds like a thing you had"
        case .idea: "Sounds like something you think"
        }
    }
}

/// A person, place, thing or idea. Every one is created from something the person said.
/// `range` is the span the person stated with "Add dates"; `.unplaced` when they have not, and
/// then the page shows the span derived from what is linked to it.
public struct Entity: Sendable, Equatable, Identifiable, Hashable {
    public var id: EntityID
    public var type: EntityType
    public var title: String
    public var detailText: String?
    public var createdFromCandidateID: CandidateID?
    public var createdAt: Date
    public var range: TimeRange
    public var hiddenFromTimeline: Bool
    public var excludedFromAI: Bool

    public init(id: EntityID = .init(), type: EntityType, title: String, detailText: String? = nil, createdFromCandidateID: CandidateID? = nil,
                createdAt: Date = .now, range: TimeRange = .unplaced, hiddenFromTimeline: Bool = false, excludedFromAI: Bool = false) {
        self.id = id; self.type = type; self.title = title; self.detailText = detailText; self.createdFromCandidateID = createdFromCandidateID
        self.createdAt = createdAt; self.range = range; self.hiddenFromTimeline = hiddenFromTimeline; self.excludedFromAI = excludedFromAI
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// How a memory relates to an entity: a standing statement about it, or a moment that names it.
public enum EntityRelation: String, Codable, Sendable {
    case detail, mention
}

/// The one link table (M7): every person, place, thing and idea a memory names or describes.
public struct MomentEntity: Sendable, Equatable, Hashable {
    public var memoryID: MemoryID
    public var entityID: EntityID
    public var relation: EntityRelation
    /// The person's phrase for the entity in this memory ("my sister").
    public var roleText: String?

    public init(memoryID: MemoryID, entityID: EntityID, relation: EntityRelation, roleText: String? = nil) {
        self.memoryID = memoryID; self.entityID = entityID; self.relation = relation; self.roleText = roleText
    }
}

/// An entity's first telling, so its page can play it.
public struct EntitySpan: Sendable, Equatable {
    public var entityID: EntityID
    public var segmentID: SegmentID
    public var startMs: Milliseconds
    public var endMs: Milliseconds
    public var order: Int

    public init(entityID: EntityID, segmentID: SegmentID, startMs: Milliseconds, endMs: Milliseconds, order: Int) {
        self.entityID = entityID; self.segmentID = segmentID; self.startMs = startMs; self.endMs = endMs; self.order = order
    }
}

/// What a domain tag hangs on.
public enum ElementKind: String, Codable, Sendable {
    case memory, entity
}

/// A free-text domain ("home", "work", or the person's own word) on a memory or an entity (M7).
public struct DomainTag: Sendable, Equatable, Hashable {
    public var elementKind: ElementKind
    public var elementID: String
    public var text: String

    public init(elementKind: ElementKind, elementID: String, text: String) {
        self.elementKind = elementKind; self.elementID = elementID; self.text = text
    }
}
