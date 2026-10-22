import Foundation
import Testing
@testable import LifelineKit

private struct Harness {
    let src = FakeAudioSource(), tr = FakeTranscriber(), sink = FakeAudioSink()
    let log = LogCollector()
    let vs: ListenOnlyVoiceSession
    init() {
        let log = self.log
        vs = ListenOnlyVoiceSession(source: src, sink: sink, transcriber: tr,
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

@Test func lateFinalWordsGoToTheSegmentTheyStartIn() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    h.src.push(speechMs: 0..<4_000, silenceMs: 4_000..<6_000)
    // Wait until the session asked for finalization, then deliver the final late.
    for _ in 0..<50 where h.tr.finalizedThrough.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    #expect(h.tr.finalizedThrough == [4_000])
    h.tr.push(TranscriptResult(text: "we moved house later", words: [w("we", 3_000, 3_400), w("moved", 3_400, 3_900), w("house", 3_900, 4_200), w("later", 4_100, 4_400)], range: MsRange(start: 3_000, end: 4_400), isFinal: true))
    let closed = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    guard case .segmentClosed(let seg) = closed else { Issue.record("not a segmentClosed"); return }
    #expect(seg.words.map(\.text) == ["we", "moved", "house"])   // "later" starts at 4_100, outside 0..<4_000
    // The held word lands in the next segment.
    h.src.push(speechMs: 6_000..<10_000, silenceMs: 10_000..<12_000)
    h.tr.push(TranscriptResult(text: "", words: [], range: MsRange(start: 10_000, end: 10_000), isFinal: true))
    let next = try await firstEvent(events) { if case .segmentClosed = $0 { true } else { false } }
    guard case .segmentClosed(let seg2) = next else { return }
    #expect(seg2.words.map(\.text) == ["later"])
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

@Test func speakingCommandsAreNoOpsThatLog() async throws {
    let h = Harness()
    let events = try await h.vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    await h.vs.say("hello"); await h.vs.acknowledge(); await h.vs.interrupt()
    #expect(h.log.all.count == 3)
    #expect(try await collect(events, count: 1, timeoutMs: 200).isEmpty)
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
