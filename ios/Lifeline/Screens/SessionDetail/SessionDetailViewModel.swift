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
    private(set) var memories: [MemoryRow] = []
    private(set) var waiting: [Card] = []
    private(set) var dismissed: [Candidate] = []
    private(set) var error: String?
    var changing: Memory?
    let player = SegmentPlayer()
    let cards: CardHandler
    let deps: Dependencies

    init(session: Session, deps: Dependencies) {
        self.session = session
        self.deps = deps
        cards = CardHandler(deps: deps)
        refresh()
    }

    func refresh() {
        do {
            segments = try deps.sessions.segments(in: session.id)
            memories = try deps.extractionStore.memories.memories(in: session.id).map { memory in
                MemoryRow(memory: memory,
                          kind: memory.createdFromCandidateID.flatMap { try? deps.extractionStore.candidates.fetch($0) }.flatMap { CandidatePayload.memory($0) }?.kindOrDefault ?? .other,
                          people: try deps.extractionStore.memories.people(of: memory.id).map(\.displayName),
                          anchors: try deps.extractionStore.memories.anchors(of: memory.id).map(\.phrase))
            }
            let candidates = deps.extractionStore.candidates
            let pending = CardQueue.waitingCards(pending: try candidates.pending(in: session.id)) { (try? candidates.fetch($0))?.status }
            // Names a memory listed that never had their own card wait here as well.
            let segmentIDs = Set(segments.map(\.id))
            let shownNames = Set(pending.compactMap { if case .whoIsThis(_, let text) = $0 { PeopleRepository.normalize(text) } else { nil } })
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

    func accept(_ card: Card) { if cards.accept(card) { refresh() } }
    func change(_ card: Card) { if let memory = cards.keep(card) { refresh(); changing = memory } }
    func dismiss(_ card: Card) { if cards.dismiss(card) { refresh() } }
    func undo() { if cards.undo() != nil { refresh() } }
    func resolve(_ card: Card, _ choice: MentionChoice) { if cards.resolve(card, choice) { refresh() } }

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
