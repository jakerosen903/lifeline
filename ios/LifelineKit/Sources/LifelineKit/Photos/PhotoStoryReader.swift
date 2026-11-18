import Foundation

/// Gathers what `PhotoStory.card` needs from the store, and applies the two taps the card offers.
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
        let pagesWithPhoto = held.entities
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

    /// The memory takes the photo's day, and its chapter follows in the same write. The resolver then runs, so a memory
    /// placed relative to this one is placed again at once; it leaves a settled date alone.
    /// A memory whose range changed since the card was drawn is left alone: the offer was made against the older range.
    public func useDate(_ offer: PhotoStoryCard.DateOffer) throws {
        guard try store.memories.updateRange(offer.memory.id, .fromPhoto(offer.date), ifCurrently: offer.memory.range, refreshingChapter: true) else { return }
        _ = try ResolverRunner(store: store).run()
    }
}
