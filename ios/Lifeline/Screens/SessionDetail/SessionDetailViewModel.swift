import Foundation
import LifelineKit

@MainActor
@Observable
final class SessionDetailViewModel {
    struct MemoryRow: Identifiable {
        let memory: Memory
        let kind: MemoryKind
        let people: [String]
        let anchors: [String]
        var id: MemoryID { memory.id }
    }

    let session: Session
    private(set) var segments: [Segment] = []
    /// The person's moments with what the interviewer said between them, in file order.
    private(set) var transcript: [TranscriptItem] = []
    private(set) var memories: [MemoryRow] = []
    private(set) var waiting: [Card] = []
    private(set) var dismissed: [Candidate] = []
    private(set) var error: String?
    var changing: Memory?
    /// The page a checked entity or person chip opened.
    var openedEntity: Entity?
    let player = SegmentPlayer()
    /// The waiting cards as a queue, acted on with the same calls as the live session.
    let flow: CardFlow
    var cards: CardHandler { flow.handler }
    let deps: Dependencies
    /// The photo card of a photo session, at the top of the page; there is none for any other session.
    let photoCard: PhotoCardViewModel

    init(session: Session, deps: Dependencies) {
        self.session = session
        self.deps = deps
        photoCard = PhotoCardViewModel(session: session.id, deps: deps, showsRemoveFromStory: true)
        // The screen's onAppear loads it: SwiftUI may build and discard a model on a parent's render, so init stays cheap.
        flow = CardFlow(deps: deps)
        flow.onAutoClose = { [weak self] in self?.refresh() }
        // A date the card sets must show on the memory pages this screen opens: they start from its rows.
        photoCard.onAction = { [weak self] in self?.refresh() }
        // A name moved on a kept card can move the story's photo: the card and the rows show it at once.
        flow.handler.onPeopleMoved = { [weak self] in self?.refresh() }
    }

    func refresh() {
        photoCard.refresh()
        do {
            segments = try deps.sessions.segments(in: session.id)
            transcript = TranscriptItem.merge(segments: segments, turns: try InterviewerTurnRepository(deps.database).turns(in: session.id))
            // Every telling in this recording counts, including one merged into an older memory.
            var seen = Set<MemoryID>()
            memories = try deps.extractionStore.memories.spans(in: session.id).map(\.0).filter { seen.insert($0.id).inserted }.map { memory in
                MemoryRow(memory: memory,
                          kind: memory.kind,
                          people: try deps.extractionStore.memories.people(of: memory.id).map(\.displayName),
                          anchors: try deps.extractionStore.memories.anchors(of: memory.id).map(\.phrase))
            }
            let candidates = deps.extractionStore.candidates
            flow.reload(CardQueue.waiting(pending: try candidates.pending(in: session.id),
                                          segmentMemories: { (try? candidates.candidates(for: $0)) ?? [] },
                                          candidate: { try? candidates.fetch($0) }))
            let pending = flow.cards
            // Names a memory listed that never had their own card wait here as well.
            let segmentIDs = Set(segments.map(\.id))
            let shownNames = Set(pending.flatMap(\.withFollowUps).compactMap { if case .whoIsThis(_, let text) = $0 { PeopleRepository.normalize(text) } else { nil } })
            let openNames = try deps.extractionStore.people.mentions(status: .unresolved)
                .filter { segmentIDs.contains($0.segmentID) && !shownNames.contains(PeopleRepository.normalize($0.text)) }
                .map(Card.init)
            waiting = pending + openNames
            dismissed = try candidates.dismissed(in: session.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func bringBack(_ candidate: Candidate) {
        do { try deps.actions.restore(candidate); error = nil; refresh() }
        catch { self.error = "Could not bring that back: \(error.localizedDescription)" }
    }

    // Each action changes the queue as the live session does, then re-reads the store; the
    // rebuilt queue keeps the open kept card as it is on screen.
    func accept(_ card: Card) { if flow.accept(card) { refresh() } }
    func change(_ card: Card) { if let memory = flow.change(card) { refresh(); changing = memory } }
    func dismiss(_ card: Card) { if flow.dismiss(card) { refresh() } }
    func undo() { if flow.undo() { refresh() } }
    func undoMerge() { if flow.undoMerge() { refresh() } }
    func undoKeptClose() { if flow.undoKeptClose() { refresh() } }
    func sameStory(_ card: Card, into targets: [MemoryID]) { if flow.sameStory(card, into: targets) { refresh() } }
    func resolve(_ card: Card, _ choice: MentionChoice) { if flow.resolve(card, choice) { refresh() } }
    func followUp(_ kept: KeptCard, _ card: Card, as type: EntityType?) { if flow.followUp(kept, card, as: type) { refresh() } }
    func resolveFollowUp(_ kept: KeptCard, _ card: Card, _ choice: MentionChoice) { if flow.resolveFollowUp(kept, card, choice) { refresh() } }
    func declineFollowUp(_ kept: KeptCard, _ card: Card) { if flow.declineFollowUp(kept, card) { refresh() } }
    func keptDone(_ kept: KeptCard) { flow.keptDone(kept); refresh() }
    /// A checked entity or person chip, tapped again: its page.
    func open(_ followUp: Card) { openedEntity = flow.page(for: followUp) }

    func isPlaying(_ segment: Segment) -> Bool { player.playingRange == segment.range && player.isPlaying }

    /// Tap plays the segment's own span; a second tap on the same segment stops.
    func toggle(_ segment: Segment) {
        if player.playingRange == segment.range {
            player.stop()
            return
        }
        do {
            try deps.activatePlayback()   // .record would silence output; the default obeys the silent switch
            try player.play(url: try deps.audioURL(for: session), range: segment.range)
            error = nil
        } catch {
            self.error = "Could not play this moment: \(error.localizedDescription)"
        }
    }

    func stop() { player.stop() }
}
