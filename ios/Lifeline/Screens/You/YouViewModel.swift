import Foundation
import LifelineKit

/// The You page (S3): the portrait read in one batch, the line that leads it, and the chosen chip.
/// `Portrait` decides what goes where; this keeps the lead across refreshes and the filter across taps.
@MainActor
@Observable
final class YouViewModel {
    private(set) var portrait: Portrait?
    private(set) var lead: PortraitLine?
    /// The chosen chip; nil is "All". Not remembered across launches.
    var tag: String?
    /// False until the first `refresh(newLead:)`: the page says nothing about being empty before it has read.
    private(set) var isLoaded = false
    /// Why the page could not be read. Apart from `playError`: a play tap never hides a failed read, nor the reverse.
    private(set) var error: String?
    /// Why a line could not play. Cleared by the next tap.
    private(set) var playError: String?
    /// The line "Delete…" was chosen on, until the person confirms or cancels.
    var deleteTarget: PortraitLine?
    /// The memory just hidden, while "Hidden." offers Undo. Hiding is easy to do by mistake from a menu.
    private(set) var hiddenID: MemoryID?
    @ObservationIgnored private var hiddenTimer: Task<Void, Never>?
    let deps: Dependencies
    /// The one player: a line plays its own telling, and starting another stops the first.
    let player = SegmentPlayer()
    private(set) var playingLineID: PortraitLine.ID?

    /// Reads nothing: the page reads when it appears.
    init(deps: Dependencies) {
        self.deps = deps
    }

    /// One batched read. `newLead` picks the lead again (the root appeared); otherwise the lead stays
    /// while it can still lead (a session closed, Settings closed, a pushed page changed something).
    func refresh(newLead: Bool) {
        defer { isLoaded = true }
        do {
            let made = Portrait(try deps.extractionStore.portraitSource(), currentYear: CivilDate.today().year)
            portrait = made
            lead = made.lead(keeping: newLead ? nil : lead?.id, pick: deps.pickLead)
            // A chip whose tag is gone goes back to "All", so no chip shows selected that is not there.
            if let chosen = tag?.lowercased(), !tags.contains(where: { $0.lowercased() == chosen }) { tag = nil }
            error = nil
        } catch {
            self.error = "Could not read your page: \(error.localizedDescription)"
        }
    }

    /// The part's lines without the lead; "Who you are" only with the chosen tag.
    func lines(_ part: PortraitLine.Part) -> [PortraitLine] {
        portrait?.lines(part, leaving: lead?.id, tag: tag) ?? []
    }

    /// The chips after "All": the tags on the listed facts.
    var tags: [String] { portrait?.tags(leaving: lead?.id) ?? [] }

    /// What a story told from You is about: the owner, as "yourself".
    var ownerSubject: SessionSubject? {
        portrait?.owner.map { SessionSubject(entityID: $0.id, title: $0.title, isOwner: true, excludedFromAI: $0.excludedFromAI) }
    }

    /// A goal's "said in October": the session's start, which the app knows.
    func saidWhen(_ line: PortraitLine) -> String? {
        line.telling.map { Portrait.saidWhen($0.toldAt, now: .now, calendar: .current) }
    }

    /// "Hidden." with Undo for the usual window, as the kept-card close shows its notice.
    var hiddenNotice: String? { hiddenID == nil ? nil : "Hidden." }

    /// Hides a fact, feeling or goal from every page. It stops playing if it was playing. Idea lines are not memories.
    func hide(_ line: PortraitLine) {
        guard let memory = line.memory else { return }
        clearHiddenNotice()
        playError = nil
        if playingLineID == line.id { stop() }
        do {
            try deps.actions.setHidden(memory.id, true)
        } catch {
            self.error = "Could not hide that: \(error.localizedDescription)"
            return
        }
        hiddenID = memory.id
        hiddenTimer = Task { [weak self] in
            try? await Task.sleep(for: CardHandler.undoWindow)
            guard !Task.isCancelled else { return }
            self?.hiddenID = nil
        }
        refresh(newLead: false)
    }

    /// Takes the hide back: the memory is shown again and its line returns to its place. A failed write
    /// leaves the notice up, so the person can try again inside the window.
    func undoHide() {
        guard let id = hiddenID else { return }
        do {
            try deps.actions.setHidden(id, false)
        } catch {
            self.error = "Could not bring that back: \(error.localizedDescription)"
            return
        }
        clearHiddenNotice()
        refresh(newLead: false)
    }

    func clearHiddenNotice() {
        hiddenTimer?.cancel()
        hiddenTimer = nil
        hiddenID = nil
    }

    /// After the confirmation: the memory and its spans, people and anchors go; the recording stays. No undo.
    func delete(_ line: PortraitLine) {
        deleteTarget = nil
        guard let memory = line.memory else { return }
        clearHiddenNotice()
        playError = nil
        if playingLineID == line.id { stop() }
        do {
            try deps.extractionStore.memories.delete(memory.id)
        } catch {
            self.error = "Could not delete that: \(error.localizedDescription)"
            return
        }
        refresh(newLead: false)
    }

    func isPlaying(_ line: PortraitLine) -> Bool {
        playingLineID == line.id && player.playingRange != nil
    }

    /// Plays the line's telling; a second tap on the playing line stops it. A tap that cannot play says why
    /// and changes nothing else. A telling is not checked to be non-empty when it is read, so an empty span reaches here.
    func togglePlayback(_ line: PortraitLine) {
        playError = nil
        clearHiddenNotice()
        if isPlaying(line) { stop(); return }
        guard let telling = line.telling else { return }
        do {
            let url = try deps.audioURL(for: telling)
            // Say what failed: a missing file otherwise reads as an OSStatus number.
            guard FileManager.default.fileExists(atPath: url.path) else {
                playError = "Could not play this: the recording could not be found."
                return
            }
            try deps.activatePlayback()
            try player.play(url: url, range: telling.range)
            // The player stops itself and returns when the span is empty or past the end of the file.
            guard player.playingRange != nil else {
                playError = "Could not play this: there is nothing to play at that point of the recording."
                return
            }
            playingLineID = line.id
        } catch {
            playError = "Could not play this: \(error.localizedDescription)"
        }
    }

    func stop() {
        player.stop()
        playingLineID = nil
    }
}
