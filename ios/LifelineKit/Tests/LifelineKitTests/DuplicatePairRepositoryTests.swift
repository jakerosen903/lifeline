import Testing
import Foundation
@testable import LifelineKit

@Test func pairRepositoryTracksDecisions() throws {
    let db = try AppDatabase.inMemory()
    let memories = MemoryRepository(db)
    let pairs = DuplicatePairRepository(db)
    let (_, segments) = try StoreFixtures.session(in: SessionRepository(db), segments: ["one", "two"])
    let a = try StoreFixtures.memory(in: memories, candidates: CandidateRepository(db), segment: segments[0].id, title: "A")
    let b = try StoreFixtures.memory(in: memories, candidates: CandidateRepository(db), segment: segments[1].id, title: "B")
    let pair = DuplicatePair(id: .init(), aMemoryID: a.id, bMemoryID: b.id, score: 0.9, verdict: .sameMoment, status: .open, decidedAt: nil)
    try pairs.insert(pair)
    #expect(try pairs.decided().isEmpty)
    #expect(try pairs.open(limit: 3) == [pair])
    try pairs.setStatus(pair.id, .separate)
    let decided = try pairs.decided()
    #expect(decided.contains(PairKey(a.id, b.id)) && decided.contains(PairKey(b.id, a.id)))
    #expect(try pairs.open(limit: 3).isEmpty)
    #expect(try pairs.pairs(touching: a.id).map(\.id) == [pair.id])
    #expect(try pairs.pairs(touching: a.id).first?.decidedAt != nil)
}
