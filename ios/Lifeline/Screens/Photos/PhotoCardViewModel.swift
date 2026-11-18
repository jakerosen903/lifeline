import Foundation
import LifelineKit

/// The photo card of one photo session: what `PhotoStoryReader` says, and what a person can do with it: take the photo off a
/// memory, add it to a page or take it off, use its date for some memories and undo that, and let the story go of it.
/// It holds no rule. Every action writes through the kit, then reads the card again, so the card always shows the store.
@MainActor
@Observable
final class PhotoCardViewModel {
    private let session: SessionID
    private let deps: Dependencies
    /// The session's page can let the session go of its photo; the landing cannot.
    let showsRemoveFromStory: Bool
    /// Nil for an ordinary session, and once the story has let go of its photo.
    private(set) var card: PhotoStoryCard?
    /// True after the first read. Reads nothing in `init`: the screen calls `refresh()` when it is on screen.
    private(set) var isLoaded = false
    /// Why the card cannot show, or why the last action failed, for `photoErrorSlot`. The action's message wins:
    /// a read right after a failed action must not hide why the action failed.
    var error: String? { actionError ?? readError }
    /// The last read failed. The next good read clears it (the landing reads every second).
    private var readError: String?
    /// The last action failed. The next action clears it.
    private var actionError: String?
    /// What the date taps on this screen changed, for "Undo" (plan decisions 3 and 4). It lives as long as the screen.
    private var used: [PhotoDateChange] = []
    /// The memories those taps settled: written, or offered and left unchecked (decision 5; `PhotoDatePart.seen`).
    private var seen: Set<MemoryID> = []
    /// Pages whose tap is still being written: a second tap on the same chip waits for the first to land.
    private var toggling: Set<EntityID> = []
    /// Called after each action, once the card has read the store again: the screen around the card reads its own rows
    /// again, so a memory opened from them shows the date the card just wrote.
    @ObservationIgnored var onAction: () -> Void = {}

    init(session: SessionID, deps: Dependencies, showsRemoveFromStory: Bool) {
        self.session = session
        self.deps = deps
        self.showsRemoveFromStory = showsRemoveFromStory
    }

    /// "When did this happen?": which state it is in, and its words.
    var datePart: PhotoDatePart {
        PhotoDatePart.state(offer: card?.dateOffer, holdingCount: card?.memories.count ?? 0, used: used, seen: seen)
    }

    /// Publishes a card only when it differs: the landing calls this every second while sorting goes on, and an
    /// unchanged card must not redraw (no flicker, no lost scroll position).
    func refresh() {
        do {
            let fresh = try reader.card(for: session)
            if fresh != card { card = fresh }
            isLoaded = true
            readError = nil
        } catch {
            readError = "Could not show the photo: \(error.localizedDescription)"
        }
    }

    /// A chosen chip takes the photo off the page (the page's next photo becomes its key photo); any other chip adds it,
    /// as the key photo only when the page has none (S4).
    func toggle(_ page: PhotoStoryCard.Page) async {
        guard let photo = card?.photo.id, toggling.insert(page.id).inserted else { return }
        defer { toggling.remove(page.id) }
        if page.isChosen {
            await perform("Could not take the photo off this page") { try await deps.photos.remove(photo, from: .entity(page.id)) }
        } else {
            run("Could not add the photo to this page") { try reader.addToPage(photo, page.id) }
        }
    }

    /// "Use for those 2", or the sheet's "Use for {n}": the offer's day for the `chosen` memories, in one write. `offered` is
    /// what the control showed when it was drawn (the button's offer, or the set the sheet captured), not the card's offer now:
    /// a memory kept while the sheet was open, or skipped as stale, was never declined and keeps its offer.
    /// If the write lands and the resolver run after it throws, the dates are stored but no change comes back: the error shows,
    /// the card reads the store again, and those memories are no longer offered. Their pages show "from a photo".
    func useDate(for memories: [Memory], offered: [Memory]) {
        guard let offer = card?.dateOffer else { return }
        var once = Set(used.map(\.memory))
        // Each memory once: a second change for one memory would make Undo put back the photo's date, not the range before.
        let fresh = memories.filter { once.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        run("Could not use the photo's date") {
            let changes = try reader.useDate(offer.date, for: fresh)
            // A tap that changed nothing (every memory changed elsewhere first) leaves the part as it was.
            guard !changes.isEmpty else { return }
            used += changes
            seen.formUnion(PhotoDatePart.seen(offered: offered, chosen: memories, changed: changes.map(\.memory)))
        }
    }

    /// "Undo": puts back every range the taps changed. The part then shows the state before the taps, also when the write
    /// put back nothing (each memory changed after the tap). A failed write keeps the changes, so Undo can be tried again.
    func undoDate() {
        run("Could not undo the date") {
            try reader.undoDate(used)
            used = []
            seen = []
        }
    }

    /// "Remove" on one memory: unlinks the photo from it. The photo stays on the story while the session points at it.
    func removeFromMemory(_ memory: Memory) async {
        guard let photo = card?.photo.id else { return }
        await perform("Could not remove the photo") { try await deps.photos.remove(photo, from: .memory(memory.id)) }
    }

    /// "Remove the photo from this story": the session lets go. Links to memories and pages stay.
    func removeFromStory() async {
        await perform("Could not remove the photo from this story") { try await deps.photos.removeFromStory(session) }
    }

    private var reader: PhotoStoryReader { PhotoStoryReader(store: deps.extractionStore) }

    private func run(_ failure: String, _ work: () throws -> Void) {
        actionError = nil
        do { try work() } catch { actionError = "\(failure): \(error.localizedDescription)" }
        refresh()
        onAction()
    }

    private func perform(_ failure: String, _ work: () async throws -> Void) async {
        actionError = nil
        do { try await work() } catch { actionError = "\(failure): \(error.localizedDescription)" }
        refresh()
        onAction()
    }
}
