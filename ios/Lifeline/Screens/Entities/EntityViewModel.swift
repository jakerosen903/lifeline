import Foundation
import LifelineKit

/// One person, place, thing or idea (M7): its details first, in the person's words, then the
/// moments it appears in, then what co-occurs. An idea reads top to bottom in date order.
@MainActor
@Observable
final class EntityViewModel {
    private(set) var entity: Entity
    private(set) var details: [Memory] = []
    private(set) var moments: [Memory] = []
    /// An idea: details and moments together, oldest first (Goal 4).
    private(set) var ideaLines: [Memory] = []
    private(set) var coOccurring: [Entity] = []
    private(set) var spanText = "no dates yet"
    private(set) var tags: [String] = []
    private(set) var firstTelling: (span: EntitySpan, session: Session)?
    private(set) var isGone = false
    private(set) var error: String?
    let player = SegmentPlayer()
    let deps: Dependencies

    init(entity: Entity, deps: Dependencies) {
        self.entity = entity
        self.deps = deps
        refresh()
    }

    /// "Add dates" is offered only on a place or a thing, and only as the person's own action.
    var canAddDates: Bool { entity.type == .place || entity.type == .thing }
    var isPlaying: Bool { player.isPlaying }

    func refresh() {
        do {
            let store = deps.extractionStore
            guard let current = try store.entities.entity(id: entity.id) else { isGone = true; return }
            entity = current
            details = try store.entities.details(of: entity.id).filter { !$0.hiddenFromTimeline }
            moments = try store.entities.moments(of: entity.id).filter { !$0.hiddenFromTimeline }
            if entity.type == .idea {
                var told: [MemoryID: Date] = [:]
                for memory in details + moments {
                    if let span = try store.memories.spans(of: memory.id).first, let segment = try store.sessions.fetchSegment(span.segmentID),
                       let session = try store.sessions.fetch(segment.sessionID) { told[memory.id] = session.startedAt }
                }
                ideaLines = EntityPage.ordered(details + moments, toldAt: told)
            }
            spanText = EntityPage.spanText(try store.entities.span(of: entity.id))
            tags = try store.tags.tags(of: .entity, entity.id.rawValue)
            var seen = Set([entity.id])
            coOccurring = try (details + moments).flatMap { try store.entities.links(of: $0.id).map(\.entity) }
                .filter { seen.insert($0.id).inserted && $0.type != .idea }
            if let span = try store.entities.spans(of: entity.id).first, let segment = try store.sessions.fetchSegment(span.segmentID),
               let session = try store.sessions.fetch(segment.sessionID) {
                firstTelling = (span, session)
            } else {
                firstTelling = nil
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func togglePlayback() {
        if player.isPlaying { player.stop(); return }
        guard let telling = firstTelling else { return }
        do {
            try deps.activatePlayback()
            try player.play(url: try deps.audioURL(for: telling.session), range: MsRange(start: telling.span.startMs, end: telling.span.endMs))
        } catch {
            self.error = "Could not play this: \(error.localizedDescription)"
        }
    }

    func rename(to title: String) {
        attempt("Could not rename") { try deps.extractionStore.entities.rename(entity.id, to: title) }
    }

    /// "Add dates": the person's own span, stored as said; it wins over the derived one.
    func addDates(_ range: TimeRange) {
        attempt("Could not save those dates") { try deps.extractionStore.entities.setStatedSpan(entity.id, range) }
    }

    func addTag(_ text: String) {
        attempt("Could not add that tag") { try deps.extractionStore.tags.tag(.entity, entity.id.rawValue, text) }
    }

    func removeTag(_ text: String) {
        attempt("Could not remove that tag") { try deps.extractionStore.tags.untag(.entity, entity.id.rawValue, text) }
    }

    func stop() { player.stop() }

    private func attempt(_ message: String, _ work: () throws -> Void) {
        do { try work(); refresh() } catch { self.error = "\(message): \(error.localizedDescription)" }
    }
}
