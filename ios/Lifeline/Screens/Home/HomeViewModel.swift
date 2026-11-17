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
        /// The session was about a photo; its list name says so.
        var isPhotoStory: Bool { session.startedFrom == .photo }
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
    /// The last Start failed (microphone or audio). Shown on the record bar; cleared by the next Start
    /// and when the page on screen changes.
    private(set) var startError: StartError?
    /// Why the last Start failed. A refused microphone is told apart so the bar can offer Settings.
    enum StartError: Equatable {
        case microphoneDenied
        case audio(String)

        var message: String {
            switch self {
            case .microphoneDenied: "Lifeline needs the microphone to record. Allow it in Settings."
            case .audio(let detail): "Could not start audio: \(detail)"
            }
        }
    }
    var presented: Presented? {
        didSet { if presented == nil, oldValue != nil { coverClosings += 1 } }
    }
    /// Counts the times the session or landing cover closed. A page under the cover gets no
    /// `onAppear` when it closes, so a page on screen watches this to read what the session added.
    private(set) var coverClosings = 0
    /// The page on screen; nil on a tab root. A session started now is about it.
    private(set) var context: SessionSubject?
    /// The screen that set `context`. Pushing and popping can report the new screen's appearance
    /// before the old one's disappearance, so a screen that leaves clears only what it set itself.
    private var contextScreen: UUID?
    /// The subject of the session that just ended, for "Tell another". Nil after a kill, where a resumed
    /// landing has no known subject.
    private var lastSubject: SessionSubject?
    /// The session that just ended was about a photo. Task 5 reads it: "Tell another" then asks for a new photo.
    private(set) var lastWasPhoto = false
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
    /// A second tap while starting or recording does nothing. The subject is fixed by the caller: a page
    /// change while the microphone prompt is up does not change this session.
    func startSession(kind: SessionKind = .quick, subject: SessionSubject?) async {
        await begin(kind: kind, subject: subject, photo: nil)
    }

    /// A session about one photo, from the viewer once it has closed. It shares the guards and the
    /// microphone path of `startSession`; it is a quick story with no subject page.
    func startPhotoSession(_ photo: Photo) async {
        await begin(kind: .quick, subject: nil, photo: photo)
    }

    private func begin(kind: SessionKind, subject: SessionSubject?, photo: Photo?) async {
        guard !isStarting, activeSession == nil else { return }
        isStarting = true
        defer { isStarting = false }
        startError = nil
        guard await deps.requestMicrophone() else {
            startError = .microphoneDenied
            return
        }
        do {
            try deps.activateAudio()
        } catch {
            startError = .audio(error.localizedDescription)
            return
        }
        let vm = SessionViewModel(deps: deps, kind: kind, subject: subject, photo: photo)
        presented = .session(vm)
        await vm.start()
    }

    /// A start from the bar: about the page on screen.
    func startSession(kind: SessionKind = .quick) async {
        await startSession(kind: kind, subject: context)
    }

    /// A screen comes into view and names what a session started now would be about (nil: nothing).
    func show(_ subject: SessionSubject?, from screen: UUID) {
        context = subject
        contextScreen = screen
        startError = nil
    }

    /// A screen leaves view. The context goes only if that screen set it.
    func leave(_ screen: UUID) {
        guard contextScreen == screen else { return }
        context = nil
        contextScreen = nil
        startError = nil
    }

    /// Finish: the cover swaps to the landing. A session with no words lands quietly.
    /// The timeline refreshes last, so it reads the landed state and the cover's final state.
    func sessionEnded() {
        let ended = activeSession
        lastSubject = ended?.subject
        lastWasPhoto = ended?.photo != nil
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

    /// A resumed landing (after a kill) has no known subject, so its "Tell another" starts on the tab.
    func present(landing: LandingViewModel) {
        lastSubject = nil
        lastWasPhoto = false
        presented = .landing(landing)
    }

    /// The bar's action for a start error: Settings when the microphone is refused, otherwise try again.
    func startErrorTapped() async {
        if startError == .microphoneDenied { deps.openSettings() } else { await startSession(kind: .quick) }
    }

    /// The person moved to another tab: an old start error no longer belongs on the bar.
    func tabChanged() { startError = nil }

    /// "Another" is about the same subject as the session that just ended, and starts from the same page
    /// (a tab-started session stays on the tab). The page under the cover may already have left, so the
    /// subject comes from `lastSubject`, not `context`.
    func landingClosed(tellAnother: Bool) {
        presented = nil
        refresh()
        if tellAnother { Task { await startSession(kind: .quick, subject: lastSubject) } }
    }

    /// Duration from the last segment's end; falls back to the wall clock for a session with no segments.
    private static func durationText(_ session: Session, _ segments: [Segment]) -> String {
        if let last = segments.map(\.endMs).max() { return Format.duration(ms: last) }
        if let end = session.endedAt { return Format.duration(from: session.startedAt, to: end) }
        return "–"
    }
}
