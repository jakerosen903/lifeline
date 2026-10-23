import Foundation
import Testing
@testable import LifelineKit

// Tests written for the M4 final-review findings; each failed before its fix.

private func gardenMemoryOut() -> MemoryOut {
    MemoryOut(ref: "m1", kind: .event, title: "The pomegranate tree", quote: "pomegranate tree", segmentSpan: WordSpan(startWord: 4, endWord: 5),
              peopleRefs: [], placeText: nil, anchors: [], sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
}

// I-1: the Finish entry survives stop(); landed and crash are logged.

@Test func stageLogWrittenDuringStopIsNotOverwritten() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = SessionRecorder(voice: voice, sessions: repo, audioURL: { URL(fileURLWithPath: "/tmp/\($0.rawValue).m4a") })
    let id = try await rec.start()
    async let stopping: Void = rec.stop()
    try await rec.record(stageLog: #"[{"reason":"finish"}]"#)
    try await stopping
    let row = try #require(try repo.fetch(id))
    #expect(row.stageLog.contains("finish") && row.endedAt != nil, "stop writes ended_at only; the log written meanwhile stands")
}

@Test func markLandedAppendsLanded() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let (id, _) = try StoreFixtures.session(in: repo)
    var arc = SessionArc(kind: .quick, config: .default, startedAt: .now)
    arc.apply(.finish, now: .now)
    try repo.updateStageLog(id, try SessionArc.encode(arc.log))
    try repo.markLanded(id, now: Date(timeIntervalSince1970: 3_000))
    let log = try SessionArc.decode(try #require(try repo.fetch(id)).stageLog)
    #expect(log.map(\.reason) == ["started", "finish", "landed"])
    #expect(log.last?.at == Date(timeIntervalSince1970: 3_000))
}

@Test func recoverAppendsCrashToTheLog() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let (id, _) = try StoreFixtures.session(in: repo)
    var crashed = try #require(try repo.fetch(id)); crashed.endedAt = nil; try repo.update(crashed)
    let resumed = try SessionRecorder.recoverUnfinishedSessions(repo, now: Date(timeIntervalSince1970: 2_000))
    #expect(resumed.first?.id == id)
    let log = try SessionArc.decode(try #require(try repo.fetch(id)).stageLog)
    #expect(log.last?.reason == "crash" && log.last?.stage == .ended)
}

// I-2 / I-5: heaviness is read back from stored flag rows and the log, not only from the live arc.

@Test func storedFlagRowsTellTheLandingTheSessionWasHeavy() throws {
    let db = try AppDatabase.inMemory(); let store = ExtractionStore(db)
    let (session, segments) = try StoreFixtures.session(in: store.sessions)
    #expect(SessionWeight.of(candidates: try store.candidates.candidates(in: session)) == SessionWeight(heavy: false, presentDanger: false))
    let flags = Flags(disclosure: .present, wantsToStop: false, wantsToChangeSubject: false)
    try store.candidates.insert(StoreFixtures.candidate(segments[0].id, ordinal: 0, kind: .flag, payload: try CandidatePayload.encode(flags)))
    #expect(SessionWeight.of(candidates: try store.candidates.candidates(in: session)) == SessionWeight(heavy: true, presentDanger: true))
}

@Test func presentDangerIsInTheLog() {
    var arc = SessionArc(kind: .quick, config: .default, startedAt: .now)
    arc.apply(.flags(Flags(disclosure: .present, wantsToStop: false, wantsToChangeSubject: false)), now: .now)
    #expect(arc.log.last?.reason == "disclosure:present")
    #expect(SessionWeight.of(log: arc.log) == SessionWeight(heavy: true, presentDanger: true))
    var past = SessionArc(kind: .quick, config: .default, startedAt: .now)
    past.apply(.flags(Flags(disclosure: .past, wantsToStop: false, wantsToChangeSubject: false)), now: .now)
    #expect(SessionWeight.of(log: past.log) == SessionWeight(heavy: true, presentDanger: false))
}

// I-3: Hide today also covers memories kept later from the same session.

@Test func hideTodayAlsoHidesMemoriesKeptLater() throws {
    let db = try AppDatabase.inMemory(); let store = ExtractionStore(db); let actions = CandidateActions(store: store)
    let (session, segments) = try StoreFixtures.session(in: store.sessions)
    let candidate = StoreFixtures.candidate(segments[0].id, payload: try CandidatePayload.encode(gardenMemoryOut()))
    try store.candidates.insert(candidate)
    try actions.hideSession(session)
    #expect(try store.sessions.fetch(session)?.hiddenFromTimeline == true)
    let memory = try actions.acceptMemory(candidate).memory
    #expect(try store.memories.fetch(memory.id)?.hiddenFromTimeline == true, "a memory kept after Hide today is hidden too")
}

// I-4: Exclude from AI covers curiosity built from the memory, not only the memory entry.

@Test func excludedMemoriesLeaveNoCuriosityInThePacket() {
    let excluded = StoreFixtures.memory(from: CandidateID(), title: "Something private")
    let kept = StoreFixtures.memory(from: CandidateID(), title: "The blue door")
    let items = [CuriosityItem(id: .init(), kind: .droppedThread, text: "something private", payoffCount: 3, status: .open, sourceMemoryID: excluded.id, targetMemoryID: nil),
                 CuriosityItem(id: .init(), kind: .unresolvedAnchor, text: "before Maya climbed it", payoffCount: 1, status: .open, sourceMemoryID: kept.id, targetMemoryID: excluded.id),
                 CuriosityItem(id: .init(), kind: .placeWithoutStory, text: "Fresno", payoffCount: 1, status: .open, sourceMemoryID: kept.id, targetMemoryID: nil)]
    let segment = Segment(id: .init(), sessionID: .init(), index: 0, startMs: 0, endMs: 1, text: "x", status: .pending)
    let packet = ContextPacketBuilder.build(segment: segment, previous: [], people: [], memories: [], profileFreeText: nil, stage: "open",
                                            curiosity: items, excludedMemoryIDs: [excluded.id])
    #expect(packet.curiosity == ["Fresno"])
}
