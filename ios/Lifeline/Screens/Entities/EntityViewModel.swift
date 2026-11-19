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
    /// The page closes when the entity is gone and no notice is still offering Undo or its reason.
    /// A move that removed this person keeps the page up, read-only, until its notice ends (R34).
    var shouldClose: Bool { isGone && personMove.text == nil }
    /// False until the first `refresh()`: a page reads nothing until it is on screen.
    private(set) var isLoaded = false
    /// The owner's own page ("About you"): a session from here is about "yourself".
    private(set) var isOwner = false
    /// The name the interviewer's model may hear for this page (`NameForModel`). A person's is read in
    /// `refresh()`; until then nil, so a session started early opens plainly and names no contact.
    private(set) var modelTitle: String?
    private(set) var error: String?
    /// Why the last photo action failed, for the pinned slot (decision 21). Cleared when the next one starts.
    private(set) var photoError: String?
    /// The page's photos (S4): the cover heads the page, two or more sit in a row.
    let shelf: PhotoShelf
    /// A person's moments that are here by a guess, keyed by memory. Empty on any other page and on the owner's.
    /// A memory with a guessed mention and a guessed detail shows the mention link.
    private(set) var guessed: [MemoryID: PersonLink] = [:]
    /// What each guessed moment's "New" line says about the contacts, worked out with `guessed` (PB1).
    private(set) var contactsSeen: [MemoryID: PersonChipLine.ContactsSeen] = [:]
    /// "Changed to {name}." with Undo, after the sheet moved a moment off this page.
    let personMove: PersonMoveUndo
    /// The contact row (PC3, PC4); it shows nothing on the owner's page or a page that is not a person's.
    let contact: PersonContactViewModel
    let player = SegmentPlayer()
    let deps: Dependencies

    init(entity: Entity, deps: Dependencies) {
        self.entity = entity
        self.deps = deps
        personMove = PersonMoveUndo(actions: deps.personLinkActions())
        contact = PersonContactViewModel(entity: entity, deps: deps)
        // The shelf reports to this page, which exists only once the shelf is stored: the closure is bound after.
        var report: (String) -> Void = { _ in }
        self.shelf = PhotoShelf(subject: .entity(entity.id), deps: deps, onError: { report($0) })
        report = { [weak self] in self?.photoError = $0 }
        contact.onChanged = { [weak self] in self?.refresh() }
    }

    /// True while the first picture is the copy the app took from the contact: it says "picture from your contacts".
    var coverIsFromContacts: Bool {
        guard let copy = contact.contactPhotoID else { return false }
        return shelf.cover?.id == copy
    }

    /// "Photo of Maya", or "Photo of you" on the owner's page (decision 19).
    var photoLabel: String { PhotoCaption.label(title: entity.title, isOwner: isOwner, isMemory: false) }

    /// "Add dates" is offered only on a place or a thing, and only as the person's own action.
    var canAddDates: Bool { entity.type == .place || entity.type == .thing }
    var isPlaying: Bool { player.isPlaying }
    /// What a session started from this page is about.
    var subject: SessionSubject {
        SessionSubject(entityID: entity.id, title: entity.title, isOwner: isOwner, excludedFromAI: entity.excludedFromAI,
                       modelTitle: entity.type == .person ? modelTitle : entity.title)
    }

    func refresh() {
        defer { isLoaded = true }
        do {
            let store = deps.extractionStore
            guard let current = try store.entities.entity(id: entity.id) else { isGone = true; return }
            // An Undo that restored the person brings the page back.
            isGone = false
            entity = current
            // A failed owner lookup costs only the bar's wording, never the page.
            isOwner = (try? store.profile.owner()?.entityID) == entity.id
            // A failed read leaves no name for the model: the opening is the plain one (PB10).
            modelTitle = entity.type == .person ? (try? store.people.nameForModel(of: PersonID(rawValue: entity.id.rawValue))) ?? nil : nil
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
            guessed = isOwner || entity.type != .person ? [:] : PersonLink.guesses(among: try store.personLinks.links(to: PersonID(rawValue: entity.id.rawValue)))
            contactsSeen = Self.contactsSeen(for: guessed, deps: deps)
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
        contact.refresh()
        shelf.load()
    }

    // MARK: - Guessed moments

    /// Only a `new` link's line names the contacts; the held identifiers are read only when there is one.
    private static func contactsSeen(for guessed: [MemoryID: PersonLink], deps: Dependencies) -> [MemoryID: PersonChipLine.ContactsSeen] {
        let fresh = guessed.filter { $0.value.origin == .new }
        guard !fresh.isEmpty else { return [:] }
        let held = deps.heldContactIdentifiers()
        return fresh.mapValues { deps.contactsSeen(saidName: $0.saidName, held: held) }
    }

    /// "Yes, this {name}": settles that one link. The mark goes at once; there is no notice.
    func confirm(_ memory: MemoryID) {
        guard let link = guessed[memory] else { return }
        do {
            try deps.personLinkActions().settle(link, wholeGroup: false)
            refresh()
        } catch {
            self.error = "Could not save that: \(error.localizedDescription)"
        }
    }

    /// What "Done" in the sheet did. A move shows its notice; the page then reads again, and stays up,
    /// read-only, when the move removed this person (`shouldClose`, R34).
    func personSheetDone(_ outcome: WhoIsThisViewModel.Outcome) {
        if case .unchanged = outcome { return }
        if case .failed(let message) = outcome { error = message; return }
        personMove.note(outcome)
        refresh()
    }

    /// Returns true when the move was taken back.
    func undoPersonMove() -> Bool {
        let done = personMove.undo()
        if done { refresh() }
        return done
    }

    // MARK: - Photos

    func addPhoto(fileAt file: URL, assetLocalID: String?) async {
        photoError = nil
        await shelf.add(fileAt: file, assetLocalID: assetLocalID)
    }

    func makeCover(_ photo: PhotoID) async {
        photoError = nil
        await shelf.makeCover(photo)
    }

    func removePhoto(_ photo: PhotoID) async {
        photoError = nil
        await shelf.remove(photo)
    }

    /// A picked photo that never reached the shelf (the picker could not hand it over).
    func photoFailed(_ message: String) { photoError = message }

    func clearPhotoError() { photoError = nil }

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
