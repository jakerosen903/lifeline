/// What playback of one turn reports: it began, then it ended. `completed` is false when it was cut.
public enum PlaybackEvent: Equatable, Sendable {
    case started
    case finished(completed: Bool)
}

/// The app's voice. The voice session plays one turn at a time and stops it on pause,
/// an interruption or stop.
public protocol VoiceOutput: Sendable {
    func play(_ text: String) -> AsyncStream<PlaybackEvent>
    func stop() async
}

/// Speaks nothing: each turn starts and finishes at once. "Lifeline speaks" off, and every
/// session until the system voice arrives.
public struct SilentVoiceOutput: VoiceOutput {
    public init() {}

    public func play(_ text: String) -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            continuation.yield(.started)
            continuation.yield(.finished(completed: true))
            continuation.finish()
        }
    }

    public func stop() async {}
}
