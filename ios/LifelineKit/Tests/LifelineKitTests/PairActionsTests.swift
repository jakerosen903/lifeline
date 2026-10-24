import Foundation
import Testing
@testable import LifelineKit

private func openPair(_ env: PairEnv, _ a: Memory, _ b: Memory) throws -> DuplicatePair {
    let pair = DuplicatePair(id: .init(), aMemoryID: a.id, bMemoryID: b.id, score: 0.95, verdict: .sameMoment, status: .open, decidedAt: nil)
    try env.store.pairs.insert(pair)
    return pair
}

@Test func samePairMergesNewerIntoOlderAndUndoReopens() throws {
    var env = try PairEnv()
    let older = try env.memory("The blue door", vector: [1, 0])
    let newer = try env.memory("Blue door again", vector: [1, 0])
    let pair = try openPair(env, older, newer)
    let actions = CandidateActions(store: env.store)
    let receipt = try actions.samePair(pair)
    #expect(receipt.target == older.id && receipt.before.count == 2)
    #expect(try env.store.memories.fetch(newer.id) == nil)
    #expect(try env.store.memories.spans(of: older.id).count == 2)
    #expect(try env.store.pairs.pair(id: pair.id) == nil, "the row went with the folded memory; nothing can find this pair again")
    try actions.undoPair(receipt, pair: pair)
    #expect(try env.store.memories.fetch(newer.id) != nil && (try env.store.memories.spans(of: older.id)).count == 1)
    #expect(try env.store.pairs.pair(id: pair.id)?.status == .open)
}

@Test func undoPairIsOneTransaction() throws {
    var env = try PairEnv()
    let older = try env.memory("The blue door", vector: [1, 0])
    let newer = try env.memory("Blue door again", vector: [1, 0])
    let pair = try openPair(env, older, newer)
    let actions = CandidateActions(store: env.store)
    let receipt = try actions.samePair(pair)
    // A pair whose other side does not exist fails the foreign key on the last write: the memories must not come back without it.
    let ghost = DuplicatePair(id: .init(), aMemoryID: older.id, bMemoryID: MemoryID(rawValue: "ghost"), score: 0.9, verdict: .sameMoment, status: .open, decidedAt: nil)
    #expect(throws: (any Error).self) { try actions.undoPair(receipt, pair: ghost) }
    #expect(try env.store.memories.fetch(newer.id) == nil && (try env.store.memories.spans(of: older.id)).count == 2, "the merge stands: nothing partial landed")
    #expect(try env.store.pairs.pair(id: ghost.id) == nil)
    // The real undo still works afterwards.
    try actions.undoPair(receipt, pair: pair)
    #expect(try env.store.memories.fetch(newer.id) != nil && (try env.store.pairs.pair(id: pair.id))?.status == .open)
}

@Test func separatePairIsRememberedAndNeverReturns() throws {
    var env = try PairEnv()
    let a = try env.memory("The blue door", vector: [1, 0])
    let b = try env.memory("Blue door again", vector: [1, 0])
    let pair = try openPair(env, a, b)
    try CandidateActions(store: env.store).separatePair(pair)
    #expect(try env.store.pairs.pair(id: pair.id)?.status == .separate)
    #expect(try env.store.pairs.decided().contains(PairKey(b.id, a.id)))
    let matcher = env.matcher()
    try env.indexAll(matcher)
    #expect(try PairFinder(store: env.store, matcher: matcher).candidates().isEmpty, "a declined pair never comes back")
}

@Test func stalePairIsRefused() throws {
    var env = try PairEnv()
    let a = try env.memory("The blue door", vector: [1, 0])
    let b = try env.memory("Blue door again", vector: [1, 0])
    let actions = CandidateActions(store: env.store)
    let gone = try openPair(env, a, b)
    try env.store.memories.delete(b.id)
    #expect(throws: CandidateActions.Error.stale) { try actions.samePair(gone) }
    let c = try env.memory("Third door", vector: [1, 0])
    let decided = try openPair(env, a, c)
    try actions.separatePair(decided)
    #expect(throws: CandidateActions.Error.stale) { try actions.samePair(decided) }
    #expect(throws: CandidateActions.Error.stale) { try actions.separatePair(decided) }
}
