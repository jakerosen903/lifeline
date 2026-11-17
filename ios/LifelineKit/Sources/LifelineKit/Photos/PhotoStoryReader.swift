import Foundation

/// Gathers what `PhotoStory.card` needs from the store, and applies the two taps the card offers.
public struct PhotoStoryReader: Sendable {
    private let store: ExtractionStore

    public init(store: ExtractionStore) { self.store = store }

    /// Nil when the session has no subject photo.
    public func card(for session: SessionID) throws -> PhotoStoryCard? {
        guard let photo = try store.photos.subjectPhoto(of: session) else { return nil }
        let memories = try store.memories.memories(in: session)
        var holding = Set<MemoryID>()
        var linked: [MemoryID: [Entity]] = [:]
        var pagesWithPhoto = Set<EntityID>()
        for memory in memories {
            if try store.photos.isLinked(photo.id, to: .memory(memory.id)) {
                holding.insert(memory.id)
                let entities = try store.entities.links(of: memory.id).map(\.entity)
                linked[memory.id] = entities
                for entity in entities where try store.photos.isLinked(photo.id, to: .entity(entity.id)) { pagesWithPhoto.insert(entity.id) }
            }
        }
        let pendingCards = try store.candidates.pending(in: session).contains { $0.kind == .memory }
        let pendingSegments = try !store.sessions.segments(in: session, status: .pending).isEmpty
        return PhotoStory.card(photo: photo, sessionMemories: memories, holding: holding, linked: linked, pagesWithPhoto: pagesWithPhoto,
                               ownerEntity: try store.profile.owner()?.entityID, hasPendingMoments: pendingCards || pendingSegments,
                               hasOtherHome: try store.photos.hasOtherHome(photo.id, than: session))
    }

    /// The first photo on a page is its cover (the S4 rule, in `PhotoRepository.link`).
    public func addToPage(_ photo: PhotoID, _ entity: EntityID) throws {
        try store.photos.link(photo, to: .entity(entity))
    }

    /// The memory takes the photo's day. `updateRange` does not move a chapter's range, so the memory's chapter follows here.
    public func useDate(_ offer: PhotoStoryCard.DateOffer) throws {
        try store.memories.updateRange(offer.memory.id, .fromPhoto(offer.date))
        guard let chapter = try store.memories.fetch(offer.memory.id)?.chapterID else { return }
        try store.chapters.setRange(chapter, ChapterRepository.span(over: try store.memories.moments(inChapter: chapter).map(\.range)))
    }
}
