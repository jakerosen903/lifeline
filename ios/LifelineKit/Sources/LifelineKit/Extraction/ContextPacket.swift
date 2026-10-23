import Foundation

/// What the extractor is told besides the segment. Built on device; selects, never dumps.
public struct ContextPacket: Codable, Sendable, Equatable {
    public struct PersonEntry: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var aliases: [String]
    }

    public struct MemoryEntry: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var rangeText: String?
    }

    public struct ChapterEntry: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var rangeText: String?
    }

    public var previousSegments: [String]
    public var people: [PersonEntry]
    public var chapters: [ChapterEntry]
    public var memories: [MemoryEntry]
    public var curiosity: [String]
    public var stage: String
    public var profileFreeText: String?

    /// Sorted keys, so the same packet always renders to the same bytes.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return try encoder.encode(self)
    }
}

public struct ContextPacketLimits: Sendable, Equatable {
    public var previousSegments: Int
    public var people: Int
    public var curiosity: Int

    public init(previousSegments: Int = 2, people: Int = 50, curiosity: Int = 10) {
        self.previousSegments = previousSegments; self.people = people; self.curiosity = curiosity
    }
}

/// Pure. Chapters and curiosity items are empty until M3 builds them.
public enum ContextPacketBuilder {
    public static func build(segment: Segment, previous: [Segment], people: [(Person, [Alias])], memories: [Memory],
                             profileFreeText: String?, stage: String, limits: ContextPacketLimits = ContextPacketLimits(),
                             chapters: [Chapter] = [], curiosity: [CuriosityItem] = [], excludedMemoryIDs: Set<MemoryID> = []) -> ContextPacket {
        let earlier = previous.filter { $0.index < segment.index }.sorted { $0.index < $1.index }
        let window = earlier.suffix(limits.previousSegments).map(\.text)
        let entries = people
            .filter { !$0.0.isOwner }
            .prefix(limits.people)
            .map { person, aliases in
                ContextPacket.PersonEntry(id: person.id.rawValue, name: person.displayName,
                                          aliases: aliases.map(\.text).filter { $0.caseInsensitiveCompare(person.displayName) != .orderedSame })
            }
        let memoryEntries = memories.filter { !$0.excludedFromAI }.map { ContextPacket.MemoryEntry(id: $0.id.rawValue, title: $0.title, rangeText: $0.range.isPlaced ? $0.range.displayText : nil) }
        let chapterEntries = chapters.map {
            ContextPacket.ChapterEntry(id: $0.id.rawValue, title: $0.title ?? "untitled", rangeText: $0.range.isPlaced ? $0.range.displayText : nil)
        }
        // Exclude from AI covers what was built from the memory, not only the memory's own entry.
        let questions = curiosity
            .filter { item in ![item.sourceMemoryID, item.targetMemoryID].compactMap { $0 }.contains { excludedMemoryIDs.contains($0) } }
            .prefix(limits.curiosity).map(\.text)
        return ContextPacket(previousSegments: Array(window), people: Array(entries), chapters: chapterEntries, memories: memoryEntries,
                             curiosity: Array(questions), stage: stage, profileFreeText: profileFreeText)
    }
}

extension ExtractorPrompt {
    /// The per-segment message: numbered words so spans are unambiguous, the packet, the text.
    public static func userMessage(segmentText: String, words: [String], packet: ContextPacket) throws -> String {
        let numbered = words.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: " ")
        let packetJSON = String(decoding: try packet.encodedJSON(), as: UTF8.self)
        return """
        Context packet:
        \(packetJSON)

        Segment words (index:word):
        \(numbered)

        Segment text:
        \(segmentText)
        """
    }
}
