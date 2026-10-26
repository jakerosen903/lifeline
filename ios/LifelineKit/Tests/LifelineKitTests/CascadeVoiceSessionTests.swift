import Foundation
import Testing
@testable import LifelineKit

private struct Harness {
    let src = FakeAudioSource(), tr = FakeTranscriber(), sink = FakeAudioSink(), output = FakeVoiceOutput()
    let log = LogCollector()
    let vs: CascadeVoiceSession
    init() {
        let log = self.log
        vs = CascadeVoiceSession(source: src, sink: sink, transcriber: tr, output: output,
                                 timing: .init(finalizeGraceMs: 700, finalizeTimeoutMs: 1_500),
                                 log: { log.append($0) })
    }
}

final class LogCollector: Sendable {
    private let lines = Mutex<[String]>([])
    func append(_ s: String) { lines.withLock { $0.append(s) } }
    var all: [String] { lines.withLock { $0 } }
}
import Synchronization

private func firstEvent(_ events: AsyncStream<VoiceEvent>, where match: @escaping @Sendable (VoiceEvent) -> Bool, timeoutMs: Int = 3_000) async throws -> VoiceEvent {
    try await withThrowingTaskGroup(of: VoiceEvent?.self) { group in
        group.addTask { for await e in events where match(e) { return e }; return nil }
        group.addTask { try await Task.sleep(for: .milliseconds(timeoutMs)); return nil }
        let first = try await group.next() ?? nil
        group.cancelAll()
        return try #require(first, "timed out waiting for event")
    }
}

private func collectUntil(_ events: AsyncStream<VoiceEvent>, timeoutMs: Int = 3_000, _ stop: @escaping @Sendable (VoiceEvent) -> Bool) async throws -> [VoiceEvent] {
    try await withThrowingTaskGroup(of: [VoiceEvent].self) { group in
        group.addTask { var out: [VoiceEvent] = []; for await e in events { out.append(e); if stop(e) { break } }; return out }
        group.addTask { try await Task.sleep(for: .milliseconds(timeoutMs)); return [] }
        let first = try await group.next() ?? []
        group.cancelAll()
        return first
    }
}

private func collect(_ events: AsyncStream<VoiceEvent>, count: Int, timeoutMs: Int = 3_000) async throws -> [VoiceEvent] {
    try await withThrowingTaskGroup(of: [VoiceEvent].self) { group in
        group.addTask { var out: [VoiceEvent] = []; for await e in events { out.append(e); if out.count == count { break } }; return out }
        group.addTask { try await Task.sleep(for: .milliseconds(timeoutMs)); return [] }
        let first = try await group.next() ?? []
        group.cancelAll()
        return first
    }
}

@Test func segmentClosedCarriesWordsInsideRange() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.tr.push(TranscriptResult(text: "the blue door", words: [w("the", 0, 300), w("blue", 300, 700), w("door", 700, 1_100)], range: MsRange(start: 0, end: 1_100), isFinal: true))
    h.tr.push(TranscriptResult(text: "later", words: [w("later", 4_500, 4_900)], range: MsRange(start: 4_500, end: 4_900), isFinal: true))
    h.src.push(speechMs: 0..<4_000, silenceMs: 4_000..<6_000)
    let closed = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    guard case .segmentClosed(let seg) = closed else { Issue.record("not a segmentClosed"); return }
    #expect(seg.range == MsRange(start: 0, end: 4_000))
    #expect(seg.words.map(\.text) == ["the", "blue", "door"])
    #expect(seg.text == "the blue door")
    #expect(h.tr.finalizedThrough == [4_000])
}

@Test func anAbandonedBlipEndsSpeaking() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<500, silenceMs: 500..<2_500)
    let seen = try await collectUntil(events) { if case .userPaused = $0 { true } else { false } }
    #expect(seen == [.speechStarted(atMs: 0), .userPaused(afterMs: 500)])
    try await h.vs.stop()
    var rest: [VoiceEvent] = []
    for await e in events { rest.append(e) }
    #expect(!rest.contains { if case .segmentClosed = $0 { true } else { false } })
}

@Test func aShortBlipThenPauseEndsSpeakingWithoutASegment() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<500, silenceMs: 500..<500)
    try await Task.sleep(for: .milliseconds(200))
    try await h.vs.pause()
    let seen = try await collectUntil(events) { $0 == .paused }
    #expect(seen.contains(.userPaused(afterMs: 500)))
    #expect(!seen.contains { if case .segmentClosed = $0 { true } else { false } })
    try await h.vs.stop()
    var rest: [VoiceEvent] = []
    for await e in events { rest.append(e) }
    #expect(!rest.contains { if case .segmentClosed = $0 { true } else { false } })
}

@Test func wordsAfterASegmentEndWidenTheNextSegment() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<4_000, silenceMs: 4_000..<6_000)
    // Wait until the session asked for finalization, then deliver the final late (during the grace wait).
    for _ in 0..<50 where h.tr.finalizedThrough.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    #expect(h.tr.finalizedThrough == [4_000])
    h.tr.push(TranscriptResult(text: "we moved house later", words: [w("we", 3_000, 3_400), w("moved", 3_400, 3_900), w("house", 3_900, 4_200), w("later", 4_100, 4_400)], range: MsRange(start: 3_000, end: 4_400), isFinal: true))
    let closed = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    guard case .segmentClosed(let seg) = closed else { Issue.record("not a segmentClosed"); return }
    #expect(seg.words.map(\.text) == ["we", "moved", "house"])   // "later" starts at 4_100, outside 0..<4_000
    #expect(seg.range == MsRange(start: 0, end: 4_000))
    // The held word lands in the next segment, whose range widens to contain it.
    h.src.push(speechMs: 6_000..<10_000, silenceMs: 10_000..<12_000)
    h.tr.push(TranscriptResult(text: "", words: [], range: MsRange(start: 10_000, end: 10_000), isFinal: true))
    let next = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    guard case .segmentClosed(let seg2) = next else { return }
    #expect(seg2.words.map(\.text) == ["later"])
    #expect(seg2.range == MsRange(start: 4_100, end: 10_000))
    #expect(seg2.words.allSatisfy { seg2.range.contains($0.range.start) })
}

@Test func wordsArrivingDuringStopAreStored() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<4_000)
    for _ in 0..<50 where h.tr.fed.count < 40 { try await Task.sleep(for: .milliseconds(20)) }
    // The last finals only arrive once the transcriber is told to finish: a closing remark after the last pause.
    h.tr.resultsOnFinish.withLock { $0 = [TranscriptResult(text: "a tail", words: [w("a", 0, 500), w("tail", 4_100, 4_500)], range: MsRange(start: 0, end: 4_500), isFinal: true)] }
    try await h.vs.stop()
    var closed: [SegmentTranscript] = []
    for await e in events { if case .segmentClosed(let s) = e { closed.append(s) } }
    #expect(closed.map(\.range) == [MsRange(start: 0, end: 4_000), MsRange(start: 4_100, end: 4_500)])
    #expect(closed.map { $0.words.map(\.text) } == [["a"], ["tail"]])
}

@Test func hungFinalizeDoesNotBlockSegmentCloseOrStop() async throws {
    let h = Harness()
    h.tr.finalizeDelay.withLock { $0 = .seconds(60) }
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<4_000, silenceMs: 4_000..<6_000)
    let closed = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    guard case .segmentClosed(let seg) = closed else { Issue.record("not a segmentClosed"); return }
    #expect(seg.range == MsRange(start: 0, end: 4_000))
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await h.vs.stop() }
        group.addTask { try await Task.sleep(for: .seconds(3)); Issue.record("stop() hung behind finalize") }
        try await group.next()
        group.cancelAll()
    }
}

@Test func interruptionClosesOpenSegment() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<5_000)
    h.src.pushInterrupted()
    h.tr.push(TranscriptResult(text: "x", words: [w("x", 100, 400)], range: MsRange(start: 100, end: 400), isFinal: true))
    let got = try await collectUntil(events) { $0 == .interrupted }
    #expect(got.contains(.userPaused(afterMs: 5_000)))
    let closed = got.compactMap { if case .segmentClosed(let s) = $0 { s } else { nil } }
    #expect(closed.map(\.range) == [MsRange(start: 0, end: 5_000)])
    #expect(got.last == .interrupted)
}

@Test func everyChunkReachesSinkAndTranscriberInOrder() async throws {
    let h = Harness()
    _ = try await h.vs.start(writingTo: URL(fileURLWithPath: "/tmp/never-written.m4a"))
    h.src.push(speechMs: 0..<1_000)
    for _ in 0..<50 where h.tr.fed.count < 10 { try await Task.sleep(for: .milliseconds(20)) }
    #expect(h.sink.written.count == 10 && h.tr.fed.count == 10)
    #expect(h.sink.written.map(\.start) == Array(stride(from: 0, to: 1_000, by: 100)))
    #expect(h.sink.opened?.path == "/tmp/never-written.m4a")
}

@Test func stopFlushesFinishesAndEndsStream() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<4_000)
    for _ in 0..<50 where h.tr.fed.count < 40 { try await Task.sleep(for: .milliseconds(20)) }
    h.tr.push(TranscriptResult(text: "a", words: [w("a", 0, 500)], range: MsRange(start: 0, end: 500), isFinal: true))
    try await h.vs.stop()
    var all: [VoiceEvent] = []
    for await e in events { all.append(e) }    // the stream must end
    #expect(all.contains { if case .segmentClosed(let s) = $0 { s.range == MsRange(start: 0, end: 4_000) } else { false } })
    #expect(h.sink.closed && h.tr.finished && h.src.stopped)
}

@Test func aSilentTurnStartsAndEndsAtOnce() async throws {
    let vs = CascadeVoiceSession(source: FakeAudioSource(), sink: FakeAudioSink(), transcriber: FakeTranscriber())
    let events = try await vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "What would you like to tell me about today?")
    await vs.say(turn)
    let seen = try await collect(events, count: 2)
    #expect(seen == [.turnStarted(turn.id, atMs: 0), .turnEnded(turn.id, atMs: 0, interrupted: false)])
    try await vs.stop()
}

@Test func acknowledgeAndInterruptWithNoTurnOnlyLog() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    await h.vs.acknowledge(); await h.vs.interrupt()
    #expect(h.log.all.count == 2)
    #expect(try await collect(events, count: 1, timeoutMs: 200).isEmpty)
    #expect(h.output.stops == 0)
}

@Test func pausesAreLoggedNotEmitted() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<3_000, silenceMs: 3_000..<4_000)
    h.src.push(speechMs: 4_000..<6_000, silenceMs: 6_000..<8_000)
    h.tr.push(TranscriptResult(text: "", words: [], range: MsRange(start: 0, end: 0), isFinal: true))
    _ = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    #expect(h.log.all.contains("pause 1000"))
}

@Test func resultsStreamEndingBeforeStopIsReportedAsFailure() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.tr.endResults()
    let event = try await firstEvent(events) { if case .failed = $0 { true } else { false } }
    guard case .failed(let message) = event else { Issue.record("expected failed"); return }
    #expect(message.contains("transcriber"))
    try await h.vs.stop()
}

@Test func pauseClosesTheOpenSegmentAndResumeContinuesTheClock() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<4_000)
    h.tr.push(TranscriptResult(text: "one", words: [TranscribedWord(text: "one", range: MsRange(start: 0, end: 300))], range: MsRange(start: 0, end: 300), isFinal: true))
    _ = try await firstEvent(events) { if case .transcriptFinal = $0 { true } else { false } }
    try await Task.sleep(for: .milliseconds(300))   // let the source task observe every pushed chunk
    try await h.vs.pause()
    let closed = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    guard case .segmentClosed(let segment) = closed else { Issue.record("expected a segment"); return }
    #expect(segment.range == MsRange(start: 0, end: 4_000) && segment.words.count == 1, "pausing closes what was said")
    #expect(await h.src.paused)
    _ = try await firstEvent(events) { if case .paused = $0 { true } else { false } }
    try await h.vs.resume()
    _ = try await firstEvent(events) { if case .resumed = $0 { true } else { false } }
    // The next chunk follows on the same file clock: the source keeps counting frames, so the session accepts it as is.
    h.src.push(speechMs: 4_000..<7_000, silenceMs: 7_000..<9_000)
    h.tr.push(TranscriptResult(text: "two", words: [TranscribedWord(text: "two", range: MsRange(start: 4_000, end: 4_300))], range: MsRange(start: 4_000, end: 4_300), isFinal: true))
    let second = try await firstEvent(events) { if case .segmentClosed(let s) = $0 { s.range.start >= 4_000 } else { false } }
    guard case .segmentClosed(let next) = second else { Issue.record("expected a second segment"); return }
    #expect(next.range.start == 4_000)
}

// MARK: Turns (M8)

private func isTurnStarted(_ e: VoiceEvent) -> Bool { if case .turnStarted = e { true } else { false } }
private func isTurnEnded(_ e: VoiceEvent) -> Bool { if case .turnEnded = e { true } else { false } }

/// Waits until the session has taken `chunks` chunks, so `lastChunkEndMs` is where the test expects.
private func settle(_ h: Harness, chunks: Int) async throws {
    for _ in 0..<100 where h.tr.fed.count < chunks { try await Task.sleep(for: .milliseconds(20)) }
    try await Task.sleep(for: .milliseconds(100))
}

@Test func appWordsInAFinalNeverReachASegment() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<0, silenceMs: 0..<1_000)
    try await settle(h, chunks: 10)
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "Where did you grow up?")
    await h.vs.say(turn)
    _ = try await firstEvent(events, where: isTurnStarted)
    h.src.push(speechMs: 1_000..<2_500)   // the app's own voice reaches the mic
    try await settle(h, chunks: 25)
    h.output.finish()
    _ = try await firstEvent(events, where: isTurnEnded)
    // The transcriber hears the turn and then the person, in one final.
    let heard = [w("where", 1_100, 1_300), w("did", 1_300, 1_500), w("you", 1_500, 1_700), w("grow", 1_700, 2_000), w("up", 2_000, 2_300),
                 w("by", 2_600, 2_800), w("the", 2_800, 3_000), w("sea", 3_000, 3_600), w("every", 4_000, 4_500), w("summer", 4_500, 6_400)]
    h.tr.push(TranscriptResult(text: heard.map(\.text).joined(separator: " "), words: heard, range: MsRange(start: 1_100, end: 6_400), isFinal: true))
    h.src.push(speechMs: 2_500..<6_500, silenceMs: 6_500..<8_500)
    let closed = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    guard case .segmentClosed(let segment) = closed else { Issue.record("expected a segment"); return }
    #expect(segment.words.map(\.text) == ["by", "the", "sea", "every", "summer"])
    #expect(segment.text == "by the sea every summer")
    #expect(segment.range == MsRange(start: 2_500, end: 6_500), "the app's words do not widen the segment")
}

@Test func energyDuringPlaybackOpensNoSegment() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "Tell me about the house.")
    await h.vs.say(turn)
    _ = try await firstEvent(events, where: isTurnStarted)
    h.src.push(speechMs: 0..<4_000, silenceMs: 4_000..<6_000)
    try await settle(h, chunks: 60)
    h.output.finish()
    let during = try await collectUntil(events, isTurnEnded)
    #expect(during == [.turnEnded(turn.id, atMs: 6_000, interrupted: false)], "no speech, pause or segment from the app's voice; saw \(during)")
    #expect(h.sink.written.count == 60, "the audio file still records every chunk")
    // After the turn, the person's energy opens a segment again.
    h.src.push(speechMs: 6_000..<7_000)
    let started = try await firstEvent(events) { if case .speechStarted = $0 { true } else { false } }
    #expect(started == .speechStarted(atMs: 6_000))
}

@Test func pauseCutsTheTurn() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<0, silenceMs: 0..<1_000)
    try await settle(h, chunks: 10)
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "Who lived next door?")
    await h.vs.say(turn)
    #expect(try await firstEvent(events, where: isTurnStarted) == .turnStarted(turn.id, atMs: 1_000))
    try await h.vs.pause()
    let seen = try await collectUntil(events) { $0 == .paused }
    #expect(seen.contains(.turnEnded(turn.id, atMs: 1_000, interrupted: true)))
    #expect(h.output.stops == 1)
    // A turn offered while paused is dropped, and the cut turn does not come back.
    await h.vs.say(SpokenTurn(id: InterviewerTurnID(), text: "And after that?"))
    #expect(h.output.played == [turn.text])
    try await h.vs.resume()
    #expect(try await collect(events, count: 1) == [.resumed], "the dropped turn emitted nothing")
}

@Test func anInterruptionCutsTheTurn() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "Who lived next door?")
    await h.vs.say(turn)
    _ = try await firstEvent(events, where: isTurnStarted)
    h.src.pushInterrupted()
    let seen = try await collectUntil(events) { $0 == .interrupted }
    #expect(seen.contains(.turnEnded(turn.id, atMs: 0, interrupted: true)))
    #expect(h.output.stops == 1)
}

@Test func stopCutsTheTurnAndAcceptsNoOther() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "Who lived next door?")
    await h.vs.say(turn)
    _ = try await firstEvent(events, where: isTurnStarted)
    try await h.vs.stop()
    await h.vs.say(SpokenTurn(id: InterviewerTurnID(), text: "And after that?"))
    var rest: [VoiceEvent] = []
    for await e in events { rest.append(e) }
    #expect(rest == [.turnEnded(turn.id, atMs: 0, interrupted: true)])
    #expect(h.output.stops == 1 && h.output.played == [turn.text])
}

@Test func aNewTurnEndsThePlayingOneFirst() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    let first = SpokenTurn(id: InterviewerTurnID(), text: "Who lived next door?")
    let second = SpokenTurn(id: InterviewerTurnID(), text: "We can leave it here, or carry on.")
    await h.vs.say(first)
    _ = try await firstEvent(events, where: isTurnStarted)
    await h.vs.say(second)
    let seen = try await collect(events, count: 2)
    #expect(seen == [.turnEnded(first.id, atMs: 0, interrupted: true), .turnStarted(second.id, atMs: 0)])
}

@Test func aTurnDuringAnInterruptionIsDropped() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.pushInterrupted()
    _ = try await firstEvent(events) { $0 == .interrupted }
    await h.vs.say(SpokenTurn(id: InterviewerTurnID(), text: "Who lived next door?"))
    #expect(h.output.played.isEmpty)
    h.src.pushResumed()
    #expect(try await collect(events, count: 1) == [.resumed], "the dropped turn emitted nothing")
}

@Test func overlappingTurnsStayBalanced() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    let first = SpokenTurn(id: InterviewerTurnID(), text: "Who lived next door?")
    let second = SpokenTurn(id: InterviewerTurnID(), text: "And after that?")
    let third = SpokenTurn(id: InterviewerTurnID(), text: "We can leave it here, or carry on.")
    await h.vs.say(first)
    #expect(try await firstEvent(events, where: isTurnStarted) == .turnStarted(first.id, atMs: 0))
    h.output.stopDelay.withLock { $0 = .milliseconds(300) }
    // `second` cuts `first` and waits in the slow stop; `third` arrives meanwhile.
    let pending = Task { await h.vs.say(second) }
    try await Task.sleep(for: .milliseconds(50))
    await h.vs.say(third)
    await pending.value
    h.output.stopDelay.withLock { $0 = nil }
    await h.vs.interrupt()   // ends whatever plays now
    try await h.vs.stop()
    var all: [VoiceEvent] = []
    for await e in events { all.append(e) }
    var open: Set<InterviewerTurnID> = [first.id], maxOpen = 1
    for e in all {
        if case .turnStarted(let id, _) = e { #expect(open.insert(id).inserted, "a turn starts once"); maxOpen = max(maxOpen, open.count) }
        if case .turnEnded(let id, _, _) = e { #expect(open.remove(id) != nil, "a turn ends once, after it started; saw \(all)") }
    }
    #expect(open.isEmpty, "every started turn ended; saw \(all)")
    #expect(maxOpen == 1, "one turn at a time")
    #expect(!h.output.played.contains(second.text), "the superseded turn never plays")
}
