import Foundation

public struct TranscribedWord: Equatable, Hashable, Sendable, Codable {
    public var text: String
    public var range: MsRange
    public init(text: String, range: MsRange) { self.text = text; self.range = range }
}

/// One result from the transcriber. Partial results carry text only; final results carry words.
public struct TranscriptResult: Equatable, Sendable {
    public var text: String
    public var words: [TranscribedWord]
    public var range: MsRange
    public var isFinal: Bool
    public init(text: String, words: [TranscribedWord], range: MsRange, isFinal: Bool) {
        self.text = text; self.words = words; self.range = range; self.isFinal = isFinal
    }
}

/// A closed segment: its span in the file and the final words inside it.
public struct SegmentTranscript: Equatable, Sendable {
    public var range: MsRange
    public var text: String
    public var words: [TranscribedWord]
    public init(range: MsRange, text: String, words: [TranscribedWord]) {
        self.range = range; self.text = text; self.words = words
    }
}

/// One turn for the voice session to speak. The recorder chooses the id, so the row it stores
/// and the events the session reports name the same turn.
public struct SpokenTurn: Equatable, Sendable {
    public var id: InterviewerTurnID
    public var text: String
    public init(id: InterviewerTurnID, text: String) { self.id = id; self.text = text }
}

/// Events from a voice session. The first four are the technical design's interface;
/// the rest are what the session needs to store segments, store turns and react to the audio session.
public enum VoiceEvent: Equatable, Sendable {
    case speechStarted(atMs: Milliseconds)
    case transcriptPartial(String)
    case transcriptFinal(TranscriptResult)
    case userPaused(afterMs: Milliseconds)
    case segmentClosed(SegmentTranscript)
    case interrupted
    /// The person paused. Capture stops until `resume`; the file clock does not move.
    case paused
    /// After an interruption or a pause, capture is running again.
    case resumed
    case failed(String)
    /// The app began to speak a turn, at this point on the file clock.
    case turnStarted(InterviewerTurnID, atMs: Milliseconds)
    /// The turn stopped. `interrupted` is true when pause, an interruption, stop or the person cut it.
    case turnEnded(InterviewerTurnID, atMs: Milliseconds, interrupted: Bool)
}

/// The voice pipeline behind one interface, so a realtime speech model can replace the cascade later.
public protocol VoiceSession: Actor {
    func start(writingTo audioURL: URL) async throws -> AsyncStream<VoiceEvent>
    func stop() async throws
    /// Closes what was said and stops capture; the next chunk after `resume` follows the last one on the file clock.
    func pause() async throws
    func resume() async throws
    /// Starts the turn and returns at once; `turnStarted` and `turnEnded` report it. Dropped while
    /// paused or stopped. A turn that is playing ends, interrupted, before the next one starts.
    func say(_ turn: SpokenTurn) async
    func acknowledge() async
    func interrupt() async
}
