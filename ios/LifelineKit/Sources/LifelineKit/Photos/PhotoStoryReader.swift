import Foundation

/// Gathers what `PhotoStory.card` needs from the store, and applies the card's taps: a page, the date and its Undo.
public struct PhotoStoryReader: Sendable {
    private let store: ExtractionStore

    public init(store: ExtractionStore) { self.store = store }

    /// Nil when the session has no subject photo.
    public func card(for session: SessionID) throws -> PhotoStoryCard? {
        guard let photo = try store.photos.subjectPhoto(of: session) else { return nil }
        // Any telling counts: a telling merged into an older memory put the photo there too.
        let memories = try store.memories.memories(toldIn: session)
        let held = try store.photos.subjects(of: photo.id)
        let holding = Set(memories.map(\.id)).intersection(held.memories)
        var linked: [MemoryID: [Entity]] = [:]
        for id in holding { linked[id] = try store.entities.links(of: id).map(\.entity) }
        let pagesWithPhoto = try held.entities.compactMap { try store.entities.entity(id: $0) }
        let pendingCards = try store.candidates.pending(in: session).contains { $0.kind == .memory }
        let pendingSegments = try !store.sessions.segments(in: session, status: .pending).isEmpty
        return PhotoStory.card(photo: photo, sessionMemories: memories, holding: holding, linked: linked, pagesWithPhoto: pagesWithPhoto,
                               ownerEntity: try store.profile.owner()?.entityID,
                               storyPages: try store.photos.storyPages(of: photo.id), hasPendingMoments: pendingCards || pendingSegments,
                               hasOtherHome: try store.photos.hasOtherHome(photo.id, than: session),
                               pagesDone: try store.sessions.fetch(session)?.photoPagesDone ?? false)
    }

    /// "Done" (true) or "Edit" (false) on the pages part of the session's photo story. Stored for the story.
    public func setPagesDone(_ done: Bool, for session: SessionID) throws {
        try store.sessions.setPhotoPagesDone(session, done)
    }

    /// The first photo on a page is its cover (the S4 rule, in `PhotoRepository.link`).
    public func addToPage(_ photo: PhotoID, _ entity: EntityID) throws {
        try store.photos.link(photo, to: .entity(entity))
    }

    /// Sets each memory to `.fromPhoto(date)` in one write, checked against the range each `Memory` value carries. A memory whose
    /// range changed since the value was read is left alone. The resolver then runs one time, so a memory placed relative to
    /// a changed one is placed again at once; it leaves a settled date alone. Returns one change for each memory it wrote.
    public func useDate(_ date: CivilDate, for memories: [Memory]) throws -> [PhotoDateChange] {
        let changes = memories.map { MemoryRepository.RangeChange(memory: $0.id, range: .fromPhoto(date), ifCurrently: $0.range) }
        let written = Set(try store.memories.updateRanges(changes))
        guard !written.isEmpty else { return [] }
        _ = try ResolverRunner(store: store).run()
        return memories.filter { written.contains($0.id) }.map { PhotoDateChange(memory: $0.id, before: $0.range, date: date) }
    }

    /// Puts back each `before` in one write, only where the stored range is still `.fromPhoto(change.date)`: a date the person
    /// set after the tap stays. The resolver then runs one time. A guess with an anchor comes back the same; a guess that
    /// nothing supports becomes unplaced, as in every resolver run. Returns the memories it put back.
    @discardableResult
    public func undoDate(_ changes: [PhotoDateChange]) throws -> [MemoryID] {
        let back = changes.map { MemoryRepository.RangeChange(memory: $0.memory, range: $0.before, ifCurrently: .fromPhoto($0.date)) }
        let restored = try store.memories.updateRanges(back)
        if !restored.isEmpty { _ = try ResolverRunner(store: store).run() }
        return restored
    }
}
