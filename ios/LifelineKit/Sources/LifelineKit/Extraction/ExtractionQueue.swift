import Foundation

public enum ExtractionEvent: Sendable, Equatable {
    /// Accepted candidates for a segment, in ordinal order. Rejected ones are stored, not sent.
    case candidates([Candidate], segment: SegmentID)
    case flags(Flags, segment: SegmentID)
    case failed(segment: SegmentID, ExtractionError)
    case skipped(segment: SegmentID)
}

/// Per-session extraction. Segments are processed one at a time in arrival order, so
/// candidates and their ordinals are stable. A failure leaves the segment pending and moves
/// on; `drain()` retries segments whose failure was transient, once, within a deadline, which
/// is what Stop calls. A missing key stops requests for the rest of the session: the person
/// is told once, not once per segment. A serious disclosure is never offered back as a memory
/// card: its memory candidates are stored withheld, and flags reach listeners before cards so
/// later cards in the session are suppressed too.
public actor ExtractionQueue {
    public nonisolated let events: AsyncStream<ExtractionEvent>
    private let emit: AsyncStream<ExtractionEvent>.Continuation

    private let session: SessionID
    private let service: any ExtractionService
    private let store: ExtractionStore
    private let stage: String
    private let drainDeadline: Duration
    private let log: @Sendable (String) -> Void
    private let actions: CandidateActions
    private let matcher: MemoryMatcher?
    private let reporter: SortingReporter?

    private var waiting: [SegmentID] = []
    private var running = false
    private var keyMissing = false
    private var lastFailure: [SegmentID: ExtractionError] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    /// Raw story refs the model made up, and the ids minted for them, for this session (M5).
    private var mintedStoryRefs: [String: StoryID] = [:]

    public static let defaultDrainDeadline: Duration = .seconds(20)
    public static let withheldReason = "withheld: serious disclosure"

    public init(session: SessionID, service: any ExtractionService, store: ExtractionStore, stage: String = "open",
                drainDeadline: Duration = ExtractionQueue.defaultDrainDeadline, matcher: MemoryMatcher? = nil, reporter: SortingReporter? = nil,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.session = session; self.service = service; self.store = store; self.stage = stage
        self.drainDeadline = drainDeadline; self.log = log; self.matcher = matcher; self.reporter = reporter
        actions = CandidateActions(store: store)
        (events, emit) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// True once a request failed for want of an API key; nothing more is tried this session.
    public var isKeyMissing: Bool { keyMissing }

    public func enqueue(_ segment: SegmentID) {
        waiting.append(segment)
        startWorkerIfNeeded()
    }

    /// Waits for the queue to empty, retries pending segments whose last failure was transient,
    /// waits again. Gives up at the deadline: the session ends and the CLI or a later run picks
    /// the segments up. Work in flight carries on in the background.
    public func drain() async {
        let deadline = ContinuousClock.now + drainDeadline
        guard await waitUntilIdle(until: deadline), !keyMissing else { return }
        let retry = ((try? store.sessions.segments(in: session, status: .pending)) ?? [])
            .filter { lastFailure[$0.id]?.isTransient ?? true }
        guard !retry.isEmpty else { return }
        log("retrying \(retry.count) pending segment(s)")
        for segment in retry { waiting.append(segment.id) }
        startWorkerIfNeeded()
        _ = await waitUntilIdle(until: deadline)
    }

    public func finish() {
        emit.finish()
    }

    // MARK: - Worker

    private func startWorkerIfNeeded() {
        guard !running else { return }
        running = true
        Task { await self.work() }
    }

    private func work() async {
        reporter?.activityChanged(active: true)
        while !waiting.isEmpty {
            let segment = waiting.removeFirst()
            await process(segment)
        }
        reporter?.activityChanged(active: false)
        running = false
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// False when the deadline passed first.
    private func waitUntilIdle(until deadline: ContinuousClock.Instant) async -> Bool {
        while running || !waiting.isEmpty {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return true
    }

    private func process(_ segmentID: SegmentID) async {
        if keyMissing {
            emit.yield(.failed(segment: segmentID, .noKey))
            return
        }
        do {
            guard let segment = try store.sessions.fetchSegment(segmentID) else { return }
            if try store.candidates.hasCandidates(for: segmentID, version: service.version) {
                // Rows exist but the status may not: a kill between the two. Close it out.
                if segment.status == .pending { try store.sessions.setStatus(.extracted, for: segmentID) }
                emit.yield(.skipped(segment: segmentID))
                return
            }
            let words = try store.sessions.words(in: segmentID).map(\.text)
            let request = ExtractionRequest(segmentID: segmentID, segmentText: segment.text, words: words, packet: try packet(for: segment))
            var response = try await service.extract(request)
            if Self.isBlank(response.output) {
                // Seen once on device: one memory with every field empty and nothing else. Noise, not an answer. Ask again once.
                log("segment \(segment.index): blank answer from \(response.model), asking again")
                response = try await service.extract(request)
                if Self.isBlank(response.output) { throw ExtractionError.badOutput("blank answer") }
            }
            var validated = OutputValidator.validate(response.output, segmentText: segment.text, words: words)
            try mintStoryRefs(&validated)
            let shown = try storeCandidates(validated, segment: segmentID, version: response.version)
            lastFailure[segmentID] = nil
            reporter?.cleared()
            log("segment \(segment.index): \(shown.count) shown, \(validated.rejected.count) rejected, model \(response.model), "
                + "\(response.usage.inputTokens) in / \(response.usage.outputTokens) out, cache read \(response.usage.cacheReadInputTokens)")
            for rejected in validated.rejected { log("  rejected: \(rejected.reason)") }
            // Flags first: a listener must know about a disclosure before it sees any card.
            if validated.flags.isAnySet { emit.yield(.flags(validated.flags, segment: segmentID)) }
            emit.yield(.candidates(shown, segment: segmentID))
        } catch let error as ExtractionError {
            if error == .noKey { keyMissing = true }
            lastFailure[segmentID] = error
            reporter?.failed(error)
            log("segment \(segmentID) failed: \(error)")
            emit.yield(.failed(segment: segmentID, error))
        } catch {
            log("segment \(segmentID) store error: \(error)")
            emit.yield(.failed(segment: segmentID, .badOutput("store: \(error)")))
        }
    }

    /// A memory with no words at all, and nothing else in the reply.
    static func isBlank(_ output: ExtractorOutput) -> Bool {
        !output.memories.isEmpty && output.mentions.isEmpty && !output.flags.isAnySet
            && output.memories.allSatisfy { $0.quote.trimmingCharacters(in: .whitespaces).isEmpty && $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func packet(for segment: Segment) throws -> ContextPacket {
        let previous = try store.sessions.segments(in: session)
        let memories = try store.memories.memories(in: session)
        let freeText = try store.profile.fetch()?.freeText
        // Earlier memories that read like this segment, so a retelling can be named (M4.1).
        let related = try matcher?.related(to: segment.text, excluding: Set(memories.map(\.id))) ?? []
        // People named in this or the previous segments first, then by most recent link (M5).
        let recentText = ([segment] + previous.filter { $0.index < segment.index }.suffix(2)).map(\.text).joined(separator: " ")
        let people = try store.people.peopleByRecentLink()
            .map { ($0, (try? store.people.aliases(of: $0.id)) ?? []) }
            .sorted { Self.isNamed($0, in: recentText) && !Self.isNamed($1, in: recentText) }
        // This session's cards still waiting, except this segment's own, so a continuation can name one (M5).
        let pending = try store.candidates.pending(in: session).filter { $0.kind == .memory && $0.segmentID != segment.id }
        var storyIDs: [StoryID] = []
        var stories: [(Story, [Memory])] = []
        for memory in related + memories {
            guard let story = try store.stories.story(of: memory.id), !storyIDs.contains(story.id) else { continue }
            storyIDs.append(story.id)
            stories.append((story, try store.stories.members(of: story.id)))
        }
        return ContextPacketBuilder.build(segment: segment, previous: previous, people: people, memories: memories,
                                          profileFreeText: freeText, stage: stage,
                                          chapters: try store.chapters.chapters(), curiosity: try store.curiosity.open(),
                                          excludedMemoryIDs: try store.memories.excludedIDs(), related: related,
                                          pending: pending, stories: stories)
    }

    private static func isNamed(_ entry: (Person, [Alias]), in text: String) -> Bool {
        let lower = text.lowercased()
        return ([entry.0.displayName] + entry.1.map(\.text)).contains { !$0.isEmpty && lower.contains($0.lowercased()) }
    }

    /// Writes one row per candidate in output order, plus a flag row when any flag is set, and
    /// marks the segment extracted, all in one transaction. Rejected rows are dismissed with the
    /// reason; after a serious disclosure the memory rows are withheld the same way. A person
    /// mention whose name the app already knows is resolved on the spot and not shown.
    /// Returns the rows to show.
    private func storeCandidates(_ validated: OutputValidator.Validated, segment: SegmentID, version: String) throws -> [Candidate] {
        var ordinal = 0
        var rows: [Candidate] = []
        var shown: [Candidate] = []
        var knownMentions: [(Candidate, MentionOut)] = []
        // Flags and place mentions are records with nothing to tap in M2; they are stored
        // accepted so the pending set is exactly the cards still waiting for an answer.
        func row(_ kind: CandidateKind, _ payload: String, _ confidence: Double, _ rejection: String?) -> Candidate {
            defer { ordinal += 1 }
            let status: CandidateStatus = rejection != nil ? .dismissed : (kind == .flag || kind == .place ? .accepted : .pending)
            return Candidate(id: .init(), segmentID: segment, extractorVersion: version, ordinal: ordinal, kind: kind, payload: payload,
                             confidence: confidence, status: status, rejection: rejection, createdAt: .now)
        }
        var extended: [CandidateRepository.Continuation] = []
        for candidate in validated.accepted {
            let r = try Self.describe(candidate)
            if case .memory = candidate, validated.flags.seriousDisclosure {
                rows.append(row(r.kind, r.payload, r.confidence, Self.withheldReason))
                continue
            }
            // A telling carried on after a pause: the earlier card grows a span and shows again;
            // this row is kept, superseded, so Keep can take its people, places and anchors (M5).
            if case .memory(let memory) = candidate, let earlier = try pendingCard(named: memory.continuesCandidateID) {
                var c = row(r.kind, r.payload, r.confidence, CandidateRepository.continuesReason(earlier.id))
                c.status = .superseded
                rows.append(c)
                extended.append(.init(earlierID: earlier.id, rowID: c.id,
                                      span: ExtraSpan(segmentID: segment.rawValue, startWord: memory.segmentSpan.startWord, endWord: memory.segmentSpan.endWord)))
                rows += try hintRows(for: memory, keyedTo: earlier.id, row: row)
                continue
            }
            var r2 = r
            // The telling it carries on was already kept: an ordinary card that names that memory (spec, Goal 3).
            if case .memory(var memory) = candidate, let kept = try keptMemory(continuing: memory.continuesCandidateID) {
                memory.sameAsMemoryIDs = [kept.id.rawValue] + memory.sameAsMemoryIDs.filter { $0 != kept.id.rawValue }
                memory.continuesCandidateID = nil
                r2 = try Self.describe(.memory(memory))
            }
            let c = row(r2.kind, r2.payload, r2.confidence, nil)
            rows.append(c)
            if case .mention(let mention) = candidate, mention.kind == .person, try store.people.findPerson(matching: mention.text) != nil {
                knownMentions.append((c, mention))
            } else {
                shown.append(c)
            }
            if case .memory(let memory) = candidate {
                rows += try hintRows(for: memory, keyedTo: c.id, row: row)
            }
        }
        for rejected in validated.rejected {
            let r = try Self.describe(rejected.candidate)
            rows.append(row(r.kind, r.payload, r.confidence, rejected.reason))
        }
        if validated.flags.isAnySet {
            rows.append(row(.flag, try CandidatePayload.encode(validated.flags), 1, nil))
        }
        // Superseded rows are records with nothing to tap; only pending hint rows from this pass show.
        shown += rows.filter { $0.kind == .hint && $0.status == .pending && !shown.contains($0) }
        // The rows, the segment's status and the grown cards land together.
        let grown = try store.candidates.insertAll(rows, markingExtracted: segment, in: store.sessions, extending: extended)
        for (candidate, _) in knownMentions {
            let mention = try actions.acceptMention(candidate)
            try actions.resolveIfKnown(mention)
        }
        for continuation in extended {
            // The grown card shows again; a card kept in the meantime leaves its continuation as an ordinary card.
            let id = grown.contains(continuation.earlierID) ? continuation.earlierID : continuation.rowID
            if let card = try store.candidates.fetch(id) { shown.insert(card, at: 0) }
        }
        return shown
    }

    /// A stored `story_ref` is always a story id: a ref that names no story and no pending
    /// card's ref gets a fresh id, shared by every memory of this session with the same raw ref.
    private func mintStoryRefs(_ validated: inout OutputValidator.Validated) throws {
        let pendingRefs = Set(try store.candidates.pending(in: session).compactMap { CandidatePayload.memory($0)?.storyRef })
        for i in validated.accepted.indices {
            guard case .memory(var memory) = validated.accepted[i], let raw = memory.storyRef?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            if pendingRefs.contains(raw) { continue }
            if try store.stories.story(id: StoryID(rawValue: raw)) != nil { continue }
            let minted = mintedStoryRefs[raw] ?? StoryID()
            mintedStoryRefs[raw] = minted
            memory.storyRef = minted.rawValue
            validated.accepted[i] = .memory(memory)
        }
    }

    /// The pending memory card of this session a continuation names, or nil: a kept, dismissed
    /// or unknown card is never extended, so the new telling stands as its own card.
    private func pendingCard(named id: String?) throws -> Candidate? {
        guard let id, let card = try store.candidates.fetch(CandidateID(rawValue: id)),
              card.kind == .memory, card.status == .pending,
              let segment = try store.sessions.fetchSegment(card.segmentID), segment.sessionID == session else { return nil }
        return card
    }

    /// The memory an accepted card made or joined, when a continuation names a card that was kept.
    private func keptMemory(continuing id: String?) throws -> Memory? {
        guard let id, let card = try store.candidates.fetch(CandidateID(rawValue: id)), card.kind == .memory, card.status == .accepted else { return nil }
        return try store.memories.memory(createdFrom: card.id) ?? store.memories.memory(withSpanFrom: card.id)
    }

    /// Hint rows for a memory's collection and chapter phrases, waiting on the card `keyedTo`.
    private func hintRows(for memory: MemoryOut, keyedTo card: CandidateID,
                          row: (CandidateKind, String, Double, String?) -> Candidate) throws -> [Candidate] {
        var out: [Candidate] = []
        for (kind, phrase) in [(HintKind.collection, memory.collectionHint), (.chapter, memory.chapterHint), (.story, memory.storyTitleHint)] {
            guard let phrase = phrase?.trimmingCharacters(in: .whitespacesAndNewlines), !phrase.isEmpty else { continue }
            out.append(row(.hint, try CandidatePayload.encode(HintOut(kind: kind, phrase: phrase, memoryCandidateID: card.rawValue)), memory.confidence, nil))
        }
        return out
    }

    private static func describe(_ candidate: OutputValidator.ValidatedCandidate) throws -> (kind: CandidateKind, payload: String, confidence: Double) {
        switch candidate {
        case .memory(let m): return (.memory, try CandidatePayload.encode(m), m.confidence)
        case .mention(let m): return (m.kind == .person ? .person : .place, try CandidatePayload.encode(m), m.confidence)
        }
    }
}
