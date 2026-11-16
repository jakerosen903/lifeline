import Foundation
import LifelineKit

/// The cards on a screen and what a tap does to them, shared by the live session, the session
/// detail and the timeline. Every memory action first closes the open kept card, as if "Done"
/// was tapped, so at most one is open and it belongs to the memory acted on last. A kept card
/// whose chips are all answered closes by itself a moment later.
@MainActor
@Observable
final class CardFlow {
    static let keptAutoClose: Duration = .milliseconds(1500)

    private(set) var queue = CardQueue()
    let handler: CardHandler
    /// Called after a kept card closed by itself, so the screen can re-read what closing wrote.
    @ObservationIgnored var onAutoClose: () -> Void = {}
    /// One pending auto-close per kept card, after its last chip was answered.
    @ObservationIgnored private var autoClose: [String: Task<Void, Never>] = [:]
    /// Answered entity and person chips, by follow-up id: the page a second tap opens.
    @ObservationIgnored private var pages: [String: EntityID] = [:]
    private let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
        handler = CardHandler(deps: deps)
    }

    var cards: [Card] { queue.cards }

    /// The live session: one extraction event.
    func apply(_ event: ExtractionEvent) { queue.apply(event) }

    /// Session detail and the timeline: the waiting cards rebuilt from the store. A kept card
    /// open on screen stays where it is, with the chips answered so far.
    func reload(_ fresh: CardQueue) {
        var fresh = fresh
        fresh.keepOpen(from: queue)
        queue = fresh
    }

    // MARK: - Memory and question cards

    /// Keep: the memory swaps for its kept card in place. Returns true when the card is done with.
    func accept(_ card: Card) -> Bool {
        closeAllKept()
        guard handler.accept(card) else { return false }
        queue.memoryAccepted(card.id)
        return true
    }

    /// Keep, then Change…: the memory to edit, or nil when Keep failed.
    func change(_ card: Card) -> Memory? {
        closeAllKept()
        guard let memory = handler.keep(card) else { return nil }
        queue.memoryAccepted(card.id)
        return memory
    }

    func dismiss(_ card: Card) -> Bool {
        if case .memory = card { closeAllKept() }
        guard handler.dismiss(card) else { return false }
        if case .memory = card { queue.memoryDismissed(card.id) } else { queue.remove(card.id) }
        return true
    }

    func undo() -> Bool {
        guard let card = handler.undo() else { return false }
        queue.restore(card)
        return true
    }

    func undoMerge() -> Bool {
        guard let card = handler.undoMerge() else { return false }
        queue.restore(card)
        return true
    }

    /// Undo under "n suggestions dismissed.": the kept cards a close took away come back.
    func undoKeptClose() -> Bool {
        let cards = handler.undoKeptClose()
        cards.forEach { queue.reopenKept($0) }
        return !cards.isEmpty
    }

    /// "Same story": the card joins an earlier memory; its follow-ups follow as if it were kept.
    func sameStory(_ card: Card, into targets: [MemoryID]) -> Bool {
        closeAllKept()
        guard handler.sameStory(card, into: targets) else { return false }
        queue.memoryAccepted(card.id)
        return true
    }

    /// A "Who's this?" card of its own (People, open names).
    func resolve(_ card: Card, _ choice: MentionChoice) -> Bool {
        guard handler.resolve(card, choice) else { return false }
        queue.remove(card.id)
        return true
    }

    // MARK: - Kept cards

    /// A hint, thing, place or idea chip: accepted as heard or as the type chosen. Never leaves
    /// the screen for the entity's page. Returns true when the chip is answered.
    func followUp(_ kept: KeptCard, _ card: Card, as type: EntityType?) -> Bool {
        if case .entity = card {
            guard let entity = handler.acceptEntity(card, as: type) else { return false }
            pages[card.id] = entity.id
        } else {
            guard handler.acceptFollowUp(card, as: type) else { return false }
        }
        answered(card, in: kept)
        return true
    }

    /// A person chip answered in its "Who's this?" sheet.
    func resolveFollowUp(_ kept: KeptCard, _ card: Card, _ choice: MentionChoice) -> Bool {
        let (done, person) = handler.resolvePerson(card, choice)
        guard done else { return false }
        if let person { pages[card.id] = person.entityID }
        answered(card, in: kept)
        return true
    }

    /// "Not any of these" on an entity chip.
    func declineFollowUp(_ kept: KeptCard, _ card: Card) -> Bool {
        guard handler.declineFollowUp(card) else { return false }
        answered(card, in: kept)
        return true
    }

    /// "Done": unanswered hints and entities are dismissed, unanswered people wait in People.
    func keptDone(_ kept: KeptCard) { closeKept(kept.memoryCandidateID) }

    /// Whether a checked chip has a page: an entity kept or a person named on this screen.
    func hasPage(_ followUp: Card) -> Bool { pages[followUp.id] != nil }

    /// The page of a checked entity or person chip, or nil (a hint, "Not a person", or a chip
    /// answered before this screen opened).
    func page(for followUp: Card) -> Entity? {
        guard let id = pages[followUp.id] else { return nil }
        return try? deps.extractionStore.entities.entity(id: id)
    }

    /// The last chip answered closes the card 1.5 s later, unless Done or another memory action
    /// closed it first, or a late follow-up joined it meanwhile.
    private func answered(_ card: Card, in kept: KeptCard) {
        let id = kept.memoryCandidateID
        guard queue.answered(card.id, in: id) else { return }
        autoClose[id]?.cancel()
        autoClose[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.keptAutoClose)
            guard !Task.isCancelled, let self else { return }
            self.autoClose[id] = nil
            guard case .kept(let current)? = self.queue.cards.first(where: { $0.id == id }), current.isComplete else { return }
            self.closeKept(id)
            self.onAutoClose()
        }
    }

    private func closeKept(_ id: String) {
        autoClose.removeValue(forKey: id)?.cancel()
        handler.close(queue.closeKept(id))
    }

    private func closeAllKept() {
        autoClose.values.forEach { $0.cancel() }
        autoClose.removeAll()
        handler.close(queue.closeAllKept())
    }
}
