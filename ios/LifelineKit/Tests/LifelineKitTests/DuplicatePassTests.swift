import Foundation
import Testing
@testable import LifelineKit

@Test func duplicatePassWritesVerdicts() async throws {
    var env = try PairEnv()
    let door1 = try env.memory("The blue door", vector: [1, 0, 0])
    let door2 = try env.memory("The blue door", vector: [1, 0, 0])
    let maya = try env.memory("Maya climbed it", vector: [0.8, 0.6, 0])
    let canal = try env.memory("The canal", vector: [0.7, 0.7, 0])
    let matcher = env.matcher()
    try env.indexAll(matcher)
    let log = LogCollector()
    let pass = DuplicatePass(store: env.store, matcher: matcher, reconcile: ScriptedReconcileService(), actions: CandidateActions(store: env.store), log: { log.append($0) })
    let judged = await pass.run()
    let rows = try env.store.pairs.pairs(touching: door1.id) + env.store.pairs.pairs(touching: door2.id) + env.store.pairs.pairs(touching: canal.id)
    let unique = Dictionary(grouping: rows, by: \.id).values.compactMap(\.first)
    #expect(judged == unique.count && judged > 0)
    let sameMoment = unique.filter { $0.verdict == .sameMoment }
    #expect(sameMoment.count == 1 && sameMoment[0].status == .open && sameMoment[0].key == PairKey(door1.id, door2.id))
    let sameStory = unique.filter { $0.verdict == .sameStory }
    #expect(sameStory.count == 2 && sameStory.allSatisfy { $0.status == .open && ($0.aMemoryID == maya.id || $0.bMemoryID == maya.id) })
    #expect(unique.filter { $0.verdict == .different }.allSatisfy { $0.status == .separate && $0.decidedAt != nil })
    #expect(try env.store.pairs.open(limit: 10).count == 3)
    #expect(log.all.contains { $0.contains("[duplicates]") })
    #expect(await pass.run() == 0, "every pair is on file now")
}

@Test func duplicatePassStopsQuietlyWithoutAKey() async throws {
    var env = try PairEnv()
    _ = try env.memory("The blue door", vector: [1, 0])
    _ = try env.memory("The blue door", vector: [1, 0])
    let matcher = env.matcher()
    try env.indexAll(matcher)
    let noKey = AnthropicReconcileService(config: .default, apiKey: { nil }, transport: FakeHTTPTransport([]))
    let pass = DuplicatePass(store: env.store, matcher: matcher, reconcile: noKey, actions: CandidateActions(store: env.store), log: { _ in })
    #expect(await pass.run() == 0)
    #expect(try env.store.pairs.open(limit: 10).isEmpty && (try env.store.pairs.known()).isEmpty)
}
