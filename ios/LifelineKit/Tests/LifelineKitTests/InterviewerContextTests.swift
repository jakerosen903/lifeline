import Testing
@testable import LifelineKit

private func segment(_ index: Int, _ text: String, session: SessionID = SessionID()) -> Segment {
    Segment(id: SegmentID(), sessionID: session, index: index, startMs: index * 1_000, endMs: index * 1_000 + 900, text: text, status: .pending)
}

private func turn(_ text: String, at startMs: Int, session: SessionID) -> InterviewerTurn {
    InterviewerTurn(id: InterviewerTurnID(), sessionID: session, kind: .question, source: .model, text: text, startMs: startMs, endMs: nil, interrupted: false)
}

@Test func newestFirstWithinTheBudget() {
    let session = SessionID()
    let newest = segment(2, String(repeating: "c", count: 40), session: session)   // 10 tokens
    let middle = segment(1, String(repeating: "b", count: 40), session: session)   // 10
    let oldest = segment(0, String(repeating: "a", count: 40), session: session)   // 10
    let request = InterviewerContext.build(session: session, segments: [newest, middle, oldest], excluded: [], opening: "Hello", stage: .open, turns: [], tokenBudget: 20)
    #expect(request.segments == [newest.text, middle.text])
    #expect(request.opening == "Hello")
    #expect(request.stage == .open)
}

@Test func theNewestSegmentIsKeptEvenOverTheBudget() {
    let session = SessionID()
    let big = segment(1, String(repeating: "x", count: 400), session: session)
    let small = segment(0, "hi", session: session)
    let request = InterviewerContext.build(session: session, segments: [big, small], excluded: [], opening: "", stage: .open, turns: [], tokenBudget: 10)
    #expect(request.segments == [big.text])
}

@Test func anExcludedSegmentIsLeftOut() {
    let session = SessionID()
    let secret = segment(1, "private", session: session)
    let plain = segment(0, "plain", session: session)
    let request = InterviewerContext.build(session: session, segments: [secret, plain], excluded: [secret.id], opening: "", stage: .open, turns: [])
    #expect(request.segments == ["plain"])
}

@Test func anotherSessionsSegmentsAreDroppedEvenIfFirst() {
    let session = SessionID()
    let mine = segment(1, "mine", session: session)
    let theirs = segment(2, "theirs", session: SessionID())
    let request = InterviewerContext.build(session: session, segments: [theirs, mine], excluded: [], opening: "", stage: .open, turns: [])
    #expect(request.segments == ["mine"])
}

@Test func callerOrderDoesNotMatter() {
    let session = SessionID()
    let old = segment(0, "old", session: session), new = segment(1, "new", session: session)
    let request = InterviewerContext.build(session: session, segments: [old, new], excluded: [], opening: "", stage: .open, turns: [])
    #expect(request.segments == ["new", "old"])
}

@Test func whenTheNewestIsExcludedTheNextIsAlwaysIncluded() {
    let session = SessionID()
    let newest = segment(2, "n", session: session)
    let next = segment(1, String(repeating: "y", count: 400), session: session)
    let oldest = segment(0, "o", session: session)
    let request = InterviewerContext.build(session: session, segments: [newest, next, oldest], excluded: [newest.id], opening: "", stage: .open, turns: [], tokenBudget: 10)
    #expect(request.segments == [next.text])
}

@Test func budgetSumsCharactersWithoutRoundingEachSegment() {
    let session = SessionID()
    // Three segments of 3 characters: 9 characters pass a budget of 2 (8 characters) when summed; rounding each to 0 tokens would let all three in.
    let segs = (0..<3).map { segment($0, "abc", session: session) }
    let request = InterviewerContext.build(session: session, segments: segs, excluded: [], opening: "", stage: .open, turns: [], tokenBudget: 3)
    #expect(request.segments.count == 3)
    let tight = InterviewerContext.build(session: session, segments: segs, excluded: [], opening: "", stage: .open, turns: [], tokenBudget: 2)
    #expect(tight.segments.count == 2)
}

@Test func recentTurnsAreTheLastThreeOldestFirst() {
    let session = SessionID()
    let turns = [turn("d", at: 4_000, session: session), turn("a", at: 1_000, session: session), turn("c", at: 3_000, session: session),
                 turn("b", at: 2_000, session: session), turn("x", at: 5_000, session: SessionID())]
    let request = InterviewerContext.build(session: session, segments: [], excluded: [], opening: "", stage: .windDown, turns: turns)
    #expect(request.recentTurns == ["b", "c", "d"])
    #expect(request.stage == .windDown)
}

@Test func theRequestNamesItsNewestSegment() throws {
    let session = SessionID()
    let older = segment(0, "older", session: session)
    let newer = segment(1, "newer", session: session)
    let request = InterviewerContext.build(session: session, segments: [older, newer], excluded: [], opening: "", stage: .open, turns: [])
    #expect(request.newestSegment == newer.id)
    let withoutNewer = InterviewerContext.build(session: session, segments: [older, newer], excluded: [newer.id], opening: "", stage: .open, turns: [])
    #expect(withoutNewer.newestSegment == older.id, "an excluded segment is never named")
    #expect(!(try request.userMessage()).contains(newer.id.rawValue), "the id is not sent")
}
