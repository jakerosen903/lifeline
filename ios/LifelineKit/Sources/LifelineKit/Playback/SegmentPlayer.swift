import AVFoundation
import Observation

/// Plays one span of a session file. Observable so a view can show which segment is playing.
@MainActor
@Observable
public final class SegmentPlayer {
    public private(set) var playingRange: MsRange?
    private var player: AVAudioPlayer?
    private var stopTimer: Timer?

    public init() {}

    public var isPlaying: Bool { player?.isPlaying ?? false }

    public var positionMs: Milliseconds {
        guard let player else { return 0 }
        return Int((player.currentTime * 1_000).rounded())
    }

    /// Starts playback at `range.start` and stops at `range.end`, clamped to the file.
    public func play(url: URL, range: MsRange) throws {
        stop()
        let p = try AVAudioPlayer(contentsOf: url)
        let clamped = Self.clamp(range, toDurationMs: Int((p.duration * 1_000).rounded()))
        p.currentTime = Double(clamped.start) / 1_000
        player = p
        playingRange = clamped
        guard clamped.duration > 0, p.play() else {
            stop()
            return
        }
        stopTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    public func stop() {
        stopTimer?.invalidate()
        stopTimer = nil
        player?.stop()
        player = nil
        playingRange = nil
    }

    private func tick() {
        guard let player, let range = playingRange else { return }
        if !player.isPlaying || positionMs >= range.end { stop() }
    }

    public nonisolated static func clamp(_ range: MsRange, toDurationMs duration: Milliseconds) -> MsRange {
        let start = min(max(0, range.start), duration)
        let end = min(max(start, range.end), duration)
        return MsRange(start: start, end: end)
    }
}
