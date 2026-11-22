import Foundation
import LifelineKit

/// R6 Landing / R4 FirstPayoff. Shows what was saved and plays it back; asks for nothing.
/// While sorting is still going on it re-reads the rows every second so they fill in.
@MainActor
@Observable
final class LandingViewModel: Identifiable {
    let id = UUID()
    private(set) var session: Session
    /// What the live arc knew at Finish; storage can add to it (a flag that arrived after).
    private let liveWeight: SessionWeight
    private(set) var weight: SessionWeight
    var heavy: Bool { weight.heavy }
    var presentDanger: Bool { weight.presentDanger }
    private(set) var rows: [LandingRow] = []
    private(set) var more = 0
    private(set) var stillSorting: String?
    private(set) var closingLine = ""
    private(set) var isFirst = false
    /// "I made 2 guesses about who you meant.", for the whole session, or nil with none.
    private(set) var guesses: String?
    /// Each row's people: a kept memory's links, or what Keep will link for a card that waits.
    private(set) var people: [LandingRow.ID: [PersonChipRow.Item]] = [:]
    /// Links of this recording's memories that name someone other than the owner. The screen asks for contacts
    /// when this becomes one or more (`ContactsPromptRule`).
    private(set) var keptPeople = 0
    /// "Changed to {name}." with Undo, after the sheet moved a name.
    let personMove: PersonMoveUndo
    private(set) var error: String?
    /// Set when the person chose; the screen closes. `true` means "Tell another".
    private(set) var finished: Bool?
    var confirmingDelete = false
    let player = SegmentPlayer()
    let deps: Dependencies
    /// The photo card of a photo session; it has no card for any other. Refreshed with the rows, on the same tick.
    let photoCard: PhotoCardViewModel
    private var poll: Task<Void, Never>?
    /// Set when the contacts prompt is asked for, so a second read of the rows cannot ask twice.
    private var askingForContacts = false

    init(session: Session, heavy: Bool, presentDanger: Bool, deps: Dependencies) {
        self.session = session
        liveWeight = SessionWeight(heavy: heavy, presentDanger: presentDanger)
        weight = liveWeight
        self.deps = deps
        personMove = PersonMoveUndo(actions: deps.personLinkActions())
        photoCard = PhotoCardViewModel(session: session.id, deps: deps, showsRemoveFromStory: false)
        refresh()
    }

    /// A session recovered after a crash: heavy if its log or its stored flags say so.
    convenience init(resuming session: Session, deps: Dependencies) {
        self.init(session: session, heavy: false, presentDanger: false, deps: deps)
    }

    var headline: String { Landing.headline(first: isFirst, heavy: heavy) }
    var crisisLine: CrisisLine? { presentDanger ? FixedResponses.crisisLine() : nil }
    var moreText: String? { more > 0 ? "and \(more) more in Sessions" : nil }

    /// "…This cannot be undone." and, when the session was the photo's last home, "Its photo goes too."
    var deleteMessage: String {
        ["The audio, the words and the \(rows.count + more) moments from today go. This cannot be undone.",
         PhotoStory.deleteSentence(card: photoCard.card)].compactMap { $0 }.joined(separator: " ")
    }

    func refresh() {
        do {
            let store = deps.extractionStore
            session = try store.sessions.fetch(session.id) ?? session
            let segments = try store.sessions.segments(in: session.id)
            // A telling merged into an older memory is a kept moment of this session too (M4.1).
            let kept = try store.memories.spans(in: session.id)
            let possible = try store.candidates.pending(in: session.id).compactMap { candidate -> (Candidate, MemoryOut)? in
                guard let out = CandidatePayload.memory(candidate) else { return nil }
                return (candidate, out)
            }
            (rows, more) = Landing.rows(kept: kept, possible: possible, segments: segments)
            people = try chips(for: rows, possible: possible.map(\.0))
            guesses = PersonChipLine.landingLine(guesses: try store.personLinks.guessCount(in: session.id))
            keptPeople = try store.personLinks.keptPeopleCount(in: session.id)
            weight = liveWeight
                || SessionWeight.of(candidates: try store.candidates.candidates(in: session.id))
                || SessionWeight.of(log: (try? SessionArc.decode(session.stageLog)) ?? [])
            let pending = segments.filter { $0.status == .pending }.count
            stillSorting = Landing.stillSorting(pendingSegments: pending)
            closingLine = Landing.closingLine(topCuriosity: try store.curiosity.open().first, heavy: heavy)
            isFirst = Landing.isFirstSession(sessionCount: try store.sessions.listSessions().count)
            photoCard.refresh()
            error = nil
            if pending > 0 { startPolling() } else { poll?.cancel() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func chips(for rows: [LandingRow], possible: [Candidate]) throws -> [LandingRow.ID: [PersonChipRow.Item]] {
        let store = deps.extractionStore
        let preview = deps.personLinkActions()
        let waiting = Dictionary(possible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var chips: [LandingRow.ID: [PersonChipRow.Item]] = [:]
        for row in rows {
            switch row.source {
            case .memory(let memory):
                chips[row.id] = try store.personLinks.links(of: memory).map(PersonChipRow.Item.init(link:))
            case .candidate(let id):
                guard let candidate = waiting[id] else { continue }
                chips[row.id] = try preview.preview(candidate).map { .init(chip: $0, on: candidate) }
            }
        }
        return chips
    }

    /// What "Done" in the sheet did: the line and the chips are read again.
    func personSheetDone(_ outcome: WhoIsThisViewModel.Outcome) {
        if case .unchanged = outcome { return }
        personMove.note(outcome)
        refresh()
    }

    func undoPersonMove() {
        if personMove.undo() { refresh() }
    }

    // MARK: - Contacts (spec, "Access")

    /// The one system prompt, on the landing of the recording whose kept moments first name a person, unless the
    /// recording was heavy or a serious disclosure showed (PB36): then the next quiet landing asks. On a yes the
    /// app looks at this recording's new people again (plan decision 7), then the chips and the guess line read again.
    /// Not heavy, no serious disclosure, and sorting done: a flag from a segment still sorting could make it heavy.
    var isQuietForContacts: Bool { !heavy && !presentDanger && stillSorting == nil }

    func askForContactsIfDue() async {
        let prompt = ContactsAccessPrompt(deps: deps)
        guard !askingForContacts, prompt.shouldAsk(keptPeopleInSession: keptPeople, landingIsQuiet: isQuietForContacts) else { return }
        askingForContacts = true
        if await prompt.askOnLanding(session: session.id) { refresh() }
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
            // The dialog may have said "Its photo goes too.": the session's row is gone now, so the library's sweep takes the photo.
            // A failed sweep is not a failed delete; the next launch sweeps again.
            do { try await deps.photos.sweep() } catch { print("[photos] sweep after a delete failed: \(error)") }
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
        do { try deps.sessions.markLanded(session.id) } catch { self.error = error.localizedDescription }
        finished = tellAnother
    }

    func stop() { player.stop(); poll?.cancel() }
}
