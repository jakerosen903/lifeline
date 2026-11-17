import Foundation

/// What the photo card shows and offers for one photo session. The reader gathers the inputs; this file holds the rules.
public struct PhotoStoryCard: Sendable, Equatable {
    /// "The photo is dated 14 July 2019. Use that for when this happened?" for one memory.
    public struct DateOffer: Sendable, Equatable, Identifiable {
        public var memory: Memory
        public var date: CivilDate
        public var id: MemoryID { memory.id }

        public init(memory: Memory, date: CivilDate) { self.memory = memory; self.date = date }
    }

    public var photo: Photo
    /// A pending memory candidate or a pending segment in the session: more moments may still come.
    public var hasPendingMoments: Bool
    /// The memories of the session that hold the photo, in telling order.
    public var memories: [Memory]
    /// Linked to those memories, not holding the photo, not hidden from browsing. The owner first, then by title.
    public var pageOffers: [Entity]
    public var dateOffers: [DateOffer]
    public var hasOtherHome: Bool
    /// The owner's page, so a view can word that offer "Add to your page". Nil when there is no owner.
    public var ownerEntity: EntityID?

    public init(photo: Photo, hasPendingMoments: Bool, memories: [Memory], pageOffers: [Entity], dateOffers: [DateOffer], hasOtherHome: Bool,
                ownerEntity: EntityID? = nil) {
        self.photo = photo; self.hasPendingMoments = hasPendingMoments; self.memories = memories
        self.pageOffers = pageOffers; self.dateOffers = dateOffers; self.hasOtherHome = hasOtherHome; self.ownerEntity = ownerEntity
    }
}

public enum PhotoStory {
    /// True when the memory is unplaced, or `date` is before `earliest` or after `latest`. False with no date.
    /// A missing edge is unbounded, so a half-open range offers the date only when it falls on the wrong side of the edge it has.
    /// False for a date the person said or confirmed: a tap replaces the range and its evidence text, and there is no undo.
    public static func offersDate(_ date: CivilDate?, for range: TimeRange) -> Bool {
        guard let date else { return false }
        if range.origin == .stated || range.origin == .confirmed { return false }
        if range.earliest == nil && range.latest == nil { return true }
        if let earliest = range.earliest, date < earliest { return true }
        if let latest = range.latest, date > latest { return true }
        return false
    }

    /// The sentence the session's delete dialog adds, or nil. The photo goes with the session only when the session was
    /// its last home. A memory that came only from this session is deleted with it, so the card already ignores it.
    public static func deleteSentence(card: PhotoStoryCard?) -> String? {
        guard let card, !card.hasOtherHome else { return nil }
        return "Its photo goes too."
    }

    /// - Parameters:
    ///   - sessionMemories: the session's memories in telling order.
    ///   - holding: the ones that hold the photo.
    ///   - linked: the entities each memory names, of every type.
    ///   - pagesWithPhoto: the entities that already hold the photo.
    public static func card(photo: Photo, sessionMemories: [Memory], holding: Set<MemoryID>, linked: [MemoryID: [Entity]],
                            pagesWithPhoto: Set<EntityID>, ownerEntity: EntityID?, hasPendingMoments: Bool, hasOtherHome: Bool) -> PhotoStoryCard {
        let memories = sessionMemories.filter { holding.contains($0.id) }
        var seen = Set<EntityID>()
        let offers = memories.flatMap { linked[$0.id] ?? [] }.filter { entity in
            !entity.hiddenFromTimeline && !pagesWithPhoto.contains(entity.id) && seen.insert(entity.id).inserted
        }.sorted { a, b in
            if (a.id == ownerEntity) != (b.id == ownerEntity) { return a.id == ownerEntity }
            let byTitle = a.title.localizedCaseInsensitiveCompare(b.title)
            return byTitle == .orderedSame ? a.id.rawValue < b.id.rawValue : byTitle == .orderedAscending
        }
        let date = photo.takenAt?.date
        let dateOffers = memories.filter { offersDate(date, for: $0.range) }.compactMap { memory in
            date.map { PhotoStoryCard.DateOffer(memory: memory, date: $0) }
        }
        return PhotoStoryCard(photo: photo, hasPendingMoments: hasPendingMoments, memories: memories, pageOffers: offers,
                              dateOffers: dateOffers, hasOtherHome: hasOtherHome, ownerEntity: ownerEntity)
    }
}
