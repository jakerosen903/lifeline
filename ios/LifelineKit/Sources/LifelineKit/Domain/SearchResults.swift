import Foundation

/// How an item matched, best first (decision 12).
public enum SearchMatch: Int, Sendable, Comparable {
    case exactTitle, titleStart, titleWords, alias, text

    public static func < (a: SearchMatch, b: SearchMatch) -> Bool { a.rawValue < b.rawValue }
}

/// What a search found, grouped by kind (decision 11). A group with no hit is empty.
public struct SearchResults: Sendable, Equatable {
    public struct EntityHit: Sendable, Equatable, Identifiable {
        public var summary: EntitySummary
        public var match: SearchMatch
        /// Set only when `match` is `.alias`: the alias that matched, as stored.
        public var matchedAlias: String?

        public init(summary: EntitySummary, match: SearchMatch, matchedAlias: String? = nil) {
            self.summary = summary; self.match = match; self.matchedAlias = matchedAlias
        }

        public var id: EntityID { summary.id }

        /// The row's second line: the matched alias, else the own words (decision 13).
        /// Only a person shows one; a place, a thing or an idea shows its title alone.
        public var secondLine: String? {
            if let matchedAlias { return matchedAlias }
            return summary.entity.type == .person ? summary.ownWords : nil
        }
    }

    public struct MemoryHit: Sendable, Equatable, Identifiable {
        public var memory: Memory
        public var match: SearchMatch
        /// The text the match was found in: the quote, or the first telling that holds every query word. Nil for a title match.
        public var matchedText: String?

        public init(memory: Memory, match: SearchMatch, matchedText: String? = nil) {
            self.memory = memory; self.match = match; self.matchedText = matchedText
        }

        public var id: MemoryID { memory.id }

        /// `MemoryLabel.heading(for:)`.
        public var heading: String { MemoryLabel.heading(for: memory) }

        /// `range.displayText` when `memory.isMoment && memory.range.isDated`. Nil for an undated or
        /// half-dated moment and for a fact, feeling or goal, whose stored range shows on no screen (M7).
        public var dateText: String? {
            memory.isMoment && memory.range.isDated ? memory.range.displayText : nil
        }
    }

    public var people: [EntityHit]
    public var places: [EntityHit]
    public var things: [EntityHit]
    public var ideas: [EntityHit]
    public var memories: [MemoryHit]

    public init(people: [EntityHit] = [], places: [EntityHit] = [], things: [EntityHit] = [], ideas: [EntityHit] = [], memories: [MemoryHit] = []) {
        self.people = people; self.places = places; self.things = things; self.ideas = ideas; self.memories = memories
    }

    public var isEmpty: Bool {
        people.isEmpty && places.isEmpty && things.isEmpty && ideas.isEmpty && memories.isEmpty
    }

    public static func heading(_ type: EntityType) -> String {
        switch type {
        case .person: "People"
        case .place: "Places"
        case .thing: "Things"
        case .idea: "What you think"
        }
    }

    public static let memoriesHeading = "Memories"
}
