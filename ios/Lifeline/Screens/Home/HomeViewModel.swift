import Foundation
import LifelineKit

@MainActor
@Observable
final class HomeViewModel {
    struct Row: Identifiable {
        let session: Session
        let segmentCount: Int
        let durationText: String
        var id: SessionID { session.id }
    }

    private(set) var rows: [Row] = []
    private(set) var error: String?
    var activeSession: SessionViewModel?
    let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
        refresh()
    }

    func refresh() {
        do {
            rows = try deps.sessions.listSessions().map { session in
                let segments = try deps.sessions.segments(in: session.id)
                return Row(session: session, segmentCount: segments.count, durationText: Self.durationText(session, segments))
            }
        } catch {
            self.error = "Could not load sessions: \(error.localizedDescription)"
        }
    }

    /// Asks for the microphone, activates audio, starts a recorder and presents the session screen.
    func startSession() async {
        error = nil
        guard await deps.requestMicrophone() else {
            error = "Lifeline needs the microphone to record. Allow it in Settings."
            return
        }
        do {
            try deps.activateAudio()
            let vm = SessionViewModel(deps: deps)
            try await vm.start()
            activeSession = vm
        } catch {
            deps.deactivateAudio()
            self.error = "Could not start: \(error.localizedDescription)"
        }
    }

    func sessionEnded() {
        activeSession = nil
        deps.deactivateAudio()
        refresh()
    }

    /// Duration from the last segment's end; falls back to the wall clock for a session with no segments.
    private static func durationText(_ session: Session, _ segments: [Segment]) -> String {
        if let last = segments.map(\.endMs).max() { return Format.duration(ms: last) }
        if let end = session.endedAt { return Format.duration(from: session.startedAt, to: end) }
        return "–"
    }
}
