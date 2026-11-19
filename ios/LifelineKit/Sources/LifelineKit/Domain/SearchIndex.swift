import Foundation

/// Everything search reads, in memory. Built by `ExtractionStore.searchIndex()` (Task 4) or by a test.
/// It holds no hidden row: the builder leaves those out, and `Search.run` does not filter again.
/// Each entry folds its words once, when it is made (off the main actor), so a keystroke folds only the query.
/// The entries are immutable, so their folded words always match their text.
public struct SearchIndex: Sendable, Equatable {
    public struct EntityEntry: Sendable, Equatable {
        public let summary: EntitySummary
        /// A person's other names. Empty for a place, a thing or an idea.
        public let aliases: [String]
        /// `SearchFold.words` of the title.
        public let titleWords: [String]
        /// `SearchFold.words` of each alias, in the order of `aliases`.
        public let aliasWords: [[String]]

        public init(summary: EntitySummary, aliases: [String] = []) {
            self.summary = summary; self.aliases = aliases
            titleWords = SearchFold.words(summary.entity.title)
            aliasWords = aliases.map(SearchFold.words)
        }
    }

    public struct MemoryEntry: Sendable, Equatable {
        public let memory: Memory
        /// The words of each telling, as said, first telling first. Empty when the store has no word rows.
        public let tellings: [String]
        /// The session's `started_at` of the first telling, for life order with no date.
        public let toldAt: Date?
        /// `SearchFold.words` of a moment's title. Empty for a fact, a feeling or a goal:
        /// its stored title is one the person never said, so it is not searched.
        public let titleWords: [String]
        /// `SearchFold.words` of each of `texts`, in the same order.
        public let textWords: [[String]]

        public init(memory: Memory, tellings: [String] = [], toldAt: Date? = nil) {
            self.memory = memory; self.tellings = tellings; self.toldAt = toldAt
            titleWords = memory.isMoment ? SearchFold.words(memory.title) : []
            textWords = ([memory.summaryQuote] + tellings).map(SearchFold.words)
        }

        /// The person's words that search reads: the quote first, then each telling.
        public var texts: [String] { [memory.summaryQuote] + tellings }
    }

    public var entities: [EntityEntry]
    public var memories: [MemoryEntry]

    public init(entities: [EntityEntry] = [], memories: [MemoryEntry] = []) {
        self.entities = entities; self.memories = memories
    }

    public static let empty = SearchIndex()
}
