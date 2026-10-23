import AVFoundation

/// One buffer of captured audio with its position on the file clock and its level.
/// `@unchecked` because the buffer is handed from the source to the session and never
/// shared after that; consumers must not retain it past the call.
public struct AudioChunk: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    public let startMs: Milliseconds
    public let durationMs: Milliseconds
    /// RMS level in dBFS.
    public let levelDb: Float

    public init(buffer: AVAudioPCMBuffer, startMs: Milliseconds, durationMs: Milliseconds, levelDb: Float) {
        self.buffer = buffer; self.startMs = startMs; self.durationMs = durationMs; self.levelDb = levelDb
    }

    public var range: MsRange { MsRange(start: startMs, end: startMs + durationMs) }
}

public enum AudioSourceEvent: Sendable {
    case chunk(AudioChunk)
    case interrupted
    case resumed
}

/// Where audio comes from: the microphone on iOS, a fake in tests.
public protocol AudioSource: Sendable {
    var format: AVAudioFormat { get }
    func start() async throws -> AsyncStream<AudioSourceEvent>
    func stop() async
    /// Stops delivering chunks without ending the stream. Frame counting continues where it left off at `resume`.
    func pause() async
    func resume() async throws
}

/// Where audio goes: the m4a file, a fake in tests.
public protocol AudioSink: Sendable {
    func open(url: URL, format: AVAudioFormat) async throws
    func write(_ chunk: AudioChunk) async throws
    func close() async throws
}
