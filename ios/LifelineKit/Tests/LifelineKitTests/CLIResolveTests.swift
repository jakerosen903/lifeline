import Foundation
import Testing
@testable import LifelineKit

@Test func cliResolvePrintsADiff() async throws {
    let dbURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
    let db = try AppDatabase.open(at: dbURL)
    let store = ExtractionStore(db)
    let (session, _) = try StoreFixtures.session(in: store.sessions)
    let segment = try store.sessions.segments(in: session)[0]
    let c = StoreFixtures.candidate(segment.id, payload: "{}")
    try store.candidates.insert(c)
    var memory = StoreFixtures.memory(from: c.id, title: "Mirror Lake")
    memory.range = .unplaced
    try store.memories.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment.id, startMs: 0, endMs: 500, order: 0)], people: [], places: [],
                              anchors: [Anchor(id: .init(), memoryID: memory.id, phrase: "in 2000", relation: .absolute, targetKind: .none, targetID: nil, value: nil, resolved: false)])
    let first = try await CLI.run(["resolve", "--all", "--db", dbURL.path()])
    #expect(first.exitCode == 0)
    #expect(first.output.contains("Mirror Lake\tno date yet\t→\t2000"), Comment(rawValue: first.output))
    #expect(first.output.hasSuffix("1 placed, 0 floating created, 0 questions open\n"), Comment(rawValue: first.output))
    let second = try await CLI.run(["resolve", "--all", "--db", dbURL.path()])
    #expect(second.output == "0 placed, 0 floating created, 0 questions open\n")
    #expect(try await CLI.run(["resolve", "--db", dbURL.path()]).exitCode == 2)
}
