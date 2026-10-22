import Foundation
import Testing
@testable import LifelineKit

private func makeRecorder(voice: FakeVoiceSession, repo: SessionRepository) -> SessionRecorder {
    SessionRecorder(voice: voice, sessions: repo,
                    audioURL: { URL(fileURLWithPath: "/tmp/\($0.rawValue).m4a") },
                    now: { Date(timeIntervalSince1970: 1_000) })
}

private func waitUntil(_ cond: @escaping () async -> Bool, timeoutMs: Int = 2_000) async {
    for _ in 0..<(timeoutMs / 20) {
        if await cond() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@Test func startInsertsOpenSessionBeforeVoiceStarts() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    let id = try await rec.start()
    let row = try #require(try repo.fetch(id))
    #expect(row.endedAt == nil && row.startedAt == Date(timeIntervalSince1970: 1_000))
    #expect(row.audioPath == "\(id.rawValue).m4a")
    #expect(await voice.startCalled)
    #expect(await voice.audioURL?.lastPathComponent == "\(id.rawValue).m4a")
}

@Test func startFailureRemovesTheOrphanRow() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    await voice.setFailOnStart()
    let rec = makeRecorder(voice: voice, repo: repo)
    await #expect(throws: (any Error).self) { try await rec.start() }
    #expect(try repo.listSessions().isEmpty)
}

@Test func segmentClosedBecomesRows() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    let id = try await rec.start()
    let words = [w("the", 0, 300), w("blue", 300, 700), w("door", 700, 1_100)]
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 0, end: 4_000), text: "the blue door", words: words)))
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 6_000, end: 9_000), text: "and a garden", words: [w("and", 6_000, 6_200), w("a", 6_200, 6_300), w("garden", 6_300, 6_900)])))
    await waitUntil { (try? repo.segments(in: id).count) == 2 }
    let segs = try repo.segments(in: id)
    #expect(segs.map(\.index) == [0, 1])
    #expect(segs[0].text == "the blue door" && segs[0].range == MsRange(start: 0, end: 4_000) && segs[0].status == .pending)
    let stored = try repo.words(in: segs[0].id)
    #expect(stored.map(\.text) == ["the", "blue", "door"])
    #expect(stored.map(\.startMs) == [0, 300, 700])
}

@Test func emptySegmentIsNotStored() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    let id = try await rec.start()
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 0, end: 4_000), text: "", words: [])))
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 5_000, end: 9_000), text: "hello there", words: [w("hello", 5_000, 5_400), w("there", 5_400, 5_900)])))
    await waitUntil { (try? repo.segments(in: id).count) == 1 }
    #expect(try repo.segments(in: id).map(\.index) == [0])
}

@Test func stateReflectsPartialsSegmentsAndInterruptions() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    _ = try await rec.start()
    await voice.emit(.transcriptPartial("the bl"))
    await voice.emit(.interrupted)
    await waitUntil { await rec.state.isInterrupted }
    var s = await rec.state
    #expect(s.partial == "the bl" && s.isInterrupted)
    await voice.emit(.resumed)
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 0, end: 4_000), text: "the blue", words: [w("the", 0, 300), w("blue", 300, 700)])))
    await waitUntil { await rec.state.segments.count == 1 }
    s = await rec.state
    #expect(!s.isInterrupted && s.partial.isEmpty && s.segments.first?.text == "the blue")
}

@Test func stopSetsEndedAt() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    let id = try await rec.start()
    try await rec.stop()
    #expect(try repo.fetch(id)?.endedAt == Date(timeIntervalSince1970: 1_000))
    #expect(await voice.stopCalled)
    #expect(try repo.unfinishedSessions().isEmpty)
}

@Test func stopTwiceIsHarmless() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    _ = try await rec.start()
    try await rec.stop()
    try await rec.stop()
    #expect(try repo.listSessions().count == 1)
}

@Test func recoverUnfinishedSessionsSetsEndedAt() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    try repo.insert(Session(id: .init(), startedAt: .now, endedAt: nil, audioPath: "a.m4a", stageLog: "[]", landingChoiceMade: false))
    try repo.insert(Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "b.m4a", stageLog: "[]", landingChoiceMade: false))
    #expect(try SessionRecorder.recoverUnfinishedSessions(repo) == 1)
    #expect(try repo.unfinishedSessions().isEmpty)
    #expect(try SessionRecorder.recoverUnfinishedSessions(repo) == 0)
}
