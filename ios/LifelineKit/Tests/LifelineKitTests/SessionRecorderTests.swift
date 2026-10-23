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
    let chosen = SessionID()
    let id = try await rec.start(id: chosen)
    #expect(id == chosen, "the caller's id is the session's id")
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

@Test func stateKeepsSpokenTextAndSpeakingFlagBetweenSegments() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    _ = try await rec.start()
    await voice.emit(.speechStarted(atMs: 0))
    await voice.emit(.transcriptPartial("the bl"))
    await voice.emit(.transcriptFinal(TranscriptResult(text: "the blue", words: [w("the", 0, 300), w("blue", 300, 700)], range: MsRange(start: 0, end: 700), isFinal: true)))
    await voice.emit(.transcriptPartial("do"))
    await waitUntil { await rec.state.partial == "do" }
    var s = await rec.state
    // Finals that have not closed into a segment yet stay on screen; the partial is the next utterance.
    #expect(s.isSpeaking && s.spoken == "the blue" && s.partial == "do")
    await voice.emit(.transcriptFinal(TranscriptResult(text: "door", words: [w("door", 700, 1_000)], range: MsRange(start: 700, end: 1_000), isFinal: true)))
    await voice.emit(.userPaused(afterMs: 1_000))
    await waitUntil { await !rec.state.isSpeaking }
    s = await rec.state
    #expect(s.spoken == "the blue door" && s.partial.isEmpty)
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 0, end: 4_000), text: "the blue door", words: [w("the", 0, 300), w("blue", 300, 700), w("door", 700, 1_000)])))
    await waitUntil { await rec.state.segments.count == 1 }
    s = await rec.state
    #expect(s.spoken.isEmpty && s.partial.isEmpty)
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
    #expect(try SessionRecorder.recoverUnfinishedSessions(repo).isEmpty, "no words: nothing to resume")
    #expect(try repo.unfinishedSessions().isEmpty)
    #expect(try SessionRecorder.recoverUnfinishedSessions(repo).isEmpty)
}

@Test func storedSegmentsReachTheHookInOrder() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let seen = LogCollector()
    let rec = SessionRecorder(voice: voice, sessions: repo, audioURL: { URL(fileURLWithPath: "/tmp/\($0.rawValue).m4a") },
                              hooks: .init(onSegmentStored: { seen.append($0.rawValue) }))
    let id = try await rec.start()
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 0, end: 4_000), text: "one", words: [w("one", 0, 300)])))
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 5_000, end: 9_000), text: "", words: [])))
    await voice.emit(.segmentClosed(SegmentTranscript(range: MsRange(start: 10_000, end: 14_000), text: "two", words: [w("two", 10_000, 10_300)])))
    await waitUntil { await rec.state.segments.count == 2 }
    let stored = try repo.segments(in: id).map(\.id.rawValue)
    #expect(seen.all == stored, "the hook sees exactly the stored segments, in order; the empty one never reaches it")
}

@Test func stoppedHookFiresAfterTheRowIsEnded() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let seen = LogCollector()
    let rec = SessionRecorder(voice: voice, sessions: repo, audioURL: { URL(fileURLWithPath: "/tmp/\($0.rawValue).m4a") },
                              now: { Date(timeIntervalSince1970: 1_000) },
                              hooks: .init(onStopped: { seen.append((try? repo.listSessions().first?.endedAt) == nil ? "open" : "ended") }))
    try await rec.start()
    try await rec.stop()
    #expect(seen.all == ["ended"], "the background sorting starts from an ended session")
    try await rec.stop()
    #expect(seen.all == ["ended"], "a second Finish is a no-op")
}

@Test func stopReturnsBeforeExtractionFinishes() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let finished = LogCollector()
    let rec = SessionRecorder(voice: voice, sessions: repo, audioURL: { URL(fileURLWithPath: "/tmp/\($0.rawValue).m4a") },
                              hooks: .init(onStopped: { Task { try? await Task.sleep(for: .seconds(1)); finished.append("sorted") } }))
    let id = try await rec.start()
    let clock = ContinuousClock()
    let elapsed = await clock.measure { try? await rec.stop() }
    #expect(elapsed < .milliseconds(500), "finishing never waits for sorting: \(elapsed)")
    #expect(try repo.fetch(id)?.endedAt != nil)
    #expect(finished.all.isEmpty, "sorting is still going on in the background")
}

@Test func recoverLeavesUnlandedSessionsWithSegmentsOpen() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let (withWords, _) = try StoreFixtures.session(in: repo, segments: ["the garden had a pomegranate tree"])
    var crashed = try #require(try repo.fetch(withWords)); crashed.endedAt = nil; try repo.update(crashed)
    let empty = Session(id: .init(), startedAt: .now, endedAt: nil, audioPath: "e.m4a", stageLog: "[]", landingChoiceMade: false)
    try repo.insert(empty)
    let resume = try SessionRecorder.recoverUnfinishedSessions(repo, now: Date(timeIntervalSince1970: 2_000))
    #expect(resume.map(\.id) == [withWords], "a session with words is resumed to the landing, not closed")
    #expect(try repo.fetch(withWords)?.endedAt != nil, "its recording has ended, though")
    #expect(try repo.fetch(withWords)?.landingChoiceMade == false)
    let closed = try #require(try repo.fetch(empty.id))
    #expect(closed.endedAt != nil && closed.landingChoiceMade, "an empty session is closed quietly")
}

@Test func markLandedAndUnlandedSessions() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let (a, _) = try StoreFixtures.session(in: repo)
    #expect(try repo.unlandedSessions().map(\.id) == [a])
    try repo.markLanded(a, stageLog: "[]")
    #expect(try repo.unlandedSessions().isEmpty)
    #expect(try repo.fetch(a)?.landingChoiceMade == true)
}

@Test func pauseAndResumeAreRecordedInState() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    _ = try await rec.start()
    try await rec.pause()
    #expect(await voice.pauseCalls == 1)
    await waitUntil { await rec.state.isPaused }
    try await rec.resume()
    #expect(await voice.resumeCalls == 1)
    await waitUntil { await !rec.state.isPaused }
}

@Test func stageLogIsStoredOnTheRow() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = makeRecorder(voice: voice, repo: repo)
    let id = try await rec.start(kind: .settleIn)
    try await rec.record(stageLog: #"[{"stage":"open"}]"#)
    let row = try #require(try repo.fetch(id))
    #expect(row.stageLog == #"[{"stage":"open"}]"# && row.kind == .settleIn)
}
