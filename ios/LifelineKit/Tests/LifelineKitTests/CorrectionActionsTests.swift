import Foundation
import Testing
import GRDB
@testable import LifelineKit

/// Correction and privacy actions (M4): hide, exclude, hide today, delete today, rename, link.
private struct Env {
    let db: AppDatabase, store: ExtractionStore, actions: CandidateActions
    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        actions = CandidateActions(store: store)
    }
    /// A session with one segment per text and one accepted memory per segment.
    func told(_ texts: [String]) throws -> (SessionID, [Segment], [Memory]) {
        let (session, segments) = try StoreFixtures.session(in: store.sessions, segments: texts)
        var memories: [Memory] = []
        for (i, segment) in segments.enumerated() {
            let out = MemoryOut(ref: "m\(i)", kind: .event, title: "Memory \(i)", quote: String(texts[i].split(separator: " ").prefix(2).joined(separator: " ")),
                                segmentSpan: WordSpan(startWord: 0, endWord: 1), peopleRefs: [], placeText: nil, anchors: [],
                                sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
            let candidate = StoreFixtures.candidate(segment.id, ordinal: 0, kind: .memory, payload: try CandidatePayload.encode(out))
            try store.candidates.insert(candidate)
            try store.sessions.setStatus(.extracted, for: segment.id)   // as the queue does when it stores the rows
            memories.append(try actions.acceptMemory(candidate).memory)
        }
        return (session, segments, memories)
    }
}

@Test func hiddenMemoriesLeaveTheTimelineQueryButStayInSessions() throws {
    let env = try Env()
    let (session, _, memories) = try env.told(["the garden had a pomegranate tree", "my sister climbed it"])
    try env.actions.setHidden(memories[0].id, true)
    #expect(try env.store.memories.visibleMemories().map(\.id) == [memories[1].id])
    #expect(try env.store.memories.memories(in: session).map(\.id) == memories.map(\.id), "Sessions still shows it")
    #expect(try env.store.memories.fetch(memories[0].id)?.hiddenFromTimeline == true)
    try env.actions.setHidden(memories[0].id, false)
    #expect(try env.store.memories.visibleMemories().count == 2)
}

@Test func excludedFlagIsStoredAndIndependentOfHidden() throws {
    let env = try Env()
    let (_, _, memories) = try env.told(["the garden had a pomegranate tree"])
    try env.actions.setExcluded(memories[0].id, true)
    let m = try #require(try env.store.memories.fetch(memories[0].id))
    #expect(m.excludedFromAI && !m.hiddenFromTimeline)
    #expect(try env.store.memories.visibleMemories().count == 1, "excluded from AI is not hidden from the person")
}

@Test func hideTodayFlagsEverySessionMemory() throws {
    let env = try Env()
    let (today, _, mine) = try env.told(["the garden had a pomegranate tree", "my sister climbed it"])
    let (_, _, other) = try env.told(["we drove to the coast"])
    try env.actions.hideSession(today)
    #expect(try mine.allSatisfy { try env.store.memories.fetch($0.id)?.hiddenFromTimeline == true })
    #expect(try env.store.memories.fetch(other[0].id)?.hiddenFromTimeline == false)
}

@Test func deleteSessionDropsPendingSortingAndEverything() async throws {
    let env = try Env()
    let (doomed, segments, memories) = try env.told(["the garden had a pomegranate tree"])
    let (kept, _, keptMemories) = try env.told(["we drove to the coast"])
    // A second, still-pending segment in the doomed session, a mention and a prompt-log row.
    let pending = Segment(id: .init(), sessionID: doomed, index: 1, startMs: 10_000, endMs: 14_000, text: "my sister climbed it", status: .pending)
    try env.store.sessions.insert(pending, words: [Word(segmentID: pending.id, index: 0, text: "my", startMs: 10_000, endMs: 10_200)])
    try env.store.people.insertMention(Mention(id: .init(), segmentID: segments[0].id, text: "Maya", status: .unresolved, personID: nil, relationText: "my sister"))
    try PromptLogRepository(env.db).record(promptID: "p1", session: doomed, at: .now)
    let audio = FileManager.default.temporaryDirectory.appending(path: "\(doomed.rawValue).m4a")
    try Data("tone".utf8).write(to: audio)

    let service = FakeExtractionService()
    let worker = SortingWorker(store: env.store, service: service)
    await worker.cancel(session: doomed)
    try env.actions.deleteSession(doomed, audioURL: audio)

    #expect(!FileManager.default.fileExists(atPath: audio.path))
    let counts = try rowCounts(env.db, doomed: doomed, pending: pending, segment: segments[0], memory: memories[0])
    #expect(counts.values.allSatisfy { $0 == 0 }, "\(counts)")
    #expect(try env.store.sessions.fetch(kept) != nil)
    #expect(try env.store.memories.fetch(keptMemories[0].id) != nil)
    _ = await worker.start()
    #expect(service.requests.isEmpty, "nothing left to sort, and nothing was asked about the deleted session")
}

@Test func deleteSessionWithoutAFileStillRemovesTheRows() throws {
    let env = try Env()
    let (doomed, _, _) = try env.told(["the garden had a pomegranate tree"])
    try env.actions.deleteSession(doomed, audioURL: FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).m4a"))
    #expect(try env.store.sessions.fetch(doomed) == nil)
}

private func rowCounts(_ db: AppDatabase, doomed: SessionID, pending: Segment, segment: Segment, memory: Memory) throws -> [String: Int] {
    try db.writer.read { db -> [String: Int] in
        var out: [String: Int] = [:]
        out["session"] = try Int.fetchOne(db, sql: "select count(*) from session where id = ?", arguments: [doomed.rawValue])
        out["segment"] = try Int.fetchOne(db, sql: "select count(*) from segment where session_id = ?", arguments: [doomed.rawValue])
        out["word"] = try Int.fetchOne(db, sql: "select count(*) from word where segment_id = ?", arguments: [pending.id.rawValue])
        out["candidate"] = try Int.fetchOne(db, sql: "select count(*) from candidate where segment_id = ?", arguments: [segment.id.rawValue])
        out["mention"] = try Int.fetchOne(db, sql: "select count(*) from mention where segment_id = ?", arguments: [segment.id.rawValue])
        out["memory"] = try Int.fetchOne(db, sql: "select count(*) from memory where id = ?", arguments: [memory.id.rawValue])
        out["memory_span"] = try Int.fetchOne(db, sql: "select count(*) from memory_span where memory_id = ?", arguments: [memory.id.rawValue])
        out["anchor"] = try Int.fetchOne(db, sql: "select count(*) from anchor where memory_id = ?", arguments: [memory.id.rawValue])
        out["prompt_log"] = try Int.fetchOne(db, sql: "select count(*) from prompt_log where session_id = ?", arguments: [doomed.rawValue])
        return out
    }
}

@Test func deletingASessionRemovesOnlyItsSpans() throws {
    let env = try Env()
    let (s1, _, memories) = try env.told(["we lived in an orange house"])
    let target = memories[0]
    let (s2, segs2) = try StoreFixtures.session(in: env.store.sessions, segments: ["grew up in an orange house"])
    let out = MemoryOut(ref: "m1", kind: .event, title: "Grew up", quote: "grew up", segmentSpan: WordSpan(startWord: 0, endWord: 1), peopleRefs: [], placeText: nil,
                        anchors: [], sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
    let c = StoreFixtures.candidate(segs2[0].id, payload: try CandidatePayload.encode(out))
    try env.store.candidates.insert(c)
    try env.store.sessions.setStatus(.extracted, for: segs2[0].id)
    _ = try env.actions.mergeCandidate(c, into: target.id)
    #expect(try env.store.memories.spans(of: target.id).count == 2)
    try env.store.sessions.deleteSession(s2)
    let left = try env.store.memories.spans(of: target.id)
    #expect(left.count == 1 && left[0].order == 0, "the older memory keeps its first telling")
    try env.store.sessions.deleteSession(s1)
    #expect(try env.store.memories.fetch(target.id) == nil, "a memory with no span left goes too")
}

@Test func deletingASessionRenumbersSurvivingSpans() throws {
    let env = try Env()
    let (s1, _, memories) = try env.told(["we lived in an orange house"])
    let target = memories[0]
    var sessions: [SessionID] = []
    for text in ["grew up in an orange house", "the orange house had a canal"] {
        let (s, segs) = try StoreFixtures.session(in: env.store.sessions, segments: [text])
        let out = MemoryOut(ref: "m1", kind: .event, title: text, quote: text, segmentSpan: WordSpan(startWord: 0, endWord: 1), peopleRefs: [], placeText: nil,
                            anchors: [], sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try env.store.candidates.insert(c)
        _ = try env.actions.mergeCandidate(c, into: target.id)
        sessions.append(s)
    }
    try env.store.sessions.deleteSession(s1)
    let spans = try env.store.memories.spans(of: target.id)
    #expect(spans.map(\.order) == [0, 1] && spans[0].titleText == "grew up in an orange house")
    #expect(try env.store.memories.fetch(target.id) != nil)
    _ = sessions
}

@Test func setStatedRangeRejectsOtherOrigins() throws {
    let env = try Env()
    let (_, _, memories) = try env.told(["we lived in an orange house"])
    let m = memories[0].id
    #expect(throws: CandidateActions.Error.notStated) { try env.actions.setStatedRange(m, .year(1998, origin: .inferred, evidence: nil)) }
    try env.actions.setStatedRange(m, .stated(around: 1998))
    let range = try #require(try env.store.memories.fetch(m)?.range)
    #expect(range.displayText == "around 1998" && range.origin == .stated)
}
