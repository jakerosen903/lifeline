import AVFoundation

/// On-device speech to text. Results arrive on the stream returned by `start`.
public protocol Transcriber: Sendable {
    func start(format: AVAudioFormat) async throws -> AsyncStream<TranscriptResult>
    func feed(_ chunk: AudioChunk) async
    /// Asks for every result up to `throughMs` to be made final.
    func finalize(throughMs: Milliseconds) async
    /// No more audio. Ends the results stream.
    func finish() async
}
