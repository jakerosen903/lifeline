import Testing
@testable import LifelineKit

private let session = SessionID()

private func segment(_ index: Int, startMs: Milliseconds) -> Segment {
    Segment(id: .init(), sessionID: session, index: index, startMs: startMs, endMs: startMs + 2_000, text: "the blue door \(index)", status: .pending)
}

private func turn(_ kind: TurnKind, startMs: Milliseconds) -> InterviewerTurn {
    InterviewerTurn(id: .init(), sessionID: session, kind: kind, source: .fixed, text: "turn at \(startMs)", startMs: startMs, endMs: startMs, interrupted: false)
}

@Test func turnsSitBetweenSegmentsInFileOrder() {
    let first = segment(0, startMs: 1_000), second = segment(1, startMs: 5_000)
    let opening = turn(.opening, startMs: 0), disclosure = turn(.disclosure, startMs: 7_000), windDown = turn(.earlyWindDown, startMs: 7_000)
    #expect(TranscriptItem.merge(segments: [first, second], turns: [opening, disclosure, windDown])
            == [.turn(opening), .segment(first), .segment(second), .turn(disclosure), .turn(windDown)])
}

@Test func aTurnAndASegmentAtTheSameStartPutTheTurnFirst() {
    let first = segment(0, startMs: 0), opening = turn(.opening, startMs: 0)
    #expect(TranscriptItem.merge(segments: [first], turns: [opening]) == [.turn(opening), .segment(first)])
}

@Test func noTurnsIsJustTheSegments() {
    let segments = [segment(0, startMs: 0), segment(1, startMs: 3_000)]
    #expect(TranscriptItem.merge(segments: segments, turns: []) == segments.map(TranscriptItem.segment))
    #expect(TranscriptItem.merge(segments: [], turns: []).isEmpty)
}
