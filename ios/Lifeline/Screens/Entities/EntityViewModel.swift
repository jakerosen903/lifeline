import Foundation
import LifelineKit

/// One person, place, thing or idea (M7, S2): the person's own words for it, its life strip,
/// what was said about it, what it is often with, then its moments in order. An idea reads top
/// to bottom in date order.
@MainActor
@Observable
final class EntityViewModel {
    private(set) var entity: Entity
    /// The words the person used for it ("my sister"), when they used any.
    private(set) var ownWords: String?
    /// Nil for an idea: an idea has no strip.
    private(set) var strip: LifeStrip?
    /// The details and the mentions that are not moments ("What you've said about …").
    private(set) var said: [Memory] = []
    /// The told moments, in order.
    private(set) var moments: [Memory] = []
    /// An idea: details and moments together, oldest first (Goal 4).
    private(set) var ideaLines: [Memory] = []
    private(set) var oftenWith: [CoOccurrence] = []
    /// Only the span the person gave with "Add dates"; a derived span never shows as a line (audit F11).
    private(set) var statedSpanText: String?
    private(set) var tags: [String] = []
    private(set) var firstTelling: (span: EntitySpan, session: Session)?
    private(set) var isGone = false
    /// False until the first `refresh()`: a page reads nothing until it is on screen.
    private(set) var isLoaded = false
    /// The owner's own page ("About you"): a session from here is about "yourself".
    private(set) var isOwner = false
    private(set) var error: String?
    let player = SegmentPlayer()
    let deps: Dependencies

    init(entity: Entity, deps: Dependencies) {
        self.entity = entity
        self.deps = deps
    }

    /// "Add dates" is offered only on a place or a thing, and only as the person's own action.
    var canAddDates: Bool { entity.type == .place || entity.type == .thing }
    var isPlaying: Bool { player.isPlaying }
    /// What a session started from this page is about.
    var subject: SessionSubject { SessionSubject(entityID: entity.id, title: entity.title, isOwner: isOwner, excludedFromAI: entity.excludedFromAI) }

    func refresh() {
        defer { isLoaded = true }
        do {
            let store = deps.extractionStore
            guard let current = try store.entities.entity(id: entity.id) else { isGone = true; return }
            entity = current
            // A failed owner lookup costs only the bar's wording, never the page.
            isOwner = (try? store.profile.owner()?.entityID) == entity.id
            let details = try store.entities.details(of: entity.id)
            let mentions = try store.entities.moments(of: entity.id)
            let sections = EntityPage.sections(details: details, mentions: mentions)
            said = sections.said
            moments = sections.moments
            oftenWith = try store.entities.coOccurrences(of: entity.id)
            ownWords = try store.entities.ownWords(of: entity.id)
            // `entity.range` is set only by "Add dates", so it is the person's own span (decision 7).
            statedSpanText = entity.range.isPlaced ? EntityPage.spanText(entity.range) : nil
            if entity.type == .idea {
                let lines = (details + mentions).filter { !$0.hiddenFromTimeline }
                var told: [MemoryID: Date] = [:]
                for memory in lines {
                    if let span = try store.memories.spans(of: memory.id).first, let segment = try store.sessions.fetchSegment(span.segmentID),
                       let session = try store.sessions.fetch(segment.sessionID) { told[memory.id] = session.startedAt }
                }
                ideaLines = EntityPage.ordered(lines, toldAt: told)
                strip = nil
            } else {
                let birth = try store.profile.ownerBirthDate()
                strip = LifeStrip(moments: sections.moments.map(\.range), stated: entity.range,
                                  birthYear: birth?.year, currentYear: CivilDate.today().year)
            }
            tags = try store.tags.tags(of: .entity, entity.id.rawValue)
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
