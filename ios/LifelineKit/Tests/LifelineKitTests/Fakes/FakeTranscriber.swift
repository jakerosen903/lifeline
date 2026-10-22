import AVFoundation
import Synchronization
@testable import LifelineKit

final class FakeTranscriber: Transcriber, Sendable {
    private let stream: AsyncStream<TranscriptResult>
    private let continuation: AsyncStream<TranscriptResult>.Continuation
    private let state = Mutex<(fed: [MsRange], finalizedThrough: [Milliseconds], finished: Bool)>(([], [], false))

    init() { (stream, continuation) = AsyncStream.makeStream() }

    var fed: [MsRange] { state.withLock { $0.fed } }
    var finalizedThrough: [Milliseconds] { state.withLock { $0.finalizedThrough } }
    var finished: Bool { state.withLock { $0.finished } }

    func start(format: AVAudioFormat) async throws -> AsyncStream<TranscriptResult> { stream }
    func feed(_ chunk: AudioChunk) async {
        state.withLock { $0.fed.append(MsRange(start: chunk.startMs, end: chunk.startMs + chunk.durationMs)) }
    }
    func finalize(throughMs: Milliseconds) async { state.withLock { $0.finalizedThrough.append(throughMs) } }
    func finish() async { state.withLock { $0.finished = true }; continuation.finish() }

    func push(_ result: TranscriptResult) { continuation.yield(result) }
}
