import AVFoundation
import Synchronization
@testable import LifelineKit

final class FakeTranscriber: Transcriber, Sendable {
    private let stream: AsyncStream<TranscriptResult>
    private let continuation: AsyncStream<TranscriptResult>.Continuation
    private let state = Mutex<(fed: [MsRange], finalizedThrough: [Milliseconds], finished: Bool)>(([], [], false))
    /// Results delivered when finish() is called, before the stream ends (late finals).
    let resultsOnFinish = Mutex<[TranscriptResult]>([])
    /// Simulates a finalize(through:) call that never returns.
    let finalizeDelay = Mutex<Duration?>(nil)

    init() { (stream, continuation) = AsyncStream.makeStream() }

    var fed: [MsRange] { state.withLock { $0.fed } }
    var finalizedThrough: [Milliseconds] { state.withLock { $0.finalizedThrough } }
    var finished: Bool { state.withLock { $0.finished } }

    func start(format: AVAudioFormat) async throws -> AsyncStream<TranscriptResult> { stream }
    func feed(_ chunk: AudioChunk) async {
        state.withLock { $0.fed.append(MsRange(start: chunk.startMs, end: chunk.startMs + chunk.durationMs)) }
    }
    func finalize(throughMs: Milliseconds) async {
        state.withLock { $0.finalizedThrough.append(throughMs) }
        if let delay = finalizeDelay.withLock({ $0 }) { try? await Task.sleep(for: delay) }
    }
    func finish() async {
        state.withLock { $0.finished = true }
        for r in resultsOnFinish.withLock({ $0 }) { continuation.yield(r) }
        continuation.finish()
    }

    func push(_ result: TranscriptResult) { continuation.yield(result) }
}
