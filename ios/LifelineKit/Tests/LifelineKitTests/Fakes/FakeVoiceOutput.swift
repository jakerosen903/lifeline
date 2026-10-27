import Synchronization
@testable import LifelineKit

/// Plays a turn until the test calls `finish()` or the session calls `stop()`.
final class FakeVoiceOutput: VoiceOutput, Sendable {
    private let state = Mutex<(played: [String], stops: Int, playing: AsyncStream<PlaybackEvent>.Continuation?)>(([], 0, nil))

    var played: [String] { state.withLock { $0.played } }
    var stops: Int { state.withLock { $0.stops } }

    /// When false, a turn waits for `start()` before it reports `started`, as a slow engine would.
    let startsAtOnce = Mutex(true)

    func play(_ text: String) -> AsyncStream<PlaybackEvent> {
        let (stream, continuation) = AsyncStream<PlaybackEvent>.makeStream()
        if startsAtOnce.withLock({ $0 }) { continuation.yield(.started) }
        state.withLock { $0.played.append(text); $0.playing = continuation }
        return stream
    }

    /// When set, `stop()` takes this long before it stops what is playing then, as a slow engine would.
    let stopDelay = Mutex<Duration?>(nil)

    func stop() async {
        if let delay = stopDelay.withLock({ $0 }) { try? await Task.sleep(for: delay) }
        let playing = state.withLock { s in s.stops += 1; defer { s.playing = nil }; return s.playing }
        playing?.yield(.finished(completed: false))
        playing?.finish()
    }

    /// The turn plays to its end.
    func finish() {
        let playing = state.withLock { s in defer { s.playing = nil }; return s.playing }
        playing?.yield(.finished(completed: true))
        playing?.finish()
    }
}
