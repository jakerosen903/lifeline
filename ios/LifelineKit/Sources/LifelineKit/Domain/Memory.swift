import Foundation

public enum Visibility: String, Codable, Sendable {
    case timeline, `private`
}

/// The confirmed thing on the timeline. Text comes from the owner except `title`, which the
/// extractor proposes and the owner accepts by tapping. Range columns stay nil until the
/// resolver (M3) places the memory.
public struct Memory: Codable, Sendable, Equatable, Identifiable {
    public var id: MemoryID
    public var title: String
    public var summaryQuote: String
    public var visibility: Visibility
    public var chapterID: String?
    public var createdFromCandidateID: CandidateID
    public var createdAt: Date
    public var earliest: String?
    public var latest: String?
    public var likelyStart: String?
    public var likelyEnd: String?
    public var granularity: String?
    public var origin: String?
    public var evidenceText: String?

    public init(id: MemoryID, title: String, summaryQuote: String, visibility: Visibility, chapterID: String?,
                createdFromCandidateID: CandidateID, createdAt: Date, earliest: String?, latest: String?, likelyStart: String?,
                likelyEnd: String?, granularity: String?, origin: String?, evidenceText: String?) {
        self.id = id; self.title = title; self.summaryQuote = summaryQuote; self.visibility = visibility; self.chapterID = chapterID
        self.createdFromCandidateID = createdFromCandidateID; self.createdAt = createdAt; self.earliest = earliest; self.latest = latest
        self.likelyStart = likelyStart; self.likelyEnd = likelyEnd; self.granularity = granularity; self.origin = origin
        self.evidenceText = evidenceText
    }

    /// True when no range column is set: the memory belongs on the shelf.
    public var isUnplaced: Bool { earliest == nil && latest == nil && likelyStart == nil && likelyEnd == nil }
}

/// A memory's span of one segment. The span with order 0 is the primary.
public struct MemorySpan: Codable, Sendable, Equatable {
    public var memoryID: MemoryID
    public var segmentID: SegmentID
    public var startMs: Milliseconds
    public var endMs: Milliseconds
    public var order: Int

    public init(memoryID: MemoryID, segmentID: SegmentID, startMs: Milliseconds, endMs: Milliseconds, order: Int) {
        self.memoryID = memoryID; self.segmentID = segmentID; self.startMs = startMs; self.endMs = endMs; self.order = order
    }
}

public struct MemoryPerson: Codable, Sendable, Equatable {
    public var memoryID: MemoryID
    public var personID: PersonID
    /// The owner's phrase for the person in this memory ("my sister").
    public var roleText: String?

    public init(memoryID: MemoryID, personID: PersonID, roleText: String?) {
        self.memoryID = memoryID; self.personID = personID; self.roleText = roleText
    }
}

public struct Place: Codable, Sendable, Equatable, Identifiable {
    public var id: PlaceID
    public var nameText: String
    public var lat: Double?
    public var lon: Double?

    public init(id: PlaceID, nameText: String, lat: Double?, lon: Double?) {
        self.id = id; self.nameText = nameText; self.lat = lat; self.lon = lon
    }
}

public struct MemoryPlace: Codable, Sendable, Equatable {
    public var memoryID: MemoryID
    public var placeID: PlaceID

    public init(memoryID: MemoryID, placeID: PlaceID) {
        self.memoryID = memoryID; self.placeID = placeID
    }
}
