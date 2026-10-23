import AVFoundation
@testable import LifelineKit

final class FakeAudioSource: AudioSource, @unchecked Sendable {
    let format = AudioFixtures.format
    private let stream: AsyncStream<AudioSourceEvent>
    private let continuation: AsyncStream<AudioSourceEvent>.Continuation
    private(set) var stopped = false

    init() { (stream, continuation) = AsyncStream.makeStream() }

    func start() async throws -> AsyncStream<AudioSourceEvent> { stream }
    func stop() async { stopped = true; continuation.finish() }
    private(set) var paused = false
    func pause() async { paused = true }
    func resume() async throws { paused = false }

    /// Pushes 100 ms chunks: loud for `speechMs`, quiet for `silenceMs`.
    func push(speechMs: Range<Int>, silenceMs: Range<Int>? = nil) {
        for ms in stride(from: speechMs.lowerBound, to: speechMs.upperBound, by: 100) {
            continuation.yield(.chunk(AudioFixtures.chunk(startMs: ms, levelDb: -20)))
        }
        if let silenceMs {
            for ms in stride(from: silenceMs.lowerBound, to: silenceMs.upperBound, by: 100) {
                continuation.yield(.chunk(AudioFixtures.chunk(startMs: ms, levelDb: -60)))
            }
        }
    }

    func pushInterrupted() { continuation.yield(.interrupted) }
    func pushResumed() { continuation.yield(.resumed) }
}
