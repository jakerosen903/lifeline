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
                                stories: StoryRepository(db), pairs: DuplicatePairRepository(db), entities: EntityRepository(db), tags: DomainTagRepository(db), photos: PhotoRepository(db),
                                personLinks: PersonLinkRepository(db))
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
    #expect(second.isEmpty, "a name no memory carries goes to the People queue, not the session")
    #expect(env.service.requests.map(\.segmentText) == env.segments.map(\.text))
    #expect(env.service.requests[1].packet.previousSegments == [env.segments[0].text])
    #expect(try env.store.sessions.fetchSegment(env.segments[0].id)?.status == .extracted)
    #expect(try env.store.candidates.pending(in: env.session).count == 1)
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
    #expect(try env.store.candidates.pending(in: env.session).isEmpty, "nothing waits in the detail screen")
    #expect(try env.store.people.mentions(in: env.segments[0].id).map(\.status) == [.unresolved], "the name waits in the People queue")
}

@Test func nameNoMemoryCarriesBecomesAnOpenMention() async throws {
    var output = gardenOutput()
    output.mentions = [MentionOut(text: "Dara", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8, relationText: "my cousin")]
    let env = try Env(texts: ["the garden had a pomegranate tree with Dara"], script: [.success(output)])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    guard case .candidates(let shown, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    #expect(shown.map(\.kind) == [.memory], "the name is not held under a memory that does not name it")
    let mentions = try env.store.people.mentions(in: env.segments[0].id)
    #expect(mentions.map(\.text) == ["Dara"] && mentions.map(\.status) == [.unresolved] && mentions.first?.relationText == "my cousin")
    #expect(try env.store.people.mentions(status: .unresolved).map(\.id) == mentions.map(\.id))
    #expect(try env.store.candidates.candidates(for: env.segments[0].id).first { $0.kind == .person }?.status == .accepted)
}

// Task 3 (plan decision 5): a name a memory carries is a record; the kept card shows the person.
@Test func nameAMemoryCarriesIsARecordTheKeptCardLinks() async throws {
    var output = gardenOutput(people: ["Maya"])
    output.mentions = [MentionOut(text: "maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)]
    let env = try Env(texts: ["the garden had a pomegranate tree Maya climbed"], script: [.success(output)])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    guard case .candidates(let shown, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    #expect(shown.map(\.kind) == [.memory], "Keep links the name; it is not a question of its own")
    #expect(try env.store.people.mentions(in: env.segments[0].id).isEmpty)
    #expect(try env.store.candidates.pending(in: env.session).map(\.kind) == [.memory])
    #expect(try env.store.candidates.candidates(for: env.segments[0].id).first { $0.kind == .person }?.status == .accepted)
}

// Task 3: the app no longer answers a known name itself; nothing carries it, so it waits for the owner.
@Test func aKnownNameNoMemoryCarriesStillWaitsForTheOwner() async throws {
    let env = try Env(texts: ["my sister Maya climbed it"], script: [.success(ExtractorOutput(memories: [], mentions: [MentionOut(text: "maya", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)], flags: .none))])
    let maya = try env.store.people.insertPerson(displayName: "Maya")
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    guard case .candidates(let shown, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    #expect(shown.isEmpty, "with no memory to wait under, it goes to the People queue")
    let mentions = try env.store.people.mentions(in: env.segments[0].id)
    #expect(mentions.count == 1 && mentions[0].status == .unresolved && mentions[0].personID == nil)
    #expect(try env.store.people.aliases(of: maya.id).map(\.text) == ["Maya"], "nothing was learned about Maya")
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
    #expect(kept.newMentions.isEmpty, "Task 3: Maya is a new person, not a mention")
    #expect(try env.store.memories.people(of: kept.memory.id).map(\.displayName) == ["Maya"])
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
    let waiting = CardQueue.waiting(pending: try env.store.candidates.pending(in: env.session),
                                    segmentMemories: { (try? env.store.candidates.candidates(for: $0)) ?? [] },
                                    candidate: { try? env.store.candidates.fetch($0) })
    guard case .kept(let kept)? = waiting.cards.first(where: { $0.id == a.id.rawValue }) else { Issue.record("expected a kept card, got \(waiting.cards)"); return }
    #expect(kept.followUps.contains { if case .hint = $0 { true } else { false } }, "the continuation's hint waits under the first card, kept")
    #expect(kept.title == CandidatePayload.memory(a)?.title && !kept.title.isEmpty)
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

// Task 3: Keep links a name the continuation says; it no longer waits for an answer.
@Test func aPersonNamedOnlyInAContinuationIsLinkedOnKeep() async throws {
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
    #expect(kept.newMentions.isEmpty)
    #expect(try env.store.memories.people(of: kept.memory.id).map(\.displayName) == ["Marcel"])
    #expect(try env.store.entities.links(of: kept.memory.id).filter { $0.entity.type == .person }.map(\.link.origin) == [.new])
}

// PC-b, PB10: nothing from a contact reaches the model, through the real packet. Robyn is made from a contact
// by a fact card (so she has no moment and a curiosity question); Tomas is made from a contact by a moment and
// then renamed. The packet of a later segment holds neither contact's family name anywhere.
@Test func noContactNameReachesTheRealPacket() async throws {
    let texts = ["Robyn is the kindest person I know", "Tomas and I painted the fence", "we drove to the lake"]
    let env = try Env(texts: texts, script: [.success(ExtractorOutput(memories: [], mentions: [], flags: .none))])
    let contacts = [PersonGuess.Contact(identifier: "c-vale", fullName: "Robyn Vale", givenName: "Robyn", nickname: ""),
                    PersonGuess.Contact(identifier: "c-okafor", fullName: "Tomas Okafor", givenName: "Tomas", nickname: "")]
    var keep = CandidateActions(store: env.store)
    keep.contactsForGuess = { contacts }
    func card(_ index: Int, kind: MemoryKind, person: String) throws -> Candidate {
        let text = texts[index]
        let out = MemoryOut(ref: "m\(index)", kind: kind, title: "A title", quote: text,
                            segmentSpan: WordSpan(startWord: 0, endWord: text.split(separator: " ").count - 1),
                            peopleRefs: [person], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let row = StoreFixtures.candidate(env.segments[index].id, ordinal: 0, payload: try CandidatePayload.encode(out))
        try env.store.candidates.insert(row)
        return row
    }
    let fact = try keep.acceptMemory(try card(0, kind: .fact, person: "Robyn"), joinStory: false)
    let moment = try keep.acceptMemory(try card(1, kind: .event, person: "Tomas"), joinStory: false)
    let robyn = try #require(try env.store.personLinks.links(of: fact.memory.id).first?.person)
    let tomas = try #require(try env.store.personLinks.links(of: moment.memory.id).first?.person)
    #expect(robyn.contactIdentifier == "c-vale" && tomas.contactIdentifier == "c-okafor")
    try env.store.people.rename(tomas.id, to: "Tommy")
    _ = try ResolverRunner(store: env.store).run()
    #expect(try env.store.curiosity.open().contains { $0.text == "Is there one time with Robyn that stands out?" })

    let queue = env.queue()
    await queue.enqueue(env.segments[2].id)
    await queue.drain()
    let packet = try #require(env.service.requests.first?.packet)
    #expect(Set(packet.people.map(\.name)) == ["Robyn", "Tommy"])
    let text = String(decoding: try packet.encodedJSON(), as: UTF8.self)
    #expect(!text.contains("Vale") && !text.contains("Okafor"), "no contact's name in the packet: people, curiosity and all")
    #expect(text.contains("Is there one time with Robyn that stands out?"))
}

// MARK: - PC-d Task 2: the packet carries the handles of the recording so far

private func handleCard(_ segment: SegmentID, ordinal: Int = 0, _ people: [PersonOut], status: CandidateStatus = .pending,
                        in store: ExtractionStore) throws {
    let out = MemoryOut(ref: "m1", kind: .event, title: "A card", quote: "a card", segmentSpan: WordSpan(startWord: 0, endWord: 1),
                        peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9,
                        personHandles: people.map(\.handle), handlePeople: people)
    let card = StoreFixtures.candidate(segment, ordinal: ordinal, payload: try CandidatePayload.encode(out))
    try store.candidates.insert(card)
    if status != .pending { try store.candidates.setStatus(card.id, status) }
}

private func packetOfLastSegment(_ env: Env) async throws -> ContextPacket? {
    env.service.push(.success(ExtractorOutput(memories: [], mentions: [], flags: .none)))
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments.last!.id)
    _ = await collect(events, count: 1)
    return env.service.requests.first?.packet
}

private let threeSegments = ["Robyn moved in that fall", "my roommate cooked every night", "we painted the kitchen"]

@Test func oneHandleSaidTwoWaysIsOneEntryWithBothNames() async throws {
    let env = try Env(texts: threeSegments)
    try handleCard(env.segments[0].id, [PersonOut(handle: "p1", saidName: "Robyn", relationText: nil, personID: nil)], in: env.store)
    try handleCard(env.segments[1].id, [PersonOut(handle: "p1", saidName: "my roommate", relationText: "roommate", personID: nil)], in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople == [.init(handle: "p1", saidNames: ["Robyn", "my roommate"], relation: "roommate", personID: nil)])
}

@Test func theCurrentSegmentAndAnotherSessionAddNoHandles() async throws {
    let env = try Env(texts: threeSegments)
    try handleCard(env.segments[2].id, [PersonOut(handle: "p1", saidName: "Robyn", relationText: nil, personID: nil)], in: env.store)
    let (_, other) = try StoreFixtures.session(in: env.store.sessions, segments: ["Theo came by", "Theo left"])
    try handleCard(other[0].id, [PersonOut(handle: "p2", saidName: "Theo", relationText: nil, personID: nil)], in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople.isEmpty)
}

@Test func aDismissedCardAddsNoHandlesButKeptAndWaitingCardsDo() async throws {
    let env = try Env(texts: threeSegments)
    try handleCard(env.segments[0].id, ordinal: 0, [PersonOut(handle: "p1", saidName: "Robyn", relationText: nil, personID: nil)], status: .accepted, in: env.store)
    try handleCard(env.segments[0].id, ordinal: 1, [PersonOut(handle: "p2", saidName: "Theo", relationText: nil, personID: nil)], status: .dismissed, in: env.store)
    try handleCard(env.segments[1].id, [PersonOut(handle: "p3", saidName: "Ines", relationText: nil, personID: nil)], in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople.map(\.handle) == ["p1", "p3"])
}

@Test func aSupersededContinuationRowAddsNoHandlesByItself() async throws {
    let env = try Env(texts: threeSegments)
    try handleCard(env.segments[1].id, [PersonOut(handle: "p1", saidName: "Robyn", relationText: nil, personID: nil)], status: .superseded, in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople.isEmpty)
}

// MARK: - PC-d Task 7b: a person mention with a handle also gives the recording a handle

private func handleMention(_ segment: SegmentID, ordinal: Int = 0, _ text: String, handle: String?, relation: String? = nil,
                           status: CandidateStatus = .pending, in store: ExtractionStore) throws {
    let out = MentionOut(text: text, kind: .person, confidence: 0.8, relationText: relation, handle: handle)
    let row = StoreFixtures.candidate(segment, ordinal: ordinal, kind: .person, payload: try CandidatePayload.encode(out))
    try store.candidates.insert(row)
    if status != .pending { try store.candidates.setStatus(row.id, status) }
}

private let nameAlone = ["we baked bread at the shop", "Ottilie.", "she taught me to play cards"]

@Test func aWaitingPersonMentionWithAHandleGivesTheNextSegmentThatHandle() async throws {
    let env = try Env(texts: Array(nameAlone.prefix(2)))
    try handleMention(env.segments[0].id, "Ottilie", handle: "p1", in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople == [.init(handle: "p1", saidNames: ["Ottilie"], relation: nil, personID: nil)])
}

@Test func aKeptPersonMentionGivesItsHandleAndItsRelation() async throws {
    let env = try Env(texts: Array(nameAlone.prefix(2)))
    try handleMention(env.segments[0].id, "Ottilie", handle: "p1", relation: "my aunt", status: .accepted, in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople == [.init(handle: "p1", saidNames: ["Ottilie"], relation: "my aunt", personID: nil)])
}

@Test func aDismissedMentionOrAMentionWithNoHandleAddsNothing() async throws {
    let env = try Env(texts: Array(nameAlone.prefix(2)))
    try handleMention(env.segments[0].id, ordinal: 0, "Ottilie", handle: "p1", status: .dismissed, in: env.store)
    try handleMention(env.segments[0].id, ordinal: 1, "Ottilie", handle: nil, in: env.store)
    try handleMention(env.segments[0].id, ordinal: 2, "Ottilie", handle: "", in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople.isEmpty)
}

@Test func aMentionOfTheCurrentSegmentOrAnotherSessionAddsNothing() async throws {
    let env = try Env(texts: Array(nameAlone.prefix(2)))
    try handleMention(env.segments[1].id, "Ottilie", handle: "p1", in: env.store)
    let (_, other) = try StoreFixtures.session(in: env.store.sessions, segments: ["Theo came by", "Theo left"])
    try handleMention(other[0].id, "Theo", handle: "p2", in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople.isEmpty)
}

@Test func aCardAndALaterMentionOfOneHandleFoldInTheOrderSaid() async throws {
    let env = try Env(texts: ["Robyn moved in that fall", "Rob.", "we painted the kitchen"])
    try handleCard(env.segments[0].id, [PersonOut(handle: "p1", saidName: "Robyn", relationText: nil, personID: nil)], in: env.store)
    try handleMention(env.segments[1].id, "Rob", handle: "p1", relation: "my roommate", in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople == [.init(handle: "p1", saidNames: ["Robyn", "Rob"], relation: "my roommate", personID: nil)])
}

// Rule 1: the cards' handles come first, then the handles only a mention gives. Said names keep the order said.
@Test func theCardsHandlesComeBeforeAHandleOnlyAMentionGives() async throws {
    let env = try Env(texts: ["Ottilie.", "Robyn moved in and Ottilie came too", "we painted the kitchen"])
    try handleMention(env.segments[0].id, "Ottilie", handle: "p2", in: env.store)
    try handleMention(env.segments[0].id, ordinal: 1, "Ines", handle: "p3", in: env.store)
    try handleCard(env.segments[1].id, [PersonOut(handle: "p1", saidName: "Robyn", relationText: nil, personID: nil),
                                        PersonOut(handle: "p2", saidName: "Ottie", relationText: nil, personID: nil)], in: env.store)
    let packet = try #require(try await packetOfLastSegment(env))
    #expect(packet.recordingPeople.map(\.handle) == ["p1", "p2", "p3"])
    #expect(packet.recordingPeople[1].saidNames == ["Ottilie", "Ottie"])
}

// End to end: a segment that is a name alone gives only a mention; "she" in the next segment follows its handle.
@Test func aCardThatFollowsAHandleOnlyAMentionGaveStoresThatPerson() async throws {
    let first = ExtractorOutput(people: [PersonOut(handle: "p1", saidName: "Ottilie", relationText: nil, personID: nil)], memories: [],
                                mentions: [MentionOut(text: "Ottilie", kind: .person, confidence: 0.8, handle: "p1")], flags: .none)
    let second = ExtractorOutput(memories: [MemoryOut(ref: "m1", kind: .event, title: "Cards", quote: "she taught me to play cards",
                                                      segmentSpan: WordSpan(startWord: 0, endWord: 5), peopleRefs: [], placeText: nil,
                                                      anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9, personHandles: ["p1"])],
                                 mentions: [], flags: .none)
    let env = try Env(texts: ["Ottilie.", "she taught me to play cards"], script: [.success(first), .success(second)])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    _ = await collect(events, count: 1)
    await queue.enqueue(env.segments[1].id)
    let card = try #require(firstCard(await collect(events, count: 1)))
    #expect(env.service.requests.last?.packet.recordingPeople.map(\.handle) == ["p1"])
    let payload = try #require(CandidatePayload.memory(card))
    #expect(payload.handlePeople.map(\.handle) == ["p1"])
    #expect(payload.handlePeople.first?.saidName == "Ottilie")
}

// MARK: - PC-d Task 3: the card stores its people

private let robynP1 = PersonOut(handle: "p1", saidName: "Robyn", relationText: "my roommate", personID: nil)

private func handleOutput(quote: String, span: WordSpan, continues: CandidateID? = nil, mentions: [MentionOut] = []) -> ExtractorOutput {
    ExtractorOutput(people: [robynP1],
                    memories: [MemoryOut(ref: "m1", kind: .event, title: "Robyn moved in", quote: quote, segmentSpan: span, peopleRefs: [],
                                         placeText: nil, anchors: [], continuesCandidateID: continues?.rawValue, collectionHint: nil, chapterHint: nil,
                                         confidence: 0.9, personHandles: ["p1"])],
                    mentions: mentions, flags: .none)
}

@Test func theStoredCardHoldsThePeopleOfItsHandlesAndTheirSaidNames() async throws {
    let env = try Env(texts: ["my roommate Robyn moved in that fall"], script: [.success(handleOutput(quote: "Robyn moved in", span: WordSpan(startWord: 2, endWord: 4)))])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let card = try #require(firstCard(await collect(events, count: 1)))
    let payload = try #require(CandidatePayload.memory(card))
    #expect(payload.handlePeople == [robynP1] && payload.peopleRefs == ["Robyn"])
}

@Test func aPersonMentionWithAHandleTheMemoryCarriesIsARecord() async throws {
    let mention = MentionOut(text: "my roommate", kind: .person, confidence: 0.8, handle: "p1")
    let output = handleOutput(quote: "Robyn moved in", span: WordSpan(startWord: 2, endWord: 4), mentions: [mention])
    let env = try Env(texts: ["my roommate Robyn moved in that fall"], script: [.success(output)])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    guard case .candidates(let shown, _)? = await collect(events, count: 1).first else { Issue.record("no event"); return }
    #expect(shown.map(\.kind) == [.memory], "the person is on the memory card, not a card of its own")
    #expect(try env.store.candidates.candidates(for: env.segments[0].id).first { $0.kind == .person }?.status == .accepted)
    #expect(try env.store.people.mentions(in: env.segments[0].id).isEmpty)
}

// Review Focus 5: a continuation's people join the earlier card, once per handle.
@Test func aContinuationAddsItsPeopleToTheEarlierCardOncePerHandle() async throws {
    let texts = ["my roommate Robyn moved in that fall", "Robyn cooked every night"]
    let env = try Env(texts: texts, script: [.success(handleOutput(quote: "Robyn moved in", span: WordSpan(startWord: 2, endWord: 4)))])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let a = try #require(firstCard(await collect(events, count: 1)))
    env.service.push(.success(handleOutput(quote: "Robyn cooked every night", span: WordSpan(startWord: 0, endWord: 3), continues: a.id)))
    await queue.enqueue(env.segments[1].id)
    let again = try #require(firstCard(await collect(events, count: 1)))
    #expect(again.id == a.id)
    let payload = try #require(CandidatePayload.memory(again))
    #expect(payload.handlePeople.map(\.handle) == ["p1"], "p1 is on the earlier card once")
    #expect(payload.extraSpans.count == 1)
}

@Test func aContinuationWithANewHandleAddsThatPersonToTheEarlierCard() async throws {
    let texts = ["my roommate Robyn moved in that fall", "Theo came by"]
    let env = try Env(texts: texts, script: [.success(handleOutput(quote: "Robyn moved in", span: WordSpan(startWord: 2, endWord: 4)))])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    let a = try #require(firstCard(await collect(events, count: 1)))
    let theo = PersonOut(handle: "p2", saidName: "Theo", relationText: nil, personID: nil)
    env.service.push(.success(ExtractorOutput(people: [theo],
        memories: [MemoryOut(ref: "m2", kind: .event, title: "Theo came by", quote: "Theo came by", segmentSpan: WordSpan(startWord: 0, endWord: 2),
                             peopleRefs: [], placeText: nil, anchors: [], continuesCandidateID: a.id.rawValue, collectionHint: nil, chapterHint: nil,
                             confidence: 0.9, personHandles: ["p2"])], mentions: [], flags: .none)))
    await queue.enqueue(env.segments[1].id)
    let again = try #require(firstCard(await collect(events, count: 1)))
    let payload = try #require(CandidatePayload.memory(again))
    #expect(payload.handlePeople == [robynP1, theo] && payload.personHandles == ["p1", "p2"])
}

// MARK: - PC-d Task 4b (D17): a later segment names a person of the recording by handle only

@Test func aLaterSegmentNamesAPersonOfTheRecordingByHandleOnly() async throws {
    let texts = ["my roommate Robyn moved in that fall", "She was always late"]
    let env = try Env(texts: texts, script: [.success(handleOutput(quote: "Robyn moved in", span: WordSpan(startWord: 2, endWord: 4)))])
    let queue = env.queue()
    let events = await queue.events
    await queue.enqueue(env.segments[0].id)
    _ = try #require(firstCard(await collect(events, count: 1)))
    let late = MemoryOut(ref: "m1", kind: .fact, title: "Always late", quote: "She was always late", segmentSpan: WordSpan(startWord: 0, endWord: 3),
                         peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9,
                         aboutRef: "p1", personHandles: ["p1"])
    env.service.push(.success(ExtractorOutput(memories: [late], mentions: [], flags: .none)))
    await queue.enqueue(env.segments[1].id)
    let card = try #require(firstCard(await collect(events, count: 1)))
    let payload = try #require(CandidatePayload.memory(card))
    #expect(card.segmentID == env.segments[1].id)
    #expect(payload.handlePeople == [robynP1] && payload.peopleRefs == ["Robyn"], "the said name of the earlier segment")
    #expect(payload.aboutRef == "p1")
}
