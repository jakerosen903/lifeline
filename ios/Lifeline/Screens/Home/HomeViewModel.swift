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

    private var isStarting = false

    /// Asks for the microphone, activates audio, presents the session screen, then starts the
    /// recorder inside it so the owner sees the speech-model download and any start error.
    /// A second tap while starting or recording does nothing.
    func startSession(kind: SessionKind = .quick) async {
        guard !isStarting, activeSession == nil else { return }
        isStarting = true
        defer { isStarting = false }
        error = nil
        guard await deps.requestMicrophone() else {
            error = "Lifeline needs the microphone to record. Allow it in Settings."
            return
        }
        do {
            try deps.activateAudio()
        } catch {
            self.error = "Could not start audio: \(error.localizedDescription)"
            return
        }
        let vm = SessionViewModel(deps: deps, kind: kind)
        activeSession = vm
        await vm.start()
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
