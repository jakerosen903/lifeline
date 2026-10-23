import Foundation

public enum CandidateKind: String, Codable, Sendable {
    case memory, person, place, flag
}

public enum CandidateStatus: String, Codable, Sendable {
    case pending, accepted, dismissed, superseded
}

/// Raw extractor output for one segment, one row per proposed thing. Rows are immutable:
/// a new extractor version writes new rows; only `status` and `rejection` ever change.
public struct Candidate: Codable, Sendable, Equatable, Identifiable {
    public var id: CandidateID
    public var segmentID: SegmentID
    public var extractorVersion: String
    /// Position in the model's output. With the segment and version it makes the row unique.
    public var ordinal: Int
    public var kind: CandidateKind
    /// JSON of the extractor's object for this candidate (a MemoryOut, MentionOut or Flags).
    public var payload: String
    public var confidence: Double
    public var status: CandidateStatus
    /// Why the validator dismissed it before anyone saw it; nil for everything shown.
    public var rejection: String?
    public var createdAt: Date

    public init(id: CandidateID, segmentID: SegmentID, extractorVersion: String, ordinal: Int, kind: CandidateKind, payload: String,
                confidence: Double, status: CandidateStatus, rejection: String?, createdAt: Date) {
        self.id = id; self.segmentID = segmentID; self.extractorVersion = extractorVersion; self.ordinal = ordinal
        self.kind = kind; self.payload = payload; self.confidence = confidence; self.status = status
        self.rejection = rejection; self.createdAt = createdAt
    }
}
