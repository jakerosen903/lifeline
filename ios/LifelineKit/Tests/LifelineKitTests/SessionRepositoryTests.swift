import Foundation
import Testing
@testable import LifelineKit

private func makeSession(startedAt: TimeInterval = 1_000) -> Session {
    Session(id: .init(), startedAt: .init(timeIntervalSince1970: startedAt), endedAt: nil,
            audioPath: "a.m4a", stageLog: "[]", landingChoiceMade: false)
}

@Test func sessionSegmentWordRoundTrip() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let s = makeSession()
    try repo.insert(s)
    let seg = Segment(id: .init(), sessionID: s.id, index: 0, startMs: 0, endMs: 4_200,
                      text: "the house had a blue door", status: .pending)
    let words = ["the", "house", "had", "a", "blue", "door"].enumerated().map {
        Word(segmentID: seg.id, index: $0, text: $1, startMs: $0 * 700, endMs: $0 * 700 + 600)
    }
    try repo.insert(seg, words: words)
    #expect(try repo.segments(in: s.id) == [seg])
    #expect(try repo.words(in: seg.id) == words)
    #expect(try repo.unfinishedSessions().map(\.id) == [s.id])
    #expect(try repo.fetch(s.id) == s)
}

@Test func listSessionsIsNewestFirst() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let first = makeSession(startedAt: 1_000), second = makeSession(startedAt: 2_000)
    try repo.insert(first); try repo.insert(second)
    #expect(try repo.listSessions().map(\.id) == [second.id, first.id])
}

@Test func updateSetsEndedAt() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    var s = makeSession(); try repo.insert(s)
    s.endedAt = .init(timeIntervalSince1970: 3_000)
    try repo.update(s)
    #expect(try repo.fetch(s.id)?.endedAt == s.endedAt)
    #expect(try repo.unfinishedSessions().isEmpty)
}

@Test func segmentsComeBackInIndexOrder() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let s = makeSession(); try repo.insert(s)
    for i in [2, 0, 1] {
        try repo.insert(Segment(id: .init(), sessionID: s.id, index: i, startMs: i * 1000, endMs: i * 1000 + 500, text: "\(i)", status: .pending), words: [])
    }
    #expect(try repo.segments(in: s.id).map(\.index) == [0, 1, 2])
}

@Test func aSessionKeepsItsSubjectAndOrigin() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let maya = try EntityRepository(db).insert(type: .person, title: "Maya")
    let s = Session(id: .init(), startedAt: .init(timeIntervalSince1970: 1_000), endedAt: nil, audioPath: "a.m4a",
                    stageLog: "[]", landingChoiceMade: false, subjectEntityID: maya.id, startedFrom: .page)
    try repo.insert(s)
    let fetched = try #require(try repo.fetch(s.id))
    #expect(fetched.subjectEntityID == maya.id && fetched.startedFrom == .page)
}

@Test func deletingTheSubjectKeepsTheSession() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let entities = EntityRepository(db)
    let maya = try entities.insert(type: .person, title: "Maya")
    let s = Session(id: .init(), startedAt: .init(timeIntervalSince1970: 1_000), endedAt: nil, audioPath: "a.m4a",
                    stageLog: "[]", landingChoiceMade: false, subjectEntityID: maya.id, startedFrom: .page)
    try repo.insert(s)
    try entities.delete(maya.id)
    let fetched = try #require(try repo.fetch(s.id))
    #expect(fetched.subjectEntityID == nil, "the session outlives its subject")
}
