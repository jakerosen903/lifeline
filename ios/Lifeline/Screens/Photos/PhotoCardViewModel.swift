import Foundation
import LifelineKit

/// The photo card of one photo session: what `PhotoStoryReader` says, and the five things a person can do with it.
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

    init(session: SessionID, deps: Dependencies, showsRemoveFromStory: Bool) {
        self.session = session
        self.deps = deps
        self.showsRemoveFromStory = showsRemoveFromStory
    }

    /// Publishes a card only when it differs: the landing calls this every second while sorting goes on, and an
    /// unchanged card must not redraw (no flicker, no lost scroll position).
    func refresh() {
        do {
            let fresh = try PhotoStoryReader(store: deps.extractionStore).card(for: session)
            if fresh != card { card = fresh }
            isLoaded = true
            readError = nil
        } catch {
            readError = "Could not show the photo: \(error.localizedDescription)"
        }
    }

    /// "Add to {title}'s page", or "Add to your page" for the owner.
    func offerTitle(_ page: Entity) -> String {
        page.id == card?.ownerEntity ? "Add to your page" : "Add to \(page.title)'s page"
    }

    func addToPage(_ page: Entity) {
        guard let photo = card?.photo.id else { return }
        run("Could not add the photo to this page") { try PhotoStoryReader(store: deps.extractionStore).addToPage(photo, page.id) }
    }

    func useDate(_ offer: PhotoStoryCard.DateOffer) {
        run("Could not use the photo's date") { try PhotoStoryReader(store: deps.extractionStore).useDate(offer) }
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

    private func run(_ failure: String, _ work: () throws -> Void) {
        actionError = nil
        do { try work() } catch { actionError = "\(failure): \(error.localizedDescription)" }
        refresh()
    }

    private func perform(_ failure: String, _ work: () async throws -> Void) async {
        actionError = nil
        do { try await work() } catch { actionError = "\(failure): \(error.localizedDescription)" }
        refresh()
    }
}
