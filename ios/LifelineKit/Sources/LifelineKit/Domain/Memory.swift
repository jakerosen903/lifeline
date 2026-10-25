import Foundation

public enum Visibility: String, Codable, Sendable {
    case timeline, `private`
}

/// The confirmed thing on the timeline. Text comes from the owner except `title`, which the
/// extractor proposes and the owner accepts by tapping. `range` is nil-dated until the resolver
/// places the memory. A memory with no candidate is one the resolver created to stand for a
/// target the owner named ("graduation") but has not told yet.
public struct Memory: Codable, Sendable, Equatable, Identifiable {
    public var id: MemoryID
    public var title: String
    public var summaryQuote: String
    public var visibility: Visibility
    public var chapterID: ChapterID?
    public var createdFromCandidateID: CandidateID?
    public var createdAt: Date
    public var range: TimeRange
    /// Out of everyday browsing; still in Sessions. Named by its effect (decision 2026-10-22).
    public var hiddenFromTimeline: Bool
    /// Never enters a context packet again.
    public var excludedFromAI: Bool
    /// What the card said this is (M7). Only a moment shows on the timeline.
    public var kind: MemoryKind

    public init(id: MemoryID, title: String, summaryQuote: String, visibility: Visibility, chapterID: ChapterID?,
                createdFromCandidateID: CandidateID?, createdAt: Date, range: TimeRange = .unplaced,
                hiddenFromTimeline: Bool = false, excludedFromAI: Bool = false, kind: MemoryKind = .event) {
        self.id = id; self.title = title; self.summaryQuote = summaryQuote; self.visibility = visibility; self.chapterID = chapterID
        self.createdFromCandidateID = createdFromCandidateID; self.createdAt = createdAt; self.range = range
        self.hiddenFromTimeline = hiddenFromTimeline; self.excludedFromAI = excludedFromAI
        self.kind = kind
    }

    public var isUnplaced: Bool { !range.isPlaced }
    public var isFloating: Bool { createdFromCandidateID == nil }
    public var isMoment: Bool { kind.isMoment }

    // The range is flattened onto the row's columns.
    enum CodingKeys: String, CodingKey {
        case id, title, summaryQuote = "summary_quote", visibility, chapterID = "chapter_id"
        case createdFromCandidateID = "created_from_candidate_id", createdAt = "created_at"
        case hiddenFromTimeline = "hidden_from_timeline", excludedFromAI = "excluded_from_ai", kind
        case earliest, latest, likelyStart = "likely_start", likelyEnd = "likely_end", granularity, origin, evidenceText = "evidence_text"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(MemoryID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summaryQuote = try c.decode(String.self, forKey: .summaryQuote)
        visibility = try c.decode(Visibility.self, forKey: .visibility)
        chapterID = try c.decodeIfPresent(ChapterID.self, forKey: .chapterID)
        createdFromCandidateID = try c.decodeIfPresent(CandidateID.self, forKey: .createdFromCandidateID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        hiddenFromTimeline = try c.decodeIfPresent(Bool.self, forKey: .hiddenFromTimeline) ?? false
        excludedFromAI = try c.decodeIfPresent(Bool.self, forKey: .excludedFromAI) ?? false
        kind = try c.decodeIfPresent(MemoryKind.self, forKey: .kind) ?? .event
        range = TimeRange(earliest: try c.decodeIfPresent(CivilDate.self, forKey: .earliest),
                          latest: try c.decodeIfPresent(CivilDate.self, forKey: .latest),
                          likelyStart: try c.decodeIfPresent(CivilDate.self, forKey: .likelyStart),
                          likelyEnd: try c.decodeIfPresent(CivilDate.self, forKey: .likelyEnd),
                          granularity: try c.decodeIfPresent(Granularity.self, forKey: .granularity),
                          origin: try c.decodeIfPresent(RangeOrigin.self, forKey: .origin),
                          evidenceText: try c.decodeIfPresent(String.self, forKey: .evidenceText))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(summaryQuote, forKey: .summaryQuote)
        try c.encode(visibility, forKey: .visibility)
        try c.encode(chapterID, forKey: .chapterID)
        try c.encode(createdFromCandidateID, forKey: .createdFromCandidateID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(hiddenFromTimeline, forKey: .hiddenFromTimeline)
        try c.encode(excludedFromAI, forKey: .excludedFromAI)
        try c.encode(kind, forKey: .kind)
        try c.encode(range.earliest, forKey: .earliest)
        try c.encode(range.latest, forKey: .latest)
        try c.encode(range.likelyStart, forKey: .likelyStart)
        try c.encode(range.likelyEnd, forKey: .likelyEnd)
        try c.encode(range.granularity, forKey: .granularity)
        try c.encode(range.origin, forKey: .origin)
        try c.encode(range.evidenceText, forKey: .evidenceText)
    }
}

/// A memory's span of one segment. The span with order 0 is the primary. A later span is a
/// retelling: it remembers the card's title and the candidate it came from (M4.1).
public struct MemorySpan: Codable, Sendable, Equatable {
    public var memoryID: MemoryID
    public var segmentID: SegmentID
    public var startMs: Milliseconds
    public var endMs: Milliseconds
    public var order: Int
    public var titleText: String?
    public var candidateID: CandidateID?
    /// The order of the telling this span carries on after a pause (M5). Nil for a telling of its own.
    public var continuesOrder: Int?

    public init(memoryID: MemoryID, segmentID: SegmentID, startMs: Milliseconds, endMs: Milliseconds, order: Int,
                titleText: String? = nil, candidateID: CandidateID? = nil, continuesOrder: Int? = nil) {
        self.memoryID = memoryID; self.segmentID = segmentID; self.startMs = startMs; self.endMs = endMs; self.order = order
        self.titleText = titleText; self.candidateID = candidateID; self.continuesOrder = continuesOrder
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
