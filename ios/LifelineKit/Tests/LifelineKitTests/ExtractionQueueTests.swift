import Foundation
import Testing
@testable import LifelineKit

private struct Env {
    let db: AppDatabase, store: ExtractionStore, service: FakeExtractionService
    let session: SessionID, segments: [Segment], log: LogCollector
    init(texts: [String] = ["the garden had a pomegranate tree", "my sister Maya climbed it"], script: [Result<ExtractorOutput, ExtractionError>] = []) throws {
        db = try AppDatabase.inMemory()
        let sessions = SessionRepository(db)
        store = ExtractionStore(candidates: CandidateRepository(db), sessions: sessions, people: PeopleRepository(db),
                                memories: MemoryRepository(db), profile: ProfileRepository(db),
                                chapters: ChapterRepository(db), curiosity: CuriosityRepository(db), embeddings: EmbeddingRepository(db),
                                stories: StoryRepository(db), pairs: DuplicatePairRepository(db), entities: EntityRepository(db), tags: DomainTagRepository(db))
        (session, segments) = try StoreFixtures.session(in: sessions, segments: texts)
        service = FakeExtractionService(script)
        log = LogCollector()
    }
    func queue() -> ExtractionQueue {
        let log = self.log
        return ExtractionQueue(session: session, service: service, store: store, log: { log.append($0) })
    }
}

private func gardenOutput(quote: String = "had a pomegranate tree", people: [String] = []) -> ExtractorOutput {
    ExtractorOutput(memories: [MemoryOut(ref: "m1", title: "The pomegranate tree", quote: quote, segmentSpan: WordSpan(startWord: 2, endWord: 5),
                                         peopleRefs: people, placeText: nil, anchors: [], collectionHint: nil,
                                         chapterHint: nil, confidence: 0.9)],
                    mentions: [], flags: .none)
}

private func collect(_ events: AsyncStream<ExtractionEvent>, count: Int, timeoutMs: Int = 3_000) async -> [ExtractionEvent] {
    await withTaskGroup(of: [ExtractionEvent].self) { group in
        group.addTask { var out: [ExtractionEvent] = []; for await e in events { out.append(e); if out.count == count { break } }; return out }
        group.addTask { try? await Task.sleep(for: .milliseconds(timeoutMs)); return [] }
        let first = await group.next() ?? []
        group.cancelAll()
        return first
    }
}

@Test func segmentsAreExtractedInOrderAndStoredPending() async throws {
    let env = try Env(script: [.success(gardenOutput()), .success(ExtractorOutput(memories: [], mentions: [MentionOut(text: "Maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)], flags: .none))])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    await queue.enqueue(env.segments[1].id)
    let got = await collect(events, count: 2)
    guard got.count == 2, case .candidates(let first, let s0) = got[0], case .candidates(let second, let s1) = got[1] else {
        Issue.record("unexpected events \(got)"); return
    }
    #expect(s0 == env.segments[0].id && s1 == env.segments[1].id)
    #expect(first.count == 1 && first[0].kind == .memory && first[0].status == .pending && first[0].extractorVersion == "fake")
    #expect(second.count == 1 && second[0].kind == .person)
    #expect(env.service.requests.map(\.segmentText) == env.segments.map(\.text))
    #expect(env.service.requests[1].packet.previousSegments == [env.segments[0].text])
    #expect(try env.store.sessions.fetchSegment(env.segments[0].id)?.status == .extracted)
    #expect(try env.store.candidates.pending(in: env.session).count == 2)
}

@Test func rejectedCandidatesAreStoredNotShown() async throws {
    let env = try Env(script: [.success(gardenOutput(quote: "we drove to Yosemite"))])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let got = await collect(events, count: 1)
    guard case .candidates(let shown, _)? = got.first else { Issue.record("no event"); return }
    #expect(shown.isEmpty)
    let stored = try env.store.candidates.candidates(for: env.segments[0].id)
    #expect(stored.count == 1 && stored[0].status == .dismissed && stored[0].rejection?.contains("quote") == true)
}

@Test func failedRequestLeavesSegmentPendingAndRecordingContinues() async throws {
    let env = try Env(script: [.failure(.network("offline")), .success(gardenOutput())])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    await queue.enqueue(env.segments[1].id)
    let got = await collect(events, count: 2)
    guard got.count == 2, case .failed(let failed, .network) = got[0], case .candidates = got[1] else { Issue.record("events \(got)"); return }
    #expect(failed == env.segments[0].id)
    #expect(try env.store.sessions.fetchSegment(env.segments[0].id)?.status == .pending)
    #expect(try env.store.sessions.fetchSegment(env.segments[1].id)?.status == .extracted)
}

@Test func drainRetriesPendingOnce() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree"], script: [.failure(.server(status: 500)), .success(gardenOutput())])
    let queue = env.queue()
    await queue.enqueue(env.segments[0].id)
    await queue.drain()
    #expect(env.service.requests.count == 2)
    #expect(try env.store.sessions.fetchSegment(env.segments[0].id)?.status == .extracted)
}

@Test func missingKeyDisablesExtractionQuietly() async throws {
    let env = try Env(script: [.failure(.noKey), .failure(.noKey), .failure(.noKey)])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    await queue.enqueue(env.segments[1].id)
    let got = await collect(events, count: 2)
    #expect(got.count == 2)
    for e in got { guard case .failed(_, .noKey) = e else { Issue.record("expected noKey, got \(e)"); continue } }
    await queue.drain()
    #expect(env.service.requests.count == 1, "after the first missing-key failure nothing else is sent, drain included")
    #expect(try env.store.sessions.segments(in: env.session, status: .pending).count == 2)
}

@Test func alreadyExtractedSegmentIsSkipped() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree"], script: [.success(gardenOutput())])
    try env.store.candidates.insert(StoreFixtures.candidate(env.segments[0].id, version: "fake"))
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let got = await collect(events, count: 1)
    guard case .skipped(let id)? = got.first else { Issue.record("events \(got)"); return }
    #expect(id == env.segments[0].id && env.service.requests.isEmpty)
}

@Test func flagsAreStoredAsAFlagCandidate() async throws {
    var output = gardenOutput()
    output.flags = Flags(seriousDisclosure: true, wantsToStop: false, wantsToChangeSubject: false)
    let env = try Env(texts: ["the garden had a pomegranate tree"], script: [.success(output)])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let got = await collect(events, count: 2)
    #expect(got.contains { if case .flags(let f, _) = $0 { f.seriousDisclosure } else { false } })
    let stored = try env.store.candidates.candidates(for: env.segments[0].id)
    #expect(stored.map(\.kind) == [.memory, .flag])
    #expect(stored[1].payload.contains("\"disclosure\":\"past\""))
}

@Test func profileFreeTextAndPeopleReachThePacket() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree"], script: [.success(gardenOutput())])
    try env.store.profile.save(Profile(displayName: "Jake", birthDate: nil, birthPlaceText: nil, freeText: "I grew up in Fresno", updatedAt: .now))
    _ = try env.store.people.insertPerson(displayName: "Maya")
    let queue = env.queue()
    await queue.enqueue(env.segments[0].id)
    await queue.drain()
    let packet = try #require(env.service.requests.first?.packet)
    #expect(packet.profileFreeText == "I grew up in Fresno")
    #expect(packet.people.map(\.name) == ["Maya"])
}

@Test func disclosureSegmentShowsNoMemoryCardAnywhere() async throws {
    var output = gardenOutput()
    output.flags = Flags(seriousDisclosure: true, wantsToStop: false, wantsToChangeSubject: false)
    output.mentions = [MentionOut(text: "my sister", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)]
    let env = try Env(texts: ["the garden had a pomegranate tree and my sister"], script: [.success(output)])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    var cards = CardQueue()
    for event in await collect(events, count: 2) { cards.apply(event) }
    #expect(cards.suppressed)
    #expect(!cards.cards.contains { if case .memory = $0 { true } else { false } }, "the disclosure itself is never offered as a memory")
    let stored = try env.store.candidates.candidates(for: env.segments[0].id)
    let memory = try #require(stored.first { $0.kind == .memory })
    #expect(memory.status == .dismissed && memory.rejection?.contains("disclosure") == true)
    #expect(try env.store.candidates.pending(in: env.session).map(\.kind) == [.person], "nothing waits in the detail screen except the name")
}

@Test func knownNameMentionIsResolvedWithoutACard() async throws {
    let env = try Env(texts: ["my sister Maya climbed it"], script: [.success(ExtractorOutput(memories: [], mentions: [MentionOut(text: "maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)], flags: .none))])
    let maya = try env.store.people.insertPerson(displayName: "Maya")
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    guard case .candidates(let shown, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    #expect(shown.isEmpty, "a name the app knows is not a question")
    let mentions = try env.store.people.mentions(in: env.segments[0].id)
    #expect(mentions.count == 1 && mentions[0].status == .resolved && mentions[0].personID == maya.id)
    #expect(try env.store.candidates.candidates(for: env.segments[0].id).first?.status == .accepted)
}

@Test func skippedSegmentIsMarkedExtracted() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree"])
    try env.store.candidates.insert(StoreFixtures.candidate(env.segments[0].id, version: "fake"))
    let queue = env.queue()
    await queue.enqueue(env.segments[0].id)
    await queue.drain()
    #expect(try env.store.sessions.fetchSegment(env.segments[0].id)?.status == .extracted, "a half-written segment is not retried forever")
}

@Test func drainRetriesOnlyTransientFailures() async throws {
    let env = try Env(script: [.failure(.unauthorized), .failure(.network("offline")), .success(gardenOutput())])
    let queue = env.queue()
    await queue.enqueue(env.segments[0].id)
    await queue.enqueue(env.segments[1].id)
    await queue.drain()
    #expect(env.service.requests.map(\.segmentText) == [env.segments[0].text, env.segments[1].text, env.segments[1].text])
    #expect(try env.store.sessions.fetchSegment(env.segments[0].id)?.status == .pending)
    #expect(try env.store.sessions.fetchSegment(env.segments[1].id)?.status == .extracted)
}

@Test func drainGivesUpAtItsDeadline() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree"], script: [.success(gardenOutput())])
    env.service.delay.withLock { $0 = .seconds(5) }
    let queue = ExtractionQueue(session: env.session, service: env.service, store: env.store, drainDeadline: .milliseconds(300))
    await queue.enqueue(env.segments[0].id)
    let clock = ContinuousClock()
    let elapsed = await clock.measure { await queue.drain() }
    #expect(elapsed < .seconds(2), "Stop must not wait on a slow network: \(elapsed)")
    #expect(try env.store.sessions.fetchSegment(env.segments[0].id)?.status == .pending)
}

private let blankOutput = ExtractorOutput(memories: [MemoryOut(ref: "", kind: .other, title: "", quote: "", segmentSpan: WordSpan(startWord: 0, endWord: 0), peopleRefs: [],
                                                               placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0)],
                                          mentions: [], flags: .none)

@Test func aBlankAnswerIsRetriedOnceBeforeItCounts() async throws {
    // The API once returned a memory with every field empty and nothing else. That is noise, not an answer.
    let env = try Env(texts: ["the garden had a pomegranate tree"], script: [.success(blankOutput), .success(gardenOutput())])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    guard case .candidates(let shown, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    #expect(env.service.requests.count == 2, "asked again")
    #expect(shown.count == 1 && shown[0].kind == .memory)
    #expect(try env.store.candidates.candidates(for: env.segments[0].id).count == 1, "the blank answer leaves no rows")
}

@Test func twoBlankAnswersInARowAreStoredAsAFailure() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree"], script: [.success(blankOutput), .success(blankOutput)])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    guard case .failed(_, let error)? = await collect(events, count: 1).first else { Issue.record("expected a failure"); return }
    #expect(error == .badOutput("blank answer"))
    #expect(try env.store.sessions.fetchSegment(env.segments[0].id)?.status == .pending, "left for a later run, like any failure")
}

@Test func queueAsksTheMatcherForRelatedMemories() async throws {
    let env = try Env(texts: ["grew up in an orange house"], script: [.success(gardenOutput())])
    // A memory from another session whose vector equals the new segment's.
    let (_, earlier) = try StoreFixtures.session(in: env.store.sessions, segments: ["we lived in an orange house"])
    let c = StoreFixtures.candidate(earlier[0].id)
    try env.store.candidates.insert(c)
    let a = StoreFixtures.memory(from: c.id, title: "Orange house")
    try env.store.memories.insert(a, spans: [MemorySpan(memoryID: a.id, segmentID: earlier[0].id, startMs: 0, endMs: 500, order: 0)], people: [], places: [], anchors: [])
    let table = [MemoryMatcher.text(title: a.title, quote: a.summaryQuote): [Float]([1, 0]), env.segments[0].text: [1, 0]]
    let matcher = MemoryMatcher(store: env.store, embedder: FakeEmbedder(table: table))
    try matcher.index(a)
    let queue = ExtractionQueue(session: env.session, service: env.service, store: env.store, matcher: matcher)
    await queue.enqueue(env.segments[0].id)
    await queue.drain()
    let request = try #require(env.service.requests.first)
    #expect(request.packet.memories.first?.id == a.id.rawValue && request.packet.memories.first?.related == true)
}

@Test func extractorSameAsStillSuggestsWithoutVectors() async throws {
    let env = try Env(texts: ["grew up in an orange house"])
    let (_, earlier) = try StoreFixtures.session(in: env.store.sessions, segments: ["we lived in an orange house"])
    let c = StoreFixtures.candidate(earlier[0].id)
    try env.store.candidates.insert(c)
    let a = StoreFixtures.memory(from: c.id, title: "Orange house")
    try env.store.memories.insert(a, spans: [MemorySpan(memoryID: a.id, segmentID: earlier[0].id, startMs: 0, endMs: 500, order: 0)], people: [], places: [], anchors: [])
    var out = gardenOutput()
    out.memories[0].sameAsMemoryIDs = [a.id.rawValue]
    env.service.push(.success(out))
    let matcher = MemoryMatcher(store: env.store, embedder: nil)
    let queue = ExtractionQueue(session: env.session, service: env.service, store: env.store, matcher: matcher)
    await queue.enqueue(env.segments[0].id)
    await queue.drain()
    let stored = try #require(try env.store.candidates.candidates(for: env.segments[0].id).first)
    let card = try #require(CandidatePayload.memory(stored))
    let match = try #require(try matcher.suggestion(for: card, extractorSameAs: card.sameAsMemoryID.map(MemoryID.init(rawValue:))))
    #expect(match.memoryID == a.id && match.source == .extractor)
}

@Test func queuePacketCarriesPendingCardsStoriesAndPeopleByRelevance() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree", "my sister Maya climbed it"], script: [.success(gardenOutput()), .success(gardenOutput())])
    // Two people: Zed was linked to a memory; Maya is named in the current segment and goes first.
    let zed = try env.store.people.insertPerson(displayName: "Zed")
    _ = try env.store.people.insertPerson(displayName: "Maya")
    let (_, earlier) = try StoreFixtures.session(in: env.store.sessions, segments: ["we lived in an orange house"])
    let old = try StoreFixtures.memory(in: env.store.memories, candidates: env.store.candidates, segment: earlier[0].id, title: "Old")
    try env.store.memories.link(zed.id, to: old.id, roleText: nil)
    let story = try env.store.stories.insert(title: "The thread", chapterID: nil)
    try env.store.stories.add(memory: old.id, to: story.id)
    let matcher = MemoryMatcher(store: env.store, embedder: FakeEmbedder(table: [MemoryMatcher.text(title: old.title, quote: old.summaryQuote): [Float]([1, 0]), env.segments[1].text: [1, 0]]))
    try matcher.index(old)
    let queue = ExtractionQueue(session: env.session, service: env.service, store: env.store, matcher: matcher)
    await queue.enqueue(env.segments[0].id)
    await queue.enqueue(env.segments[1].id)
    await queue.drain()
    let packets = env.service.requests.map(\.packet)
    #expect(packets.count == 2)
    let second = packets[1]
    #expect(second.pending.map(\.title) == ["The pomegranate tree"], "the first segment's card is still pending when the second is extracted")
    #expect(second.people.map(\.name) == ["Maya", "Zed"], "named in this segment first, then by most recent link")
    #expect(second.stories.map(\.title) == ["The thread"], "stories of the related memories ride along")
}

// MARK: - M5 continuation

private func continuation(of candidate: CandidateID, anchors: [AnchorOut] = [], people: [String] = [], collectionHint: String? = nil) -> ExtractorOutput {
    ExtractorOutput(memories: [MemoryOut(ref: "m2", title: "The pomegranate tree", quote: "my sister Maya climbed it", segmentSpan: WordSpan(startWord: 0, endWord: 6),
                                         peopleRefs: people, placeText: nil, anchors: anchors, continuesCandidateID: candidate.rawValue,
                                         collectionHint: collectionHint, chapterHint: nil, confidence: 0.9)],
                    mentions: [], flags: .none)
}

private func firstCard(_ events: [ExtractionEvent]) -> Candidate? {
    guard case .candidates(let cards, _)? = events.first else { return nil }
    return cards.first
}

@Test func continuationExtendsThePendingCardAndKeepMakesOneMemory() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree", "my sister Maya climbed it in 1998"], script: [.success(gardenOutput())])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let a = try #require(firstCard(await collect(events, count: 1)))
    env.service.push(.success(continuation(of: a.id, anchors: [AnchorOut(phrase: "in 1998", relation: .absolute, targetText: nil, value: "1998")], people: ["Maya"])))
    await queue.enqueue(env.segments[1].id)
    let again = try #require(firstCard(await collect(events, count: 1)))
    #expect(again.id == a.id, "the first card is emitted again, not a new one")
    let payload = try #require(CandidatePayload.memory(again))
    #expect(payload.extraSpans == [ExtraSpan(segmentID: env.segments[1].id.rawValue, startWord: 0, endWord: 6)])
    let pending = try env.store.candidates.pending(in: env.session).filter { $0.kind == .memory }
    #expect(pending.map(\.id) == [a.id])
    let rows = try env.store.candidates.continuations(of: a.id)
    #expect(rows.count == 1 && rows[0].status == .superseded && rows[0].rejection == "continues \(a.id.rawValue)")

    let actions = CandidateActions(store: env.store)
    let kept = try actions.acceptMemory(again)
    let spans = try env.store.memories.spans(of: kept.memory.id)
    #expect(spans.count == 2 && spans[1].continuesOrder == 0 && spans[1].segmentID == env.segments[1].id && spans[1].order == 1)
    let words = try env.store.sessions.words(in: env.segments[1].id)
    #expect(spans[1].startMs == words[0].startMs && spans[1].endMs == words[6].endMs)
    #expect(try env.store.memories.anchors(of: kept.memory.id).map(\.phrase) == ["in 1998"])
    #expect(kept.newMentions.map(\.text) == ["Maya"])
    #expect(try env.store.candidates.fetch(rows[0].id)?.status == .accepted)
}

@Test func continuationAfterDismissIsItsOwnCard() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree", "my sister Maya climbed it in 1998"], script: [.success(gardenOutput())])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let a = try #require(firstCard(await collect(events, count: 1)))
    try CandidateActions(store: env.store).dismiss(a)
    env.service.push(.success(continuation(of: a.id)))
    await queue.enqueue(env.segments[1].id)
    let b = try #require(firstCard(await collect(events, count: 1)))
    #expect(b.id != a.id && b.status == .pending && b.segmentID == env.segments[1].id)
    #expect(try env.store.candidates.fetch(a.id)?.status == .dismissed)
    #expect(CandidatePayload.memory(b)?.extraSpans.isEmpty == true)
}

@Test func continuationHintIsKeyedToTheFirstCard() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree", "my sister Maya climbed it in 1998"], script: [.success(gardenOutput())])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let a = try #require(firstCard(await collect(events, count: 1)))
    env.service.push(.success(continuation(of: a.id, collectionHint: "every summer")))
    await queue.enqueue(env.segments[1].id)
    guard case .candidates(let emitted, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    let hint = try #require(emitted.compactMap(CandidatePayload.hint).first)
    #expect(hint.memoryCandidateID == a.id.rawValue && hint.phrase == "every summer")
    let actions = CandidateActions(store: env.store)
    _ = try actions.acceptMemory(try #require(emitted.first { $0.id == a.id }))
    let waiting = CardQueue.waitingCards(pending: try env.store.candidates.pending(in: env.session),
                                         statusOf: { (try? env.store.candidates.fetch($0))?.status })
    #expect(waiting.contains { if case .hint = $0 { true } else { false } })
}

// MARK: - M5 stories

private func storied(_ refs: [(title: String, ref: String?, hint: String?)], quote: String = "the garden") -> ExtractorOutput {
    ExtractorOutput(memories: refs.enumerated().map { i, r in
        MemoryOut(ref: "m\(i)", title: r.title, quote: quote, segmentSpan: WordSpan(startWord: 0, endWord: 1), peopleRefs: [], placeText: nil,
                  anchors: [], storyRef: r.ref, storyTitleHint: r.hint, collectionHint: nil, chapterHint: nil, confidence: 0.9)
    }, mentions: [], flags: .none)
}

@Test func queueMintsOneStoryIDPerNewRef() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree", "my sister Maya climbed it"],
                      script: [.success(storied([("One", "s1", "The garden days"), ("Two", "s1", nil), ("Three", "other", nil)]))])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    guard case .candidates(let cards, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    let outs = cards.compactMap(CandidatePayload.memory)
    #expect(outs.count == 3)
    let refs = outs.compactMap(\.storyRef)
    #expect(refs.count == 3 && refs[0] == refs[1] && refs[0] != refs[2], "one fresh id per raw ref")
    #expect(UUID(uuidString: refs[0]) != nil && UUID(uuidString: refs[2]) != nil)
    let hints = cards.compactMap(CandidatePayload.hint)
    #expect(hints.map(\.kind) == [.story] && hints[0].phrase == "The garden days" && hints[0].memoryCandidateID == cards[0].id.rawValue)
    // A later segment naming the minted id, or the raw ref again, keeps it.
    env.service.push(.success(storied([("Four", refs[0], nil), ("Five", "s1", nil)], quote: "my sister")))
    await queue.enqueue(env.segments[1].id)
    guard case .candidates(let later, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    #expect(later.compactMap(CandidatePayload.memory).map(\.storyRef) == [refs[0], refs[0]])
}

// MARK: - Review fixes

@Test func continuationHintCanBeAcceptedAfterKeep() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree", "my sister Maya climbed it in 1998"], script: [.success(gardenOutput())])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let a = try #require(firstCard(await collect(events, count: 1)))
    env.service.push(.success(continuation(of: a.id, collectionHint: "every summer")))
    await queue.enqueue(env.segments[1].id)
    guard case .candidates(let emitted, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    let actions = CandidateActions(store: env.store)
    let kept = try actions.acceptMemory(try #require(emitted.first { $0.id == a.id })).memory
    let hint = try #require(emitted.first { $0.kind == .hint })
    guard case .collection(let collection) = try actions.acceptHint(hint) else { Issue.record("expected a collection"); return }
    #expect(try env.store.chapters.members(of: collection.id).map(\.id) == [kept.id])
}

@Test func continuationAfterKeepIsASameAsCard() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree", "my sister Maya climbed it in 1998"], script: [.success(gardenOutput())])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let a = try #require(firstCard(await collect(events, count: 1)))
    let kept = try CandidateActions(store: env.store).acceptMemory(a).memory
    env.service.push(.success(continuation(of: a.id)))
    await queue.enqueue(env.segments[1].id)
    let b = try #require(firstCard(await collect(events, count: 1)))
    #expect(b.id != a.id && b.status == .pending)
    #expect(CandidatePayload.memory(b)?.sameAsMemoryIDs == [kept.id.rawValue], "the telling's memory is named, so the card offers Same story")
}

@Test func aPersonNamedOnlyInAContinuationIsLinkedWhenResolved() async throws {
    let env = try Env(texts: ["the garden had a pomegranate tree", "my sister Maya climbed it in 1998 with Marcel"], script: [.success(gardenOutput())])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let a = try #require(firstCard(await collect(events, count: 1)))
    env.service.push(.success(continuation(of: a.id, people: ["Marcel"])))
    await queue.enqueue(env.segments[1].id)
    let again = try #require(firstCard(await collect(events, count: 1)))
    let actions = CandidateActions(store: env.store)
    let kept = try actions.acceptMemory(again)
    let mention = try #require(kept.newMentions.first { $0.text == "Marcel" })
    _ = try actions.resolveMention(mention.id, to: .new(displayName: "Marcel"))
    #expect(try env.store.memories.people(of: kept.memory.id).map(\.displayName) == ["Marcel"])
}
