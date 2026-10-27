import Testing
@testable import LifelineKit

private func turn(_ session: SessionID, _ kind: TurnKind = .question, text: String = "What happened next?", startMs: Milliseconds) -> InterviewerTurn {
    InterviewerTurn(id: .init(), sessionID: session, kind: kind, source: .model, text: text, startMs: startMs, endMs: nil, interrupted: false)
}

@Test func turnsListInFileOrder() throws {
    let db = try AppDatabase.inMemory()
    let (session, _) = try StoreFixtures.session(in: SessionRepository(db))
    let repo = InterviewerTurnRepository(db)
    let late = turn(session, startMs: 9_000), early = turn(session, .opening, startMs: 1_000), middle = turn(session, .reflection, startMs: 5_000)
    for t in [late, early, middle] { try repo.insert(t) }
    #expect(try repo.turns(in: session) == [early, middle, late])
    #expect(try repo.turns(in: .init()).isEmpty)
}

@Test func turnsWithTheSameStartKeepInsertOrder() throws {
    let db = try AppDatabase.inMemory()
    let (session, _) = try StoreFixtures.session(in: SessionRepository(db))
    let repo = InterviewerTurnRepository(db)
    let turns = (0..<5).map { turn(session, .disclosure, text: "turn \($0)", startMs: 9_000) }
    for t in turns { try repo.insert(t) }
    #expect(try repo.turns(in: session) == turns)
}

@Test func endSetsEndAndInterrupted() throws {
    let db = try AppDatabase.inMemory()
    let (session, _) = try StoreFixtures.session(in: SessionRepository(db))
    let repo = InterviewerTurnRepository(db)
    let spoken = turn(session, startMs: 1_000), cut = turn(session, startMs: 5_000)
    try repo.insert(spoken); try repo.insert(cut)
    try repo.end(spoken.id, atMs: 3_000, interrupted: false)
    try repo.end(cut.id, atMs: 5_800, interrupted: true)
    let stored = try repo.turns(in: session)
    #expect(stored[0].endMs == 3_000 && !stored[0].interrupted)
    #expect(stored[1].endMs == 5_800 && stored[1].interrupted)
    #expect(stored[1].text == cut.text, "ending a turn changes nothing else")
}

@Test func deletingASessionDeletesItsTurns() throws {
    let db = try AppDatabase.inMemory()
    let sessions = SessionRepository(db)
    let (gone, _) = try StoreFixtures.session(in: sessions)
    let (kept, _) = try StoreFixtures.session(in: sessions)
    let repo = InterviewerTurnRepository(db)
    try repo.insert(turn(gone, .opening, startMs: 0)); try repo.insert(turn(kept, .opening, startMs: 0))
    try sessions.deleteSession(gone)
    #expect(try repo.turns(in: gone).isEmpty)
    #expect(try repo.turns(in: kept).count == 1)
}

@Test func aTurnKnowsWhetherItAsks() {
    #expect(TurnKind.allCases.filter(\.isQuestion) == [.opening, .question])
}
