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
        /// True for an earlier memory retrieved because it reads like this segment (M4.1);
        /// nil, and absent from the JSON, for this session's own memories.
        public var related: Bool?

        public init(id: String, title: String, rangeText: String?, related: Bool? = nil) {
            self.id = id; self.title = title; self.rangeText = rangeText; self.related = related
        }
    }

    public struct ChapterEntry: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var rangeText: String?
    }

    /// A card of this session still waiting on the person, so a continuation can name it (M5).
    public struct PendingEntry: Codable, Sendable, Equatable {
        public var candidateID: String
        public var title: String
        public var quote: String
        public var storyRef: String?

        public init(candidateID: String, title: String, quote: String, storyRef: String?) {
            self.candidateID = candidateID; self.title = title; self.quote = quote; self.storyRef = storyRef
        }
    }

    /// A story the packet's memories belong to (M5).
    public struct StoryEntry: Codable, Sendable, Equatable {
        public var id: String
        public var title: String?
        public var momentTitles: [String]

        public init(id: String, title: String?, momentTitles: [String]) { self.id = id; self.title = title; self.momentTitles = momentTitles }
    }

    /// A place, thing or idea on file, with one line of detail in the person's words (M7).
    public struct EntityEntry: Codable, Sendable, Equatable {
        public var id: String
        public var type: String
        public var title: String
        public var detail: String?

        public init(id: String, type: String, title: String, detail: String?) { self.id = id; self.type = type; self.title = title; self.detail = detail }
    }

    /// One person found so far in this recording, under the handle the extractor gave them (PC-d).
    /// Only what the owner said: the said names, the relation phrase, and the id of a person
    /// this packet already lists. Nothing from a contact.
    public struct RecordingPerson: Codable, Sendable, Equatable {
        public var handle: String
        /// Each distinct name said for this handle, in the order said.
        public var saidNames: [String]
        /// The first relation phrase given.
        public var relation: String?
        /// The first person id given, sent only when the packet's `people` holds it.
        public var personID: String?

        public init(handle: String, saidNames: [String], relation: String?, personID: String?) {
            self.handle = handle; self.saidNames = saidNames; self.relation = relation; self.personID = personID
        }
    }

    public var previousSegments: [String]
    public var people: [PersonEntry]
    public var chapters: [ChapterEntry]
    public var memories: [MemoryEntry]
    public var curiosity: [String]
    public var stage: String
    public var profileFreeText: String?
    public var pending: [PendingEntry] = []
    public var stories: [StoryEntry] = []
    public var entities: [EntityEntry] = []
    public var recordingPeople: [RecordingPerson] = []

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

/// Pure. Fills the packet in relevance order and trims it to a token ceiling (M5): previous
/// segments, pending cards, related and session memories, the recording's handles (PC-d), people (pass them already ordered),
/// entities (M7), stories, chapters, curiosity. Whole entries go, least relevant section first, and every
/// section keeps its first entry. Profile free text is never dropped.
public enum ContextPacketBuilder {
    public static let defaultBudgetTokens = 6000

    /// `people` carry their aliases oldest first (`PeopleRepository.aliasesOldestFirst`).
    public static func build(segment: Segment, previous: [Segment], people: [(Person, [Alias])], memories: [Memory],
                             profileFreeText: String?, stage: String, limits: ContextPacketLimits = ContextPacketLimits(),
                             chapters: [Chapter] = [], curiosity: [CuriosityItem] = [], excludedMemoryIDs: Set<MemoryID> = [],
                             related: [Memory] = [], pending: [Candidate] = [], stories: [(Story, [Memory])] = [],
                             entities: [(Entity, String?)] = [], recordingPeople: [ContextPacket.RecordingPerson] = [],
                             budgetTokens: Int = ContextPacketBuilder.defaultBudgetTokens) -> ContextPacket {
        let earlier = previous.filter { $0.index < segment.index }.sorted { $0.index < $1.index }
        let window = earlier.suffix(limits.previousSegments).map(\.text)
        let entries = people
            .filter { !$0.0.isOwner }
            .compactMap { personEntry($0.0, $0.1) }
            .prefix(limits.people)
        // Related earlier memories lead, so the extractor sees what a retelling might belong to.
        var seen = Set<MemoryID>()
        var memoryEntries: [ContextPacket.MemoryEntry] = []
        for memory in related where !memory.excludedFromAI && seen.insert(memory.id).inserted {
            memoryEntries.append(.init(id: memory.id.rawValue, title: memory.title, rangeText: memory.range.isPlaced ? memory.range.displayText : nil, related: true))
        }
        for memory in memories where !memory.excludedFromAI && seen.insert(memory.id).inserted {
            memoryEntries.append(.init(id: memory.id.rawValue, title: memory.title, rangeText: memory.range.isPlaced ? memory.range.displayText : nil))
        }
        let chapterEntries = chapters.map {
            ContextPacket.ChapterEntry(id: $0.id.rawValue, title: $0.title ?? "untitled", rangeText: $0.statedYears?.displayText)
        }
        // Exclude from AI covers what was built from the memory, not only the memory's own entry.
        let questions = curiosity
            .filter { item in ![item.sourceMemoryID, item.targetMemoryID].compactMap { $0 }.contains { excludedMemoryIDs.contains($0) } }
            .prefix(limits.curiosity).map(\.text)
        let pendingEntries: [ContextPacket.PendingEntry] = pending.compactMap { candidate in
            guard candidate.kind == .memory, candidate.status == .pending, let out = CandidatePayload.memory(candidate) else { return nil }
            return .init(candidateID: candidate.id.rawValue, title: out.title, quote: out.quote, storyRef: out.storyRef)
        }
        let storyEntries = stories.map { story, members in
            ContextPacket.StoryEntry(id: story.id.rawValue, title: story.title, momentTitles: members.filter { !$0.excludedFromAI }.map(\.title))
        }
        var packet = ContextPacket(previousSegments: Array(window), people: Array(entries), chapters: chapterEntries, memories: memoryEntries,
                                   curiosity: Array(questions), stage: stage, profileFreeText: profileFreeText,
                                   pending: pendingEntries, stories: storyEntries,
                                   // People have their own section; an entity excluded from AI is never sent (M7).
                                   entities: entities.filter { $0.0.type != .person && !$0.0.excludedFromAI }.map { entity, detail in
                                       ContextPacket.EntityEntry(id: entity.id.rawValue, type: entity.type.rawValue, title: entity.title, detail: detail)
                                   })
        packet.recordingPeople = recordingPeople
        trim(&packet, to: budgetTokens)
        // After the cap and the trim: an id the model was not given a person for is never sent.
        let sentIDs = Set(packet.people.map(\.id))
        for i in packet.recordingPeople.indices where packet.recordingPeople[i].personID.map({ !sentIDs.contains($0) }) ?? false {
            packet.recordingPeople[i].personID = nil
        }
        return packet
    }

    /// One entry per handle, in the order first seen. `people` come in the order said
    /// (`CandidateRepository.handlePeople`). A said name is kept once, by exact text.
    public static func recordingPeople(from people: [PersonOut]) -> [ContextPacket.RecordingPerson] {
        var entries: [ContextPacket.RecordingPerson] = []
        var index: [String: Int] = [:]
        for person in people {
            guard let i = index[person.handle] else {
                index[person.handle] = entries.count
                entries.append(.init(handle: person.handle, saidNames: [person.saidName], relation: person.relationText, personID: person.personID))
                continue
            }
            if !entries[i].saidNames.contains(person.saidName) { entries[i].saidNames.append(person.saidName) }
            if entries[i].relation == nil { entries[i].relation = person.relationText }
            if entries[i].personID == nil { entries[i].personID = person.personID }
        }
        return entries
    }

    /// One person as the model sees them: only names the owner said or typed (`NameForModel`; `aliases`
    /// come oldest first). A person whose name came from a contact and who has no alias is left out.
    static func personEntry(_ person: Person, _ aliases: [Alias]) -> ContextPacket.PersonEntry? {
        guard let name = NameForModel.of(person, aliasesOldestFirst: aliases) else { return nil }
        return ContextPacket.PersonEntry(id: person.id.rawValue, name: name,
                                         aliases: aliases.map(\.text).filter { $0.caseInsensitiveCompare(name) != .orderedSame })
    }

    /// Tokens as characters ÷ 4, never less than one.
    public static func estimate(_ text: String) -> Int { max(1, text.count / 4) }

    /// Drops whole entries from the least relevant section first until the packet fits. The
    /// profile text and each section's first entry stay, so the packet may still exceed the
    /// ceiling by those.
    static func trim(_ packet: inout ContextPacket, to budget: Int) {
        func size() -> Int { estimate(String(decoding: (try? packet.encodedJSON()) ?? Data(), as: UTF8.self)) }
        // Least relevant first; each closure drops one entry and says whether it could.
        let droppers: [(inout ContextPacket) -> Bool] = [
            { $0.curiosity.count > 1 ? ($0.curiosity.removeLast(), true).1 : false },
            { $0.chapters.count > 1 ? ($0.chapters.removeLast(), true).1 : false },
            { $0.stories.count > 1 ? ($0.stories.removeLast(), true).1 : false },
            { $0.entities.count > 1 ? ($0.entities.removeLast(), true).1 : false },
            { $0.people.count > 1 ? ($0.people.removeLast(), true).1 : false },
            { $0.recordingPeople.count > 1 ? ($0.recordingPeople.removeLast(), true).1 : false },
            { $0.memories.count > 1 ? ($0.memories.removeLast(), true).1 : false },
            { $0.pending.count > 1 ? ($0.pending.removeLast(), true).1 : false },
            { $0.previousSegments.count > 1 ? ($0.previousSegments.removeFirst(), true).1 : false },
        ]
        while size() > budget {
            guard droppers.contains(where: { $0(&packet) }) else { return }
        }
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
