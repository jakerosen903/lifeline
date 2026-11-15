import Foundation
import LifelineKit

@MainActor
@Observable
final class HomeViewModel {
    struct Row: Identifiable {
        let session: Session
        let segmentCount: Int
        let durationText: String
        /// Segments of this recording still to be sorted (M6).
        var pendingCount = 0
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
    /// The sessions list could not load. Cleared by the next load that works.
    private(set) var error: String?
    /// The last Start failed (microphone or audio). Shown on the record bar; cleared by the next Start.
    private(set) var startError: String?
    var presented: Presented?
    /// The page on screen; nil on a tab root. A session started now is about it.
    private(set) var context: SessionSubject?
    /// The screen that set `context`. Pushing and popping can report the new screen's appearance
    /// before the old one's disappearance, so a screen that leaves clears only what it set itself.
    private var contextScreen: UUID?
    /// Called after a session ends, so the timeline can refresh.
    var onSessionEnded: (() -> Void)?
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
                return Row(session: session, segmentCount: segments.count, durationText: Self.durationText(session, segments),
                           pendingCount: segments.filter { $0.status == .pending }.count)
            }
            error = nil
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
        // Read once: a change while the microphone prompt is up does not change this session.
        let subject = context
        isStarting = true
        defer { isStarting = false }
        startError = nil
        guard await deps.requestMicrophone() else {
            startError = "Lifeline needs the microphone to record. Allow it in Settings."
            return
        }
        do {
            try deps.activateAudio()
        } catch {
            startError = "Could not start audio: \(error.localizedDescription)"
            return
        }
        let vm = SessionViewModel(deps: deps, kind: kind, subject: subject)
        presented = .session(vm)
        await vm.start()
    }

    /// A screen comes into view and names what a session started now would be about (nil: nothing).
    func show(_ subject: SessionSubject?, from screen: UUID) {
        context = subject
        contextScreen = screen
    }

    /// A screen leaves view. The context goes only if that screen set it.
    func leave(_ screen: UUID) {
        guard contextScreen == screen else { return }
        context = nil
        contextScreen = nil
    }

    /// Finish: the cover swaps to the landing. A session with no words lands quietly.
    /// The timeline refreshes last, so it reads the landed state and the cover's final state.
    func sessionEnded() {
        let ended = activeSession
        deps.deactivateAudio()
        if let ended, let id = ended.state.sessionID, let session = try? deps.sessions.fetch(id),
           !((try? deps.sessions.segments(in: id)) ?? []).isEmpty {
            presented = .landing(LandingViewModel(session: session, heavy: ended.heavy, presentDanger: ended.presentDanger, deps: deps))
        } else {
            if let id = ended?.state.sessionID { try? deps.sessions.markLanded(id) }
            presented = nil
        }
        refresh()
        onSessionEnded?()
    }

    func present(landing: LandingViewModel) { presented = .landing(landing) }

    /// "Another" is about the same page: the page under the cover still holds `context`, so the new
    /// session reads it as the first did (a page-started session's "Tell another" stays on that subject).
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
