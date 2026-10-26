import Testing
@testable import LifelineKit

private func segment(_ index: Int, _ text: String, session: SessionID = SessionID()) -> Segment {
    Segment(id: SegmentID(), sessionID: session, index: index, startMs: index * 1_000, endMs: index * 1_000 + 900, text: text, status: .pending)
}

private func turn(_ text: String, at startMs: Int) -> InterviewerTurn {
    InterviewerTurn(id: InterviewerTurnID(), sessionID: SessionID(), kind: .question, source: .model, text: text, startMs: startMs, endMs: nil, interrupted: false)
}

@Test func newestFirstWithinTheBudget() {
    let session = SessionID()
    let newest = segment(2, String(repeating: "c", count: 40), session: session)   // 10 tokens
    let middle = segment(1, String(repeating: "b", count: 40), session: session)   // 10
    let oldest = segment(0, String(repeating: "a", count: 40), session: session)   // 10
    let request = InterviewerContext.build(segments: [newest, middle, oldest], excluded: [], opening: "Hello", stage: .open, turns: [], tokenBudget: 20)
    #expect(request.segments == [newest.text, middle.text])
    #expect(request.opening == "Hello")
    #expect(request.stage == .open)
}

@Test func theNewestSegmentIsKeptEvenOverTheBudget() {
    let big = segment(1, String(repeating: "x", count: 400))
    let small = segment(0, "hi")
    let request = InterviewerContext.build(segments: [big, small], excluded: [], opening: "", stage: .open, turns: [], tokenBudget: 10)
    #expect(request.segments == [big.text])
}

@Test func anExcludedSegmentIsLeftOut() {
    let session = SessionID()
    let secret = segment(1, "private", session: session)
    let plain = segment(0, "plain", session: session)
    let request = InterviewerContext.build(segments: [secret, plain], excluded: [secret.id], opening: "", stage: .open, turns: [])
    #expect(request.segments == ["plain"])
}

@Test func nothingFromAnotherSession() {
    let mine = segment(1, "mine")
    let theirs = segment(0, "theirs", session: SessionID())
    let request = InterviewerContext.build(segments: [mine, theirs], excluded: [], opening: "", stage: .open, turns: [])
    #expect(request.segments == ["mine"])
}

@Test func recentTurnsAreTheLastThreeOldestFirst() {
    let turns = [turn("d", at: 4_000), turn("a", at: 1_000), turn("c", at: 3_000), turn("b", at: 2_000)]
    let request = InterviewerContext.build(segments: [], excluded: [], opening: "", stage: .windDown, turns: turns)
    #expect(request.recentTurns == ["b", "c", "d"])
    #expect(request.stage == .windDown)
}
