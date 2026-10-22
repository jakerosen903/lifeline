import Foundation
import LifelineKit

@MainActor
@Observable
final class SessionDetailViewModel {
    let session: Session
    private(set) var segments: [Segment] = []
    private(set) var error: String?
    let player = SegmentPlayer()
    private let deps: Dependencies

    init(session: Session, deps: Dependencies) {
        self.session = session
        self.deps = deps
        do { segments = try deps.sessions.segments(in: session.id) } catch { self.error = error.localizedDescription }
    }

    func isPlaying(_ segment: Segment) -> Bool { player.playingRange == segment.range && player.isPlaying }

    /// Tap plays the segment's own span; a second tap on the same segment stops.
    func toggle(_ segment: Segment) {
        if player.playingRange == segment.range {
            player.stop()
            return
        }
        do {
            try player.play(url: try deps.audioURL(for: session), range: segment.range)
            error = nil
        } catch {
            self.error = "Could not play this moment: \(error.localizedDescription)"
        }
    }

    func stop() { player.stop() }
}
