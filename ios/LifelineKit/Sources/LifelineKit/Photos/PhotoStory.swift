import Foundation

/// What the photo card shows and offers for one photo session. The reader gathers the inputs; this file holds the rules.
public struct PhotoStoryCard: Sendable, Equatable {
    /// One page the photo can go on, or is on.
    public struct Page: Sendable, Equatable, Identifiable {
        public var entity: Entity
        /// The page holds the photo.
        public var isChosen: Bool
        public var isOwner: Bool
        /// The page holds the photo through a link a photo story made, not one the owner made.
        public var byStory: Bool = false
        public var id: EntityID { entity.id }
        public var title: String { isOwner ? "You" : entity.title }
        public var stateValue: String { byStory ? "added by this story" : isChosen ? "added" : "not added" }
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
    public var hasOtherHome: Bool
    /// The pages the kept memories name and the pages that hold the photo, not hidden from browsing, each once.
    /// In the order person, place, thing, idea. A group with no page is left out.
    public var pageGroups: [PageGroup]
    /// Nil when the photo has no date or no moment that holds it can take the date. A fact, a feeling or a goal never takes it.
    public var dateOffer: StoryDateOffer?
    /// The owner tapped "Done" on the pages part of this story: it shows only the chosen pages. A new story starts open.
    public var pagesDone: Bool

    public init(photo: Photo, hasPendingMoments: Bool, memories: [Memory], hasOtherHome: Bool, pageGroups: [PageGroup] = [],
                dateOffer: StoryDateOffer? = nil, pagesDone: Bool = false) {
        self.photo = photo; self.hasPendingMoments = hasPendingMoments; self.memories = memories; self.hasOtherHome = hasOtherHome
        self.pageGroups = pageGroups; self.dateOffer = dateOffer; self.pagesDone = pagesDone
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

    /// The line under "Also show this photo on": it names the story's choice while a page holds the photo through a story link.
    public var pagesLine: String {
        pageGroups.contains { $0.pages.contains(where: \.byStory) } ? Self.storyPagesLine : Self.tapPagesLine
    }

    static let storyPagesLine = "The people in this story have this photo on their pages. Tap to take it off, or to add it to another page."
    static let tapPagesLine = "Tap to add. Tap again to take it off."
    /// Every line `pagesLine` can be. The open part reserves the height of the tallest, so a chip does not move under the
    /// finger when the line changes.
    public static let allPagesLines = [storyPagesLine, tapPagesLine]

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
    ///   - storyPages: the entities whose link to the photo a story made. An id that is not in `pagesWithPhoto` is ignored.
    ///   - pagesDone: the owner tapped "Done" on the pages part of this story.
    public static func card(photo: Photo, sessionMemories: [Memory], holding: Set<MemoryID>, linked: [MemoryID: [Entity]],
                            pagesWithPhoto: [Entity], ownerEntity: EntityID?, storyPages: Set<EntityID> = [], hasPendingMoments: Bool,
                            hasOtherHome: Bool, pagesDone: Bool = false) -> PhotoStoryCard {
        let memories = sessionMemories.filter { holding.contains($0.id) }
        let holders = Set(pagesWithPhoto.map(\.id))
        let named = memories.flatMap { linked[$0.id] ?? [] }
        let date = photo.takenAt?.date
        var listed = Set<EntityID>()
        let pages = (named + pagesWithPhoto).filter { !$0.hiddenFromTimeline && listed.insert($0.id).inserted }
        let groups = EntityType.allCases.compactMap { type -> PhotoStoryCard.PageGroup? in
            let ofType = pages.filter { $0.type == type }.sorted { inListOrder($0, $1, owner: ownerEntity) }
            return ofType.isEmpty ? nil : PhotoStoryCard.PageGroup(type: type, pages: ofType.map {
                PhotoStoryCard.Page(entity: $0, isChosen: holders.contains($0.id), isOwner: $0.id == ownerEntity,
                                    byStory: holders.contains($0.id) && storyPages.contains($0.id))
            })
        }
        // Only a moment takes the photo's date: a fact, a feeling or a goal shows no date on its page, so a date written
        // there could not be seen or changed.
        let canTakeDate = date.map { day in
            (day, memories.filter { $0.isMoment && offersDate(day, for: $0.range) })
        }
        let storyOffer = canTakeDate.flatMap { day, takers in
            takers.isEmpty ? nil : PhotoStoryCard.StoryDateOffer(date: day, memories: takers)
        }
        return PhotoStoryCard(photo: photo, hasPendingMoments: hasPendingMoments, memories: memories, hasOtherHome: hasOtherHome,
                              pageGroups: groups, dateOffer: storyOffer, pagesDone: pagesDone)
    }

    /// The owner first, then by title, then by id.
    private static func inListOrder(_ a: Entity, _ b: Entity, owner: EntityID?) -> Bool {
        inListOrder(a, isOwner: a.id == owner, b, isOwner: b.id == owner)
    }

    /// The one order of a group's chips, for the card and for a kept page put back (`shownPageGroups(keeping:)`).
    static func inListOrder(_ a: Entity, isOwner aIsOwner: Bool, _ b: Entity, isOwner bIsOwner: Bool) -> Bool {
        if aIsOwner != bIsOwner { return aIsOwner }
        let byTitle = a.title.localizedCaseInsensitiveCompare(b.title)
        return byTitle == .orderedSame ? a.id.rawValue < b.id.rawValue : byTitle == .orderedAscending
    }
}

// MARK: - Done and Edit (spec part 3)

extension PhotoStoryCard {
    /// The button under the chips while the part is open.
    public static let doneTitle = "Done"
    /// The button under the chips while the part is done.
    public static let editTitle = "Edit"
    /// Done with no page to show.
    public static let noOtherPageSentence = "This photo is on no other page."

    /// The line under the heading: `pagesLine` while the part is open, nil while it is done.
    public var shownPagesLine: String? { pagesDone ? nil : pagesLine }

    /// What the pages part shows. `kept`: the pages the owner emptied while the part is done, as the card showed them at the
    /// tap; they stay on screen. Open: every group. Done: the chosen pages and the kept ones. A kept page the card no longer
    /// lists (it was listed only because it held the photo) comes back empty, in its group and in the card's order, so its
    /// place does not change between reads. A group left with no page goes.
    public func shownPageGroups(keeping kept: [Page]) -> [PageGroup] {
        guard pagesDone else { return pageGroups }
        let keptIDs = Set(kept.map(\.id))
        let listed = Set(pageGroups.flatMap { $0.pages.map(\.id) })
        var missing: [EntityID: Page] = [:]
        for page in kept where !listed.contains(page.id) {
            missing[page.id] = Page(entity: page.entity, isChosen: false, isOwner: page.isOwner, byStory: false)
        }
        return EntityType.allCases.compactMap { type in
            let fromCard = pageGroups.first { $0.type == type }?.pages.filter { $0.isChosen || keptIDs.contains($0.id) } ?? []
            let shown = (fromCard + missing.values.filter { $0.entity.type == type })
                .sorted { PhotoStory.inListOrder($0.entity, isOwner: $0.isOwner, $1.entity, isOwner: $1.isOwner) }
            return shown.isEmpty ? nil : PageGroup(type: type, pages: shown)
        }
    }

    /// The card draws the pages part (chips, line or sentence, Done or Edit). A kept page counts: when it was the card's
    /// only page, the part must stay so its chip does not disappear under the finger.
    public func showsPagesPart(keeping kept: [Page]) -> Bool {
        !pageGroups.isEmpty || !shownPageGroups(keeping: kept).isEmpty
    }

    /// Done, and no page is chosen or kept. A function, not a property: the kept pages live in the view model.
    public func showsNoOtherPageSentence(keeping kept: [Page]) -> Bool {
        pagesDone && shownPageGroups(keeping: kept).isEmpty
    }
}
