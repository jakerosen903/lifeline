import Foundation

public enum MentionChoice: Sendable, Equatable {
    case existing(PersonID)
    case new(displayName: String)
    case notAPerson
}

/// What a tap on a card does to the store. Accepting a memory writes the memory and its edges
/// in one transaction; names the app does not know become mentions for the "Who's this?" queue;
/// resolving a mention links every memory from that segment that named the person.
public struct CandidateActions: Sendable {
    public enum Error: Swift.Error, Equatable {
        case notPending
        case wrongKind
        case badPayload
        case segmentMissing
        case emptySpan
    }

    public struct AcceptedMemory: Sendable, Equatable {
        public var memory: Memory
        /// Unresolved names this acceptance created. Each becomes a "Who's this?" card.
        public var newMentions: [Mention]
    }

    private let store: ExtractionStore

    public init(store: ExtractionStore) { self.store = store }

    public func acceptMemory(_ candidate: Candidate) throws -> AcceptedMemory {
        guard candidate.kind == .memory else { throw Error.wrongKind }
        try requirePending(candidate)
        guard let out = CandidatePayload.memory(candidate) else { throw Error.badPayload }
        let words = try store.sessions.words(in: candidate.segmentID)
        guard !words.isEmpty, out.segmentSpan.startWord >= 0, out.segmentSpan.endWord < words.count,
              out.segmentSpan.startWord <= out.segmentSpan.endWord else { throw Error.emptySpan }

        let memory = Memory(id: .init(), title: out.title, summaryQuote: out.quote, visibility: .timeline, chapterID: nil,
                            createdFromCandidateID: candidate.id, createdAt: .now, earliest: nil, latest: nil, likelyStart: nil,
                            likelyEnd: nil, granularity: nil, origin: nil, evidenceText: nil)
        let span = MemorySpan(memoryID: memory.id, segmentID: candidate.segmentID,
                              startMs: words[out.segmentSpan.startWord].startMs, endMs: words[out.segmentSpan.endWord].endMs, order: 0)

        var people: [MemoryPerson] = []
        var unknown: [String] = []
        for ref in out.peopleRefs {
            if let person = try store.people.findPerson(matching: ref) {
                if !people.contains(where: { $0.personID == person.id }) {
                    people.append(MemoryPerson(memoryID: memory.id, personID: person.id, roleText: ref))
                }
            } else if !unknown.contains(where: { Self.same($0, ref) }) {
                unknown.append(ref)
            }
        }
        var places: [MemoryPlace] = []
        if let text = out.placeText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            places.append(MemoryPlace(memoryID: memory.id, placeID: try store.people.insertPlace(nameText: text).id))
        }
        let anchors = out.anchors.map {
            Anchor(id: .init(), memoryID: memory.id, phrase: $0.phrase, relation: $0.relation, targetKind: .none, targetID: nil,
                   value: $0.value, resolved: false)
        }

        try store.memories.insert(memory, spans: [span], people: people, places: places, anchors: anchors)
        try store.candidates.setStatus(candidate.id, .accepted)

        var newMentions: [Mention] = []
        for name in unknown {
            newMentions.append(try mention(for: name, in: candidate.segmentID))
        }
        return AcceptedMemory(memory: memory, newMentions: newMentions)
    }

    public func dismiss(_ candidate: Candidate) throws {
        try requirePending(candidate)
        try store.candidates.setStatus(candidate.id, .dismissed)
    }

    /// Writes the mention row for a `person` candidate, reusing one the same segment already has
    /// for the same name. Called when the card is first shown so the queue survives a kill.
    public func acceptMention(_ candidate: Candidate) throws -> Mention {
        guard candidate.kind == .person else { throw Error.wrongKind }
        guard let out = CandidatePayload.mention(candidate) else { throw Error.badPayload }
        let row = try mention(for: out.text, in: candidate.segmentID)
        if candidate.status == .pending { try store.candidates.setStatus(candidate.id, .accepted) }
        return row
    }

    /// Returns the person the mention now points at, or nil for "not a person".
    @discardableResult
    public func resolveMention(_ id: MentionID, to choice: MentionChoice) throws -> Person? {
        guard let mention = try store.people.mention(id: id) else { return nil }
        let person: Person?
        switch choice {
        case .existing(let personID):
            try store.people.resolve(id, to: personID)
            person = try store.people.person(id: personID)
        case .new(let displayName):
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = try store.people.insertPerson(displayName: name.isEmpty ? mention.text : name)
            try store.people.resolve(id, to: created.id)
            person = created
        case .notAPerson:
            try store.people.markNotAPerson(id)
            person = nil
        }
        if let person {
            for memory in try store.memories.memories(fromSegment: mention.segmentID) where try names(memory, mention.text) {
                try store.memories.link(person.id, to: memory.id, roleText: mention.text)
            }
        }
        return person
    }

    // MARK: - Helpers

    private func requirePending(_ candidate: Candidate) throws {
        guard try store.candidates.fetch(candidate.id)?.status == .pending else { throw Error.notPending }
    }

    private func mention(for text: String, in segment: SegmentID) throws -> Mention {
        if let existing = try store.people.mentions(in: segment).first(where: { Self.same($0.text, text) }) { return existing }
        let row = Mention(id: .init(), segmentID: segment, text: text.trimmingCharacters(in: .whitespacesAndNewlines), status: .unresolved, personID: nil)
        try store.people.insertMention(row)
        return row
    }

    /// True when the memory's candidate named this person.
    private func names(_ memory: Memory, _ text: String) throws -> Bool {
        guard let candidate = try store.candidates.fetch(memory.createdFromCandidateID), let out = CandidatePayload.memory(candidate) else { return false }
        return out.peopleRefs.contains { Self.same($0, text) }
    }

    static func same(_ a: String, _ b: String) -> Bool {
        PeopleRepository.normalize(a) == PeopleRepository.normalize(b)
    }
}
