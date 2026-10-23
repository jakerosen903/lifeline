import Foundation
import LifelineKit

/// R6 Landing / R4 FirstPayoff. Shows what was saved and plays it back; asks for nothing.
/// While sorting is still going on it re-reads the rows every second so they fill in.
@MainActor
@Observable
final class LandingViewModel: Identifiable {
    let id = UUID()
    private(set) var session: Session
    let heavy: Bool
    let presentDanger: Bool
    private(set) var rows: [LandingRow] = []
    private(set) var more = 0
    private(set) var stillSorting: String?
    private(set) var closingLine = ""
    private(set) var isFirst = false
    private(set) var error: String?
    /// Set when the person chose; the screen closes. `true` means "Tell another".
    private(set) var finished: Bool?
    var confirmingDelete = false
    let player = SegmentPlayer()
    let deps: Dependencies
    private var poll: Task<Void, Never>?

    init(session: Session, heavy: Bool, presentDanger: Bool, deps: Dependencies) {
        self.session = session
        self.heavy = heavy
        self.presentDanger = presentDanger
        self.deps = deps
        refresh()
    }

    /// A session recovered after a crash: heavy if its log says so.
    convenience init(resuming session: Session, deps: Dependencies) {
        let log = (try? SessionArc.decode(session.stageLog)) ?? []
        let heavy = log.contains { $0.reason == "disclosure" || $0.reason == "wantsToStop" }
        self.init(session: session, heavy: heavy, presentDanger: false, deps: deps)
    }

    var headline: String { Landing.headline(first: isFirst, heavy: heavy) }
    var crisisLine: CrisisLine? { presentDanger ? FixedResponses.crisisLine() : nil }
    var moreText: String? { more > 0 ? "and \(more) more in Sessions" : nil }

    func refresh() {
        do {
            let store = deps.extractionStore
            session = try store.sessions.fetch(session.id) ?? session
            let segments = try store.sessions.segments(in: session.id)
            let kept = try store.memories.memories(in: session.id).compactMap { memory -> (Memory, MemorySpan)? in
                guard let span = try store.memories.spans(of: memory.id).first else { return nil }
                return (memory, span)
            }
            let possible = try store.candidates.pending(in: session.id).compactMap { candidate -> (Candidate, MemoryOut)? in
                guard let out = CandidatePayload.memory(candidate) else { return nil }
                return (candidate, out)
            }
            (rows, more) = Landing.rows(kept: kept, possible: possible, segments: segments)
            let pending = segments.filter { $0.status == .pending }.count
            stillSorting = Landing.stillSorting(pendingSegments: pending)
            closingLine = Landing.closingLine(topCuriosity: try store.curiosity.open().first, heavy: heavy)
            isFirst = Landing.isFirstSession(sessionCount: try store.sessions.listSessions().count)
            error = nil
            if pending > 0 { startPolling() } else { poll?.cancel() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startPolling() {
        guard poll == nil || poll?.isCancelled == true else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    // MARK: - Playback

    func isPlaying(_ row: LandingRow) -> Bool { player.playingRange == row.play && player.isPlaying }

    func toggle(_ row: LandingRow) {
        if player.playingRange == row.play, player.isPlaying { player.stop(); return }
        do {
            try deps.activatePlayback()
            try player.play(url: try deps.audioURL(for: session), range: row.play)
        } catch {
            self.error = "Could not play this moment: \(error.localizedDescription)"
        }
    }

    // MARK: - Choices (none is required; Done for now is the default)

    func doneForNow() { land(tellAnother: false) }

    func tellAnother() { land(tellAnother: true) }

    func hideToday() {
        do { try deps.actions.hideSession(session.id) } catch { self.error = "Could not hide today: \(error.localizedDescription)"; return }
        land(tellAnother: false)
    }

    /// After the confirmation. The worker drops its pending work first, then the file and rows go.
    func deleteToday() async {
        await deps.worker.cancel(session: session.id)
        do {
            try deps.actions.deleteSession(session.id, audioURL: try deps.audioURL(for: session))
        } catch {
            self.error = "Could not delete today's recording: \(error.localizedDescription)"
            return
        }
        poll?.cancel()
        player.stop()
        finished = false
    }

    private func land(tellAnother: Bool) {
        poll?.cancel()
        player.stop()
        do { try deps.sessions.markLanded(session.id, stageLog: session.stageLog) } catch { self.error = error.localizedDescription }
        finished = tellAnother
    }

    func stop() { player.stop(); poll?.cancel() }
}
