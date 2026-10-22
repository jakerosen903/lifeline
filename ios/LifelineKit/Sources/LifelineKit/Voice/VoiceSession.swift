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

/// Events from a voice session. The first four are the technical design's interface;
/// the rest are what a listen-only V1 needs to store segments and react to the audio session.
public enum VoiceEvent: Equatable, Sendable {
    case speechStarted(atMs: Milliseconds)
    case transcriptPartial(String)
    case transcriptFinal(TranscriptResult)
    case userPaused(afterMs: Milliseconds)
    case segmentClosed(SegmentTranscript)
    case interrupted
    case resumed
    case failed(String)
}

/// The voice pipeline behind one interface, so a speaking interviewer or a realtime
/// speech model can replace the listen-only implementation later.
public protocol VoiceSession: Actor {
    func start(writingTo audioURL: URL) async throws -> AsyncStream<VoiceEvent>
    func stop() async throws
    func say(_ text: String) async
    func acknowledge() async
    func interrupt() async
}
