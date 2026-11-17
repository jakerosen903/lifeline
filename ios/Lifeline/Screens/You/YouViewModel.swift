import LifelineKit
import SwiftUI

/// What the slot at the foot of You says: "Hidden.", or why something failed.
enum YouNotice: Equatable {
    case hidden
    case error(String)

    var text: String {
        switch self {
        case .hidden: "Hidden."
        case .error(let message): message
        }
    }
}

/// The You page (S3): the portrait read in one batch, the line that leads it, and the chosen chip.
/// `Portrait` decides what goes where; this keeps the lead across refreshes and the filter across taps.
@MainActor
@Observable
final class YouViewModel {
    private(set) var portrait: Portrait?
    private(set) var lead: PortraitLine?
    /// False until the first `refresh(newLead:)`: the page says nothing about being empty before it has read.
    private(set) var isLoaded = false
    /// Why the page could not be read. It keeps its own place: a message in the slot never hides a failed read, nor the reverse.
    private(set) var error: String?
    /// The one slot at the foot of the page: "Hidden." or why a play, a hide, a delete or an undo failed. One at a
    /// time; a newer message replaces the older. Pinned above the record bar, so it shows wherever the line was.
    private(set) var notice: YouNotice?
    /// The line "Delete…" was chosen on, until the person confirms or cancels.
    var deleteTarget: PortraitLine?
    /// The memory just hidden, while Undo is offered. Hiding is easy to do by mistake from a menu. Undo stays in the
    /// slot for its window even when an error replaces "Hidden.", so a failure never takes the way back with it.
    private(set) var hiddenID: MemoryID?
    @ObservationIgnored private var hiddenTimer: Task<Void, Never>?
    /// Says a new message to VoiceOver. Called by the code that sets the message, so the same text twice is said twice.
    @ObservationIgnored var announce: (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    let deps: Dependencies
    /// The one player: a line plays its own telling, and starting another stops the first.
    let player = SegmentPlayer()
    private(set) var playingLineID: PortraitLine.ID?
    /// The chosen chip; nil is "All". Not remembered across launches. A chip that filters out the playing line stops it.
    var tag: String? { didSet { stopIfPlayingLineIsGone() } }
    /// The owner's photos (S4, decision 15), the same shelf as the owner's own page. Nil until the owner is known.
    private(set) var shelf: PhotoShelf?

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
            // A new lead is a fresh look at the page: an old play error must not sit under it.
            if newLead, case .error = notice { notice = nil }
            stopIfPlayingLineIsGone()
            error = nil
            placeShelf(owner: made.owner)
        } catch {
            self.error = "Could not read your page: \(error.localizedDescription)"
        }
        shelf?.load()
    }

    /// One shelf per owner. Made once the owner is known; a failure says why in the slot at the foot of the page.
    private func placeShelf(owner: Entity?) {
        guard let owner else { shelf = nil; return }
        guard shelf?.subject != .entity(owner.id) else { return }
        shelf = PhotoShelf(subject: .entity(owner.id), deps: deps, onError: { [weak self] in self?.show(.error($0)) })
    }

    // MARK: - Photos

    /// "Photo of you" (decision 19), as on the owner's own page.
    var photoLabel: String { PhotoCaption.label(title: "", isOwner: true, isMemory: false) }

    /// A photo action clears an old error only. "Hidden." and its Undo stay, so an action never takes the way back.
    func addPhoto(fileAt file: URL, assetLocalID: String?) async {
        clearError()
        await shelf?.add(fileAt: file, assetLocalID: assetLocalID)
    }

    func makeCover(_ photo: PhotoID) async {
        clearError()
        await shelf?.makeCover(photo)
    }

    func removePhoto(_ photo: PhotoID) async {
        clearError()
        await shelf?.remove(photo)
    }

    /// A picked photo that never reached the shelf (the picker could not hand it over).
    func photoFailed(_ message: String) { show(.error(message)) }

    /// Empties the slot of an error, and only of an error.
    func clearError() {
        if case .error = notice { notice = nil }
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

    /// Hides a fact, feeling or goal from every page. Idea lines are not memories. The earlier notice and its Undo
    /// go only once this write succeeds: a failed second hide keeps the first one's Undo. Playback of the line
    /// stops when the refresh takes it off the page.
    func hide(_ line: PortraitLine) {
        guard let memory = line.memory else { return }
        do {
            try deps.actions.setHidden(memory.id, true)
        } catch {
            show(.error("Could not hide that: \(error.localizedDescription)"))
            return
        }
        offerUndo(memory.id)
        show(.hidden)
        refresh(newLead: false)
    }

    /// Takes the hide back: the memory is shown again and its line returns to its place. A failed write
    /// keeps Undo in the slot, so the person can try again inside the window.
    func undoHide() {
        guard let id = hiddenID else { return }
        do {
            try deps.actions.setHidden(id, false)
        } catch {
            show(.error("Could not bring that back: \(error.localizedDescription)"))
            return
        }
        clearSlot()
        refresh(newLead: false)
    }

    /// Empties the slot and ends the Undo window: You disappeared, or a newer action took its place.
    func clearSlot() {
        hiddenTimer?.cancel()
        hiddenTimer = nil
        hiddenID = nil
        notice = nil
    }

    /// After the confirmation: the memory and its spans, people and anchors go; the recording stays. No undo.
    /// A failed delete keeps an earlier Undo; a done one replaces it.
    func delete(_ line: PortraitLine) {
        deleteTarget = nil
        guard let memory = line.memory else { return }
        do {
            try deps.extractionStore.memories.delete(memory.id)
        } catch {
            show(.error("Could not delete that: \(error.localizedDescription)"))
            return
        }
        clearSlot()
        refresh(newLead: false)
    }

    private func show(_ message: YouNotice) {
        notice = message
        announce(message.text)
    }

    private func offerUndo(_ id: MemoryID) {
        hiddenTimer?.cancel()
        hiddenID = id
        hiddenTimer = Task { [weak self] in
            try? await Task.sleep(for: CardHandler.undoWindow)
            guard !Task.isCancelled, let self else { return }
            self.hiddenID = nil
            if self.notice == .hidden { self.notice = nil }
        }
    }

    /// The lead and every line the page shows now, with the chosen chip.
    private var shownLineIDs: Set<PortraitLine.ID> {
        let parts: [PortraitLine.Part] = [.whoYouAre, .howItFelt, .whatYouThink, .hopingFor]
        return Set(parts.flatMap { lines($0).map(\.id) } + [lead?.id].compactMap { $0 })
    }

    /// A line that left the page (hidden, deleted, filtered out by a chip) does not go on talking.
    private func stopIfPlayingLineIsGone() {
        guard let playing = playingLineID, !shownLineIDs.contains(playing) else { return }
        stop()
    }

    func isPlaying(_ line: PortraitLine) -> Bool {
        playingLineID == line.id && player.playingRange != nil
    }

    /// Plays the line's telling; a second tap on the playing line stops it. A tap that cannot play says why
    /// and changes nothing else. A telling is not checked to be non-empty when it is read, so an empty span reaches here.
    func togglePlayback(_ line: PortraitLine) {
        // A play tap clears an old error only. "Hidden." and its Undo stay, so a tap never takes the way back.
        clearError()
        if isPlaying(line) { stop(); return }
        guard let telling = line.telling else { return }
        do {
            let url = try deps.audioURL(for: telling)
            // Say what failed: a missing file otherwise reads as an OSStatus number.
            guard FileManager.default.fileExists(atPath: url.path) else {
                show(.error("Could not play this: the recording could not be found."))
                return
            }
            try deps.activatePlayback()
            try player.play(url: url, range: telling.range)
            // The player stops itself and returns when the span is empty or past the end of the file.
            guard player.playingRange != nil else {
                show(.error("Could not play this: there is nothing to play at that point of the recording."))
                return
            }
            playingLineID = line.id
        } catch {
            show(.error("Could not play this: \(error.localizedDescription)"))
        }
    }

    func stop() {
        player.stop()
        playingLineID = nil
    }
}
