import Foundation

/// A span of a life the owner names ("the Boston years") or leaves untitled. Its range holds
/// stated years only: the years the person said. A member span is never written to it.
public struct Chapter: Codable, Sendable, Equatable, Identifiable {
    public var id: ChapterID
    public var title: String?
    public var range: TimeRange
    public var order: Int

    public init(id: ChapterID, title: String?, range: TimeRange, order: Int) {
        self.id = id; self.title = title; self.range = range; self.order = order
    }
}

extension Chapter {
    /// The years the person said for this chapter: a placed range whose origin is `stated` or
    /// `confirmed`. Any other origin (`derived` or `inferred`, written before chapters held stated
    /// years only, or `photo`) counts as none. The prune's SQL in `ChapterRepository` uses the same rule.
    public var statedYears: TimeRange? {
        range.isPlaced && (range.origin == .stated || range.origin == .confirmed) ? range : nil
    }

    /// The range a reader places this chapter by: the stated years when there are any, else the
    /// span over its members' ranges. Never stored, never shown as the chapter's dates.
    public func anchorRange(members: [TimeRange]) -> TimeRange {
        statedYears ?? ChapterRepository.span(over: members)
    }

    /// The title without surrounding space; nil when the person gave none.
    public var name: String? {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
