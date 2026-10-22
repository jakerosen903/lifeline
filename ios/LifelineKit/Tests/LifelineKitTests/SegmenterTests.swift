import Testing
@testable import LifelineKit

private func feed(_ s: inout Segmenter, db: Float, from: Int, count: Int, step: Int = 100) -> [SegmenterEvent] {
    var out: [SegmenterEvent] = []
    for i in 0..<count { out += s.observe(levelDb: db, startMs: from + i * step, durationMs: step) }
    return out
}

private func ended(_ events: [SegmenterEvent]) -> [MsRange] {
    events.compactMap { if case .segmentEnded(let r) = $0 { r } else { nil } }
}

@Test func speechThenLongPauseClosesSegment() {
    var s = Segmenter()
    var ev = feed(&s, db: -20, from: 0, count: 40)          // 4 s speech
    ev += feed(&s, db: -60, from: 4_000, count: 20)         // 2 s silence
    #expect(ev.contains(.speechStarted(atMs: 0)))
    #expect(ended(ev) == [MsRange(start: 0, end: 4_000)])
}

@Test func silenceOnlyProducesNoSegment() {
    var s = Segmenter()
    #expect(feed(&s, db: -70, from: 0, count: 600).isEmpty)
}

@Test func shortBlipDoesNotCloseASegment() {
    var s = Segmenter()
    var ev = feed(&s, db: -20, from: 0, count: 10)          // 1 s speech
    ev += feed(&s, db: -60, from: 1_000, count: 30)
    #expect(ended(ev).isEmpty)
}

@Test func pauseInsideSpeechDoesNotSplit() {
    var s = Segmenter()
    var ev = feed(&s, db: -20, from: 0, count: 30)
    ev += feed(&s, db: -60, from: 3_000, count: 10)         // 1 s pause, under threshold
    ev += feed(&s, db: -20, from: 4_000, count: 20)
    ev += feed(&s, db: -60, from: 6_000, count: 20)
    #expect(ended(ev) == [MsRange(start: 0, end: 6_000)])
    #expect(ev.contains(.pauseObserved(ms: 1_000)))
}

@Test func flushClosesOpenSegment() {
    var s = Segmenter()
    _ = feed(&s, db: -20, from: 0, count: 50)
    #expect(s.flush(atMs: 5_000) == [.segmentEnded(MsRange(start: 0, end: 5_000))])
}

@Test func flushOnShortSpeechProducesNothing() {
    var s = Segmenter()
    _ = feed(&s, db: -20, from: 0, count: 10)
    #expect(s.flush(atMs: 1_000).isEmpty)
    #expect(s.flush(atMs: 1_000).isEmpty)   // idempotent
}

@Test func maxSegmentForcesClose() {
    var s = Segmenter(config: .init(maxSegmentMs: 10_000))
    let ev = feed(&s, db: -20, from: 0, count: 120)
    #expect(ended(ev).first == MsRange(start: 0, end: 10_000))
    #expect(ev.filter { $0 == .speechStarted(atMs: 10_000) }.count == 1)   // next segment opens right away
}

@Test func abandonedShortSpeechDoesNotLeakIntoNextSegment() {
    var s = Segmenter()
    var ev = feed(&s, db: -20, from: 0, count: 10)          // 1 s blip
    ev += feed(&s, db: -60, from: 1_000, count: 30)         // 3 s silence, blip abandoned
    ev += feed(&s, db: -20, from: 4_000, count: 40)         // 4 s speech
    ev += feed(&s, db: -60, from: 8_000, count: 20)
    #expect(ended(ev) == [MsRange(start: 4_000, end: 8_000)])
}

@Test func speechAccumulatesAcrossShortPausesTowardMinimum() {
    // 2 s + 2 s speech with a 1 s pause between is enough (4 s >= 3 s) even though neither run alone is.
    var s = Segmenter()
    var ev = feed(&s, db: -20, from: 0, count: 20)
    ev += feed(&s, db: -60, from: 2_000, count: 10)
    ev += feed(&s, db: -20, from: 3_000, count: 20)
    ev += feed(&s, db: -60, from: 5_000, count: 20)
    #expect(ended(ev) == [MsRange(start: 0, end: 5_000)])
}
