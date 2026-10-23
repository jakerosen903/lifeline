import Foundation

/// One recording. The row exists from the moment recording starts so a crash
/// leaves evidence; `endedAt` is nil until the session lands.
public struct Session: Codable, Sendable, Equatable, Identifiable {
    public var id: SessionID
    public var startedAt: Date
    public var endedAt: Date?
    /// File name inside the audio directory, not an absolute path, so the
    /// container can move between installs.
    public var audioPath: String
    /// JSON array of stage changes. "[]" until M4 fills it.
    public var stageLog: String
    public var landingChoiceMade: Bool
    /// A quick story or settling in (M4). Older rows read as quick.
    public var kind: SessionKind
    /// "Hide today from the timeline": memories kept from this session later are hidden too.
    public var hiddenFromTimeline: Bool

    public init(id: SessionID, startedAt: Date, endedAt: Date?, audioPath: String, stageLog: String, landingChoiceMade: Bool,
                kind: SessionKind = .quick, hiddenFromTimeline: Bool = false) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioPath = audioPath
        self.stageLog = stageLog
        self.landingChoiceMade = landingChoiceMade
        self.kind = kind
        self.hiddenFromTimeline = hiddenFromTimeline
    }
}

public enum SegmentStatus: String, Codable, Sendable {
    case pending, extracted, failed
}

/// One completed thought: a span of the session file with its transcript.
public struct Segment: Codable, Sendable, Equatable, Identifiable {
    public var id: SegmentID
    public var sessionID: SessionID
    public var index: Int
    public var startMs: Milliseconds
    public var endMs: Milliseconds
    public var text: String
    public var status: SegmentStatus

    public init(id: SegmentID, sessionID: SessionID, index: Int, startMs: Milliseconds, endMs: Milliseconds, text: String, status: SegmentStatus) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.status = status
    }

    public var range: MsRange { MsRange(start: startMs, end: endMs) }
}

/// One transcribed word with its span in the session file.
public struct Word: Codable, Sendable, Equatable {
    public var segmentID: SegmentID
    public var index: Int
    public var text: String
    public var startMs: Milliseconds
    public var endMs: Milliseconds

    public init(segmentID: SegmentID, index: Int, text: String, startMs: Milliseconds, endMs: Milliseconds) {
        self.segmentID = segmentID
        self.index = index
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
    }
}
