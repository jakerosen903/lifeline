import Foundation

/// Everything search reads, in memory. Built by `ExtractionStore.searchIndex()` (Task 4) or by a test.
/// It holds no hidden row: the builder leaves those out, and `Search.run` does not filter again.
public struct SearchIndex: Sendable, Equatable {
    public struct EntityEntry: Sendable, Equatable {
        public var summary: EntitySummary
        /// A person's other names. Empty for a place, a thing or an idea.
        public var aliases: [String]

        public init(summary: EntitySummary, aliases: [String] = []) {
            self.summary = summary; self.aliases = aliases
        }
    }

    public struct MemoryEntry: Sendable, Equatable {
        public var memory: Memory
        /// The words of each telling, as said, first telling first. Empty when the store has no word rows.
        public var tellings: [String]
        /// The session's `started_at` of the first telling, for life order with no date.
        public var toldAt: Date?

        public init(memory: Memory, tellings: [String] = [], toldAt: Date? = nil) {
            self.memory = memory; self.tellings = tellings; self.toldAt = toldAt
        }
    }

    public var entities: [EntityEntry]
    public var memories: [MemoryEntry]

    public init(entities: [EntityEntry] = [], memories: [MemoryEntry] = []) {
        self.entities = entities; self.memories = memories
    }

    public static let empty = SearchIndex()
}
