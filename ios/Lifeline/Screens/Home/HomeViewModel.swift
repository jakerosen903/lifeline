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

    /// What the full-screen cover shows: the live session, then its landing, in the same cover.
    enum Presented: Identifiable {
        case session(SessionViewModel)
        case landing(LandingViewModel)
        var id: UUID {
            switch self {
            case .session(let vm): vm.id
            case .landing(let vm): vm.id
            }
        }
    }

    private(set) var rows: [Row] = []
    private(set) var error: String?
    var presented: Presented?
    var activeSession: SessionViewModel? {
        if case .session(let vm) = presented { return vm }
        return nil
    }
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
        presented = .session(vm)
        await vm.start()
    }

    /// Finish: the cover swaps to the landing. A session with no words lands quietly.
    func sessionEnded() {
        let ended = activeSession
        deps.deactivateAudio()
        refresh()
        guard let ended, let id = ended.state.sessionID, let session = try? deps.sessions.fetch(id),
              !((try? deps.sessions.segments(in: id)) ?? []).isEmpty else {
            if let id = ended?.state.sessionID { try? deps.sessions.markLanded(id) }
            presented = nil
            return
        }
        presented = .landing(LandingViewModel(session: session, heavy: ended.heavy, presentDanger: ended.presentDanger, deps: deps))
    }

    func present(landing: LandingViewModel) { presented = .landing(landing) }

    func landingClosed(tellAnother: Bool) {
        presented = nil
        refresh()
        if tellAnother { Task { await startSession(kind: .quick) } }
    }

    /// Duration from the last segment's end; falls back to the wall clock for a session with no segments.
    private static func durationText(_ session: Session, _ segments: [Segment]) -> String {
        if let last = segments.map(\.endMs).max() { return Format.duration(ms: last) }
        if let end = session.endedAt { return Format.duration(from: session.startedAt, to: end) }
        return "–"
    }
}
