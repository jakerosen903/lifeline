import Foundation

/// A span of a life the owner names ("the Boston years") or leaves untitled. Its range comes
/// from its members until the owner edits it.
public struct Chapter: Codable, Sendable, Equatable, Identifiable {
    public var id: ChapterID
    public var title: String?
    public var range: TimeRange
    public var order: Int

    public init(id: ChapterID, title: String?, range: TimeRange, order: Int) {
        self.id = id; self.title = title; self.range = range; self.order = order
    }
}

/// Related memories with a span derived from the members ("Family trips to Yosemite").
public struct Collection: Codable, Sendable, Equatable, Identifiable {
    public var id: CollectionID
    public var title: String

    public init(id: CollectionID, title: String) { self.id = id; self.title = title }
}

public struct CollectionMemory: Codable, Sendable, Equatable {
    public var collectionID: CollectionID
    public var memoryID: MemoryID

    public init(collectionID: CollectionID, memoryID: MemoryID) { self.collectionID = collectionID; self.memoryID = memoryID }
}
