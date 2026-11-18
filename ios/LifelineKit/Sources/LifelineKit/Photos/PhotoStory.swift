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

    /// One page the photo can go on, or is on.
    public struct Page: Sendable, Equatable, Identifiable {
        public var entity: Entity
        /// The page holds the photo.
        public var isChosen: Bool
        public var isOwner: Bool
        public var id: EntityID { entity.id }
        public var title: String { isOwner ? "You" : entity.title }
        public var stateValue: String { isChosen ? "added" : "not added" }
    }

    /// The pages of one entity type.
    public struct PageGroup: Sendable, Equatable, Identifiable {
        public var type: EntityType
        /// Never empty. The owner first, then by title, then by id.
        public var pages: [Page]
        public var id: EntityType { type }
        public var title: String { type.screenTitle }
    }

    /// The one date offer for the story: the photo's day, and the memories that can take it.
    public struct StoryDateOffer: Sendable, Equatable {
        public var date: CivilDate
        /// In telling order. Never empty.
        public var memories: [Memory]
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
    /// In the order person, place, thing, idea. A group with no page is left out.
    public var pageGroups: [PageGroup]
    public var dateOffer: StoryDateOffer?

    public init(photo: Photo, hasPendingMoments: Bool, memories: [Memory], pageOffers: [Entity], dateOffers: [DateOffer], hasOtherHome: Bool,
                ownerEntity: EntityID? = nil, pageGroups: [PageGroup] = [], dateOffer: StoryDateOffer? = nil) {
        self.photo = photo; self.hasPendingMoments = hasPendingMoments; self.memories = memories
        self.pageOffers = pageOffers; self.dateOffers = dateOffers; self.hasOtherHome = hasOtherHome; self.ownerEntity = ownerEntity
        self.pageGroups = pageGroups; self.dateOffer = dateOffer
    }

    /// "This photo goes on each moment you keep." while a moment waits; "On 1 moment from this story"; "On {n} moments from this
    /// story"; nil with nothing to say.
    public var momentsLine: String? {
        if hasPendingMoments { return "This photo goes on each moment you keep." }
        switch memories.count {
        case 0: return nil
        case 1: return "On 1 moment from this story"
        default: return "On \(memories.count) moments from this story"
        }
    }

    /// False while a moment waits, and with no line.
    public var momentsLineOpens: Bool { !hasPendingMoments && !memories.isEmpty }
}

public enum PhotoStory {
    /// True when the photo has a date and the range's origin is not `stated`, `confirmed` or `photo`. An unplaced range and a
    /// guess (`inferred`, `derived`) can take the date, wherever the date falls. A tap replaces the range and its evidence text,
    /// so a date the person said stays theirs; a date from a photo changes on the memory's page.
    public static func offersDate(_ date: CivilDate?, for range: TimeRange) -> Bool {
        guard date != nil else { return false }
        return ![RangeOrigin.stated, .confirmed, .photo].contains(range.origin)
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
    ///   - pagesWithPhoto: the entities that already hold the photo, named by a memory or not.
    public static func card(photo: Photo, sessionMemories: [Memory], holding: Set<MemoryID>, linked: [MemoryID: [Entity]],
                            pagesWithPhoto: [Entity], ownerEntity: EntityID?, hasPendingMoments: Bool, hasOtherHome: Bool) -> PhotoStoryCard {
        let memories = sessionMemories.filter { holding.contains($0.id) }
        let holders = Set(pagesWithPhoto.map(\.id))
        let named = memories.flatMap { linked[$0.id] ?? [] }
        var seen = Set<EntityID>()
        let offers = named.filter { entity in
            !entity.hiddenFromTimeline && !holders.contains(entity.id) && seen.insert(entity.id).inserted
        }.sorted { inListOrder($0, $1, owner: ownerEntity) }
        let date = photo.takenAt?.date
        let dateOffers = memories.filter { offersDate(date, for: $0.range) }.compactMap { memory in
            date.map { PhotoStoryCard.DateOffer(memory: memory, date: $0) }
        }
        var listed = Set<EntityID>()
        let pages = (named + pagesWithPhoto).filter { !$0.hiddenFromTimeline && listed.insert($0.id).inserted }
        let groups = EntityType.allCases.compactMap { type -> PhotoStoryCard.PageGroup? in
            let ofType = pages.filter { $0.type == type }.sorted { inListOrder($0, $1, owner: ownerEntity) }
            return ofType.isEmpty ? nil : PhotoStoryCard.PageGroup(type: type, pages: ofType.map {
                PhotoStoryCard.Page(entity: $0, isChosen: holders.contains($0.id), isOwner: $0.id == ownerEntity)
            })
        }
        let canTakeDate = date.map { day in
            (day, memories.filter { offersDate(day, for: $0.range) })
        }
        let storyOffer = canTakeDate.flatMap { day, takers in
            takers.isEmpty ? nil : PhotoStoryCard.StoryDateOffer(date: day, memories: takers)
        }
        return PhotoStoryCard(photo: photo, hasPendingMoments: hasPendingMoments, memories: memories, pageOffers: offers,
                              dateOffers: dateOffers, hasOtherHome: hasOtherHome, ownerEntity: ownerEntity,
                              pageGroups: groups, dateOffer: storyOffer)
    }

    /// The owner first, then by title, then by id.
    private static func inListOrder(_ a: Entity, _ b: Entity, owner: EntityID?) -> Bool {
        if (a.id == owner) != (b.id == owner) { return a.id == owner }
        let byTitle = a.title.localizedCaseInsensitiveCompare(b.title)
        return byTitle == .orderedSame ? a.id.rawValue < b.id.rawValue : byTitle == .orderedAscending
    }
}
