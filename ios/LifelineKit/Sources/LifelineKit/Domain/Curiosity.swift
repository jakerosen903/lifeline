import Foundation

public enum CuriosityKind: String, Codable, Sendable {
    case unresolvedAnchor = "unresolved_anchor"
    case unexplainedPerson = "unexplained_person"
    case placeWithoutStory = "place_without_story"
    case droppedThread = "dropped_thread"
}

public enum CuriosityStatus: String, Codable, Sendable {
    case open, answered, dismissed
}

/// What the interviewer would ask next, with how much it would unlock.
public struct CuriosityItem: Codable, Sendable, Equatable, Identifiable {
    public var id: CuriosityItemID
    public var kind: CuriosityKind
    public var text: String
    /// How many memories a resolution would place.
    public var payoffCount: Int
    public var status: CuriosityStatus
    public var sourceMemoryID: MemoryID?
    /// For `unresolvedAnchor`: the floating memory that stands for the target phrase.
    public var targetMemoryID: MemoryID?

    public init(id: CuriosityItemID, kind: CuriosityKind, text: String, payoffCount: Int, status: CuriosityStatus,
                sourceMemoryID: MemoryID?, targetMemoryID: MemoryID?) {
        self.id = id; self.kind = kind; self.text = text; self.payoffCount = payoffCount; self.status = status
        self.sourceMemoryID = sourceMemoryID; self.targetMemoryID = targetMemoryID
    }
}
