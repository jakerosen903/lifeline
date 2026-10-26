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
        case memoryNotAccepted
        case notDismissed
        case emptyTitle
        // M4.1 merging and stated ranges
        case targetMissing
        case sameMemory
        case stale
        case notStated
        case standIn
        // M5 stories
        case nothingToSplit
    }

    public enum HintResult: Equatable, Sendable {
        case collection(Collection)
        case chapter(Chapter)
        case story(Story)
        /// A free-text domain on the memory (M7).
        case domain(String)
    }

    public struct AcceptedMemory: Sendable, Equatable {
        public var memory: Memory
        /// Unresolved names this acceptance created. Each becomes a "Who's this?" card.
        public var newMentions: [Mention]
    }

    let store: ExtractionStore
    /// Keeps the embeddings current; nil in the CLI and under UI testing.
    let matcher: MemoryMatcher?

    public init(store: ExtractionStore, matcher: MemoryMatcher? = nil) { self.store = store; self.matcher = matcher }

    // MARK: - Correction (M4)

    /// Change… → The title. The quote is the owner's words and is never edited.
    public func renameMemory(_ memory: MemoryID, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.emptyTitle }
        try store.memories.updateTitle(memory, trimmed)
        try reindex(memory)
    }

    /// Change… → Who was there. A second link to the same person is a no-op.
    public func linkPerson(_ person: PersonID, to memory: MemoryID, roleText: String?) throws {
        try store.memories.link(person, to: memory, roleText: roleText)
    }

    /// A name typed in: an existing person by that name is reused, otherwise one is created.
    @discardableResult
    public func linkNewPerson(named name: String, to memory: MemoryID) throws -> Person {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.emptyTitle }
        let person = try store.people.findPerson(matching: trimmed) ?? store.people.insertPerson(displayName: trimmed)
        try store.memories.link(person.id, to: memory, roleText: nil)
        return person
    }

    /// Unlinking never deletes the person: they may be in other memories, and People keeps them.
    public func unlinkPerson(_ person: PersonID, from memory: MemoryID) throws {
        try store.memories.unlink(person, from: memory)
    }

    // MARK: - Privacy (M4)

    public func setHidden(_ memory: MemoryID, _ hidden: Bool) throws { try store.memories.setHidden(memory, hidden) }
    public func setExcluded(_ memory: MemoryID, _ excluded: Bool) throws {
        try store.memories.setExcluded(memory, excluded)
        try reindex(memory)   // an excluded memory loses its vector; an included one gets it back
    }

    /// "Hide today from the timeline": every memory told in the session leaves everyday browsing.
    public func hideSession(_ session: SessionID) throws {
        try store.sessions.setHidden(session, true)
        for memory in try store.memories.memories(in: session, includingStandIns: true) {
            try store.memories.setHidden(memory.id, true)
        }
    }

    /// "Delete today's recording…": the audio file goes first, then every row derived from the
    /// session. A file already gone is not an error. The caller cancels any sorting worker first.
    public func deleteSession(_ session: SessionID, audioURL: URL) throws {
        if FileManager.default.fileExists(atPath: audioURL.path) {
            try FileManager.default.removeItem(at: audioURL)
        }
        try store.sessions.deleteSession(session)
    }

    /// `joinStory: false` is the card's "Not part of it": the memory lands with no story.
    public func acceptMemory(_ candidate: Candidate, joinStory: Bool = true) throws -> AcceptedMemory {
        guard candidate.kind == .memory else { throw Error.wrongKind }
        try requirePending(candidate)
        guard let out = CandidatePayload.memory(candidate) else { throw Error.badPayload }
        let words = try store.sessions.words(in: candidate.segmentID)
        guard !words.isEmpty, out.segmentSpan.startWord >= 0, out.segmentSpan.endWord < words.count,
              out.segmentSpan.startWord <= out.segmentSpan.endWord else { throw Error.emptySpan }

        // A session hidden from the timeline hides what is kept from it later, too.
        let hidden = try store.sessions.fetchSegment(candidate.segmentID).flatMap { try store.sessions.fetch($0.sessionID) }?.hiddenFromTimeline ?? false
        let memory = Memory(id: .init(), title: out.title, summaryQuote: out.quote, visibility: .timeline, chapterID: nil,
                            createdFromCandidateID: candidate.id, createdAt: .now, hiddenFromTimeline: hidden,
                            kind: out.kind ?? .event)
        var spans = [MemorySpan(memoryID: memory.id, segmentID: candidate.segmentID,
                                startMs: words[out.segmentSpan.startWord].startMs, endMs: words[out.segmentSpan.endWord].endMs, order: 0)]
        spans += try continuationSpans(of: out, for: memory.id)

        // The card's edges and every continuation's, as one telling (M5).
        let continuations = try store.candidates.continuations(of: candidate.id)
        var edges = try edges(of: out, for: memory.id, segment: candidate.segmentID)
        for row in continuations { if let o = CandidatePayload.memory(row) { edges.merge(try self.edges(of: o, for: memory.id, segment: row.segmentID)) } }
        // The memory, its continuation cards' status and its story line land together (M5).
        let storyRef = joinStory ? out.storyRef.flatMap { $0.isEmpty ? nil : StoryID(rawValue: $0) } : nil
        try store.memories.insert(memory, spans: spans, people: edges.people, places: edges.places, links: edges.links, entities: edges.entityWrite, anchors: edges.anchors,
                                  acceptingCandidate: candidate.id, acceptingContinuations: continuations.map(\.id),
                                  joiningStory: storyRef.map { (id: $0, chapterID: memory.chapterID) })
        let newMentions = try finishEdges(edges, segment: candidate.segmentID)
        try reindex(memory.id)
        // Place what the new anchors allow, and re-place anything that pointed at this title.
        _ = try ResolverRunner(store: store).run()
        return AcceptedMemory(memory: memory, newMentions: newMentions)
    }

    /// The people, places and anchors a card names, built for `memory`. Shared by Keep and
    /// Same story so a retelling links exactly as a first telling does.
    struct Edges {
        var people: [MemoryPerson] = []
        var unknown: [String] = []
        var roleAliases: [(PersonID, String)] = []
        var places: [MemoryPlace] = []
        var anchors: [Anchor] = []
        /// Things and ideas named (mention) and what a fact, feeling or goal is about (detail) (M7).
        var links: [MomentEntity] = []
        /// New entities and their tags, written in the memory's own transaction (M7).
        var entityWrite = EntityRepository.Write()

        /// The union with another segment's edges, deduplicated as one segment's are.
        mutating func merge(_ other: Edges) {
            // Two segments that both named a new "the house" plan one entity, not two.
            let remap = entityWrite.merge(other.entityWrite)
            for person in other.people where !people.contains(where: { $0.personID == person.personID }) { people.append(person) }
            for name in other.unknown where !unknown.contains(where: { CandidateActions.same($0, name) }) { unknown.append(name) }
            roleAliases += other.roleAliases.filter { pair in !roleAliases.contains { $0.0 == pair.0 && $0.1 == pair.1 } }
            for var place in other.places {
                if let mapped = remap[EntityID(rawValue: place.placeID.rawValue)] { place.placeID = PlaceID(rawValue: mapped.rawValue) }
                if !places.contains(where: { $0.placeID == place.placeID }) { places.append(place) }
            }
            anchors += other.anchors.filter { a in !anchors.contains { $0.phrase == a.phrase && $0.relation == a.relation } }
            for var link in other.links {
                link.entityID = remap[link.entityID] ?? link.entityID
                if !links.contains(where: { $0.entityID == link.entityID && $0.relation == link.relation }) { links.append(link) }
            }
        }
    }

    /// One span per continuation segment, each carrying on the first telling (M5). Words are
    /// looked up per segment; a span that no longer fits its segment is skipped, not guessed.
    func continuationSpans(of out: MemoryOut, for memory: MemoryID) throws -> [MemorySpan] {
        var spans: [MemorySpan] = []
        for (i, extra) in out.extraSpans.enumerated() {
            let segment = SegmentID(rawValue: extra.segmentID)
            let words = try store.sessions.words(in: segment)
            guard extra.startWord >= 0, extra.endWord < words.count, extra.startWord <= extra.endWord else { continue }
            spans.append(MemorySpan(memoryID: memory, segmentID: segment, startMs: words[extra.startWord].startMs, endMs: words[extra.endWord].endMs,
                                    order: i + 1, continuesOrder: 0))
        }
        return spans
    }

    func edges(of out: MemoryOut, for memory: MemoryID, segment: SegmentID? = nil) throws -> Edges {
        let currentSegment = segment
        var e = Edges()
        for ref in out.peopleRefs {
            if let person = try store.people.findPerson(matching: ref) {
                if !e.people.contains(where: { $0.personID == person.id }) {
                    e.people.append(MemoryPerson(memoryID: memory, personID: person.id, roleText: ref))
                }
                // "my mom, Marcel": the role half becomes an alias so "my mom" alone links next time.
                let parts = PeopleRepository.parts(of: ref)
                if parts.count > 1 { e.roleAliases += parts.dropFirst().map { (person.id, $0) } }
            } else if !e.unknown.contains(where: { Self.same($0, ref) }) {
                e.unknown.append(ref)
            }
        }
        // Places, things and ideas the card names (its chips) link on Keep without a card of their own (M7).
        for ref in out.allEntityRefs where ref.kind != .person {
            let entity = try entity(for: ref, plan: &e.entityWrite)
            if ref.kind == .place {
                if !e.places.contains(where: { $0.placeID.rawValue == entity.id.rawValue }) {
                    e.places.append(MemoryPlace(memoryID: memory, placeID: PlaceID(rawValue: entity.id.rawValue)))
                }
            } else if !e.links.contains(where: { $0.entityID == entity.id && $0.relation == .mention }) {
                e.links.append(MomentEntity(memoryID: memory, entityID: entity.id, relation: .mention, roleText: ref.text))
            }
        }
        // A fact, feeling or goal is a detail of what it is about; a moment never is (M7).
        if let kind = out.kind, !kind.isMoment, let about = try aboutEntity(out.aboutRef, segment: currentSegment, plan: &e.entityWrite) {
            e.links.append(MomentEntity(memoryID: memory, entityID: about, relation: .detail))
        }
        e.anchors = out.anchors.map {
            Anchor(id: .init(), memoryID: memory, phrase: $0.phrase, relation: $0.relation, targetKind: .none, targetID: nil,
                   targetText: $0.targetText, value: $0.value, resolved: false)
        }
        return e
    }

    /// The entity a ref names: the one the packet pointed at when it is that type, else one of the
    /// same type and title, else a new one.
    private func entity(for ref: EntityRefOut, plan: inout EntityRepository.Write) throws -> Entity {
        if let id = ref.likelyEntityID, let known = try store.entities.entity(id: EntityID(rawValue: id)), known.type == ref.kind.entityType { return known }
        return try planEntity(type: ref.kind.entityType, title: ref.text, candidate: nil, plan: &plan)
    }

    /// An entity of this type and title on file, already planned, or planned now. Nothing is written.
    func planEntity(type: EntityType, title: String, candidate: CandidateID?, plan: inout EntityRepository.Write) throws -> Entity {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EntityRepository.Error.emptyTitle }
        if let known = try store.entities.find(type: type, title: trimmed) { return known }
        if let planned = plan.planned(type, trimmed) { return planned }
        let entity = Entity(type: type, title: trimmed, createdFromCandidateID: candidate)
        plan.entities.append(entity)
        return entity
    }

    /// `about_ref` resolved: `self` is the owner; an id on file is that entity; a mention's `ref`
    /// in the same segment becomes its entity. Nil when it names nothing the app can find.
    private func aboutEntity(_ ref: String?, segment currentSegment: SegmentID?, plan: inout EntityRepository.Write) throws -> EntityID? {
        guard let ref = ref?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else { return nil }
        if ref == "self" { return try store.profile.owner()?.entityID }
        if let known = try store.entities.entity(id: EntityID(rawValue: ref)) { return known.id }
        guard let segment = currentSegment,
              let row = try store.candidates.candidates(for: segment).first(where: { ($0.kind == .entity || $0.kind == .place) && CandidatePayload.mention($0)?.ref == ref }),
              let mention = CandidatePayload.mention(row), mention.kind != .person else { return nil }
        return try proposeEntity(from: mention, candidate: row, plan: &plan).id
    }

    /// An entity from a mention, planned: an idea's title is the person's words or the dated default.
    func proposeEntity(from mention: MentionOut, candidate: Candidate, as type: EntityType? = nil, plan: inout EntityRepository.Write) throws -> Entity {
        let type = type ?? mention.kind.entityType
        if let id = mention.likelyEntityID, let known = try store.entities.entity(id: EntityID(rawValue: id)), known.type == type { return known }
        let title: String
        if type == .idea {
            let text = try store.sessions.fetchSegment(candidate.segmentID)?.text ?? ""
            let told = try store.sessions.fetchSegment(candidate.segmentID).flatMap { try store.sessions.fetch($0.sessionID) }?.startedAt ?? candidate.createdAt
            title = IdeaTitle.title(proposed: mention.title, segmentText: text, toldOn: told)
        } else {
            title = mention.text
        }
        let entity = try planEntity(type: type, title: title, candidate: candidate.id, plan: &plan)
        if let hint = mention.domainHint { plan.tags.append(.init(entityID: entity.id, text: hint)) }
        return entity
    }

    /// Aliases and the "Who's this?" mentions that follow the edges. Returns the new mentions.
    func finishEdges(_ edges: Edges, segment: SegmentID) throws -> [Mention] {
        for (person, alias) in edges.roleAliases { try store.people.addAlias(alias, to: person) }
        return try edges.unknown.map { try mention(for: $0, in: segment) }
    }

    func reindex(_ memory: MemoryID) throws {
        guard let matcher, let row = try store.memories.fetch(memory) else { return }
        try matcher.index(row)
    }

    public func dismiss(_ candidate: Candidate) throws {
        try requirePending(candidate)
        try store.candidates.setStatus(candidate.id, .dismissed)
    }

    /// A wrong tap costs nothing: a dismissed card waits again. Only what the owner dismissed
    /// comes back; what the validator rejected or the app withheld stays out.
    public func restore(_ candidate: Candidate) throws {
        guard let current = try store.candidates.fetch(candidate.id), current.status == .dismissed, current.rejection == nil else {
            throw Error.notDismissed
        }
        try store.candidates.setStatus(candidate.id, .pending)
        if current.kind == .person, let mention = try store.people.mentions(in: current.segmentID).first(where: { m in
            CandidatePayload.mention(current).map { Self.same($0.text, m.text) } ?? false
        }), mention.status == .notAPerson {
            try store.people.reopen(mention.id)
        }
    }

    public func restoreMention(_ id: MentionID) throws {
        try store.people.reopen(id)
    }

    /// Writes the mention row for a `person` candidate, reusing one the same segment already has
    /// for the same name. Called when the card is first shown so the queue survives a kill.
    public func acceptMention(_ candidate: Candidate) throws -> Mention {
        guard candidate.kind == .person else { throw Error.wrongKind }
        guard let out = CandidatePayload.mention(candidate) else { throw Error.badPayload }
        let row = try mention(for: out.text, in: candidate.segmentID, relation: out.relationText)
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
            let wanted = name.isEmpty ? mention.text : name
            // A typed name the app already knows is that person, not a second one.
            let existing = try store.people.findPerson(matching: wanted)
            let target = try existing ?? store.people.insertPerson(displayName: wanted)
            try store.people.resolve(id, to: target.id)
            person = target
        case .notAPerson:
            try store.people.markNotAPerson(id)
            person = nil
        }
        if let person {
            try linkMemories(naming: mention.text, in: mention.segmentID, to: person.id)
            // The same name waiting in other segments is the same question; answer it once.
            for other in try store.people.mentions(status: .unresolved) where other.id != id && Self.same(other.text, mention.text) {
                try store.people.resolve(other.id, to: person.id)
                try linkMemories(naming: other.text, in: other.segmentID, to: person.id)
            }
        } else {
            for other in try store.people.mentions(status: .unresolved) where other.id != id && Self.same(other.text, mention.text) {
                try store.people.markNotAPerson(other.id)
            }
        }
        return person
    }

    /// Records a mention the app can answer itself because the name is already known.
    /// Returns the person when it did, nil when the name is new and needs a card.
    @discardableResult
    public func resolveIfKnown(_ mention: Mention) throws -> Person? {
        guard mention.status == .unresolved, let person = try store.people.findPerson(matching: mention.text) else { return nil }
        try store.people.resolve(mention.id, to: person.id)
        try linkMemories(naming: mention.text, in: mention.segmentID, to: person.id)
        return person
    }

    private func linkMemories(naming text: String, in segment: SegmentID, to person: PersonID) throws {
        for memory in try store.memories.memories(fromSegment: segment) where try names(memory, text) {
            try store.memories.link(person, to: memory.id, roleText: text)
        }
    }

    // MARK: - Relative questions

    /// The owner answered: the range is confirmed, the anchor behind the question is settled,
    /// any open question about this memory closes, and the resolver places whatever follows.
    public func answer(_ question: RelativeQuestion, with choice: RelativeQuestion.Choice) throws {
        guard let memory = try store.memories.fetch(question.memoryID) else { return }
        let span = try store.memories.spans(of: memory.id).first
        let ref = MemoryRef(id: memory.id, title: memory.title, range: memory.range,
                            primarySpan: MemoryRef.Span(segmentID: span?.segmentID ?? SegmentID(rawValue: ""), startMs: span?.startMs ?? 0, endMs: span?.endMs ?? 0), kind: memory.kind)
        try store.memories.updateRange(memory.id, RelativeQuestions.apply(choice, to: ref))
        if let anchorID = question.anchorID, var anchor = try store.memories.anchors(of: memory.id).first(where: { $0.id == anchorID }) {
            anchor.resolved = true
            try store.memories.update(anchor)
        }
        // The runner refreshes the open questions from what is still unplaced.
        _ = try ResolverRunner(store: store).run()
    }

    /// "Tell me when": the person's own date, at their precision. Only a stated range may be
    /// written here; the app never dresses a guess as a fact.
    public func setStatedRange(_ memory: MemoryID, _ range: TimeRange) throws {
        guard range.origin == .stated, range.isPlaced else { throw Error.notStated }
        try store.memories.updateRange(memory, range)
        _ = try ResolverRunner(store: store).run()
    }

    // MARK: - Hints, chapters and collections

    /// "Sounds like it belongs here", accepted: the hint's memory joins a collection or chapter
    /// titled with the owner's phrase, reusing one that already exists.
    public func acceptHint(_ candidate: Candidate) throws -> HintResult {
        guard candidate.kind == .hint else { throw Error.wrongKind }
        try requirePending(candidate)
        guard let out = CandidatePayload.hint(candidate) else { throw Error.badPayload }
        // The card was kept as its own memory, or merged into one as a later telling (M4.1).
        let cardID = CandidateID(rawValue: out.memoryCandidateID)
        guard let memory = try store.memories.memory(createdFrom: cardID) ?? store.memories.memory(withSpanFrom: cardID) else { throw Error.memoryNotAccepted }
        let result: HintResult
        switch out.kind {
        case .collection:
            result = .collection(try addToCollection(memory.id, titled: out.phrase))
        case .chapter:
            if let existing = try store.chapters.chapters().first(where: { Self.same($0.title ?? "", out.phrase) }) {
                try assign(memory: memory.id, toChapter: existing.id)
                result = .chapter(try store.chapters.chapter(id: existing.id) ?? existing)
            } else {
                result = .chapter(try createChapter(title: out.phrase, containing: memory.id))
            }
        case .story:
            result = .story(try acceptStoryHint(out.phrase, for: memory.id))
        case .domain:
            try store.tags.tag(.memory, memory.id.rawValue, out.phrase)
            result = .domain(out.phrase)
        }
        try store.candidates.setStatus(candidate.id, .accepted)
        return result
    }

    public func createChapter(title: String?, containing memory: MemoryID) throws -> Chapter {
        let chapter = try store.chapters.insertChapter(title: title)
        try assign(memory: memory, toChapter: chapter.id)
        return try store.chapters.chapter(id: chapter.id) ?? chapter
    }

    /// Moves a memory between chapters and refreshes both chapters' member-derived ranges.
    public func assign(memory: MemoryID, toChapter chapter: ChapterID?) throws {
        let previous = try store.memories.fetch(memory)?.chapterID
        try store.chapters.assign(memory: memory, toChapter: chapter)
        for id in [previous, chapter].compactMap({ $0 }) { try chapterRangeFromMembers(id) }
    }

    /// "What is this?" on the Change sheet (M7): the only way a memory changes kind. A moment
    /// turned fact leaves its chapter's range and its questions; a fact turned moment comes back.
    public func setKind(_ memory: MemoryID, _ kind: MemoryKind) throws {
        guard let current = try store.memories.fetch(memory) else { return }
        guard current.kind != kind else { return }
        try store.memories.setKind(memory, kind)   // the chapter range, links and story move in the same write
        _ = try ResolverRunner(store: store).run()
    }

    public func addToCollection(_ memory: MemoryID, titled title: String) throws -> Collection {
        let collection = try store.chapters.insertCollection(titled: title)
        try store.chapters.add(memory: memory, to: collection.id)
        return collection
    }

    public func removeFromCollection(_ memory: MemoryID, from collection: CollectionID) throws {
        try store.chapters.remove(memory: memory, from: collection)
    }

    /// A chapter's range is the span of its placed members, origin `derived`; unplaced when none are placed.
    public func chapterRangeFromMembers(_ chapter: ChapterID) throws {
        try store.chapters.setRange(chapter, ChapterRepository.span(over: try store.memories.moments(inChapter: chapter).map(\.range)))
    }

    // MARK: - Helpers

    func requirePending(_ candidate: Candidate) throws {
        guard try store.candidates.fetch(candidate.id)?.status == .pending else { throw Error.notPending }
    }

    func mention(for text: String, in segment: SegmentID, relation: String? = nil) throws -> Mention {
        if let existing = try store.people.mentions(in: segment).first(where: { Self.same($0.text, text) }) { return existing }
        let row = Mention(id: .init(), segmentID: segment, text: text.trimmingCharacters(in: .whitespacesAndNewlines), status: .unresolved,
                          personID: nil, relationText: relation?.trimmingCharacters(in: .whitespacesAndNewlines))
        try store.people.insertMention(row)
        return row
    }

    /// True when the memory's candidate named this person.
    /// Whether the memory's card, or any segment that carried it on (M5), named this person.
    private func names(_ memory: Memory, _ text: String) throws -> Bool {
        guard let candidateID = memory.createdFromCandidateID, let candidate = try store.candidates.fetch(candidateID),
              let out = CandidatePayload.memory(candidate) else { return false }
        let refs = out.peopleRefs + (try store.candidates.continuations(of: candidateID)).compactMap(CandidatePayload.memory).flatMap(\.peopleRefs)
        return refs.contains { Self.same($0, text) }
    }

    static func same(_ a: String, _ b: String) -> Bool {
        PeopleRepository.normalize(a) == PeopleRepository.normalize(b)
    }
}
