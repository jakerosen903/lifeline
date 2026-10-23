import Foundation
import Testing
@testable import LifelineKit

@Test func vectorRoundTripsAndUpsertReplaces() throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (_, segments) = try StoreFixtures.session(in: store.sessions)
    let candidate = StoreFixtures.candidate(segments[0].id)
    try store.candidates.insert(candidate)
    let memory = StoreFixtures.memory(from: candidate.id)
    try store.memories.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segments[0].id, startMs: 0, endMs: 500, order: 0)],
                              people: [], places: [], anchors: [])
    try store.embeddings.upsert(memory: memory.id, model: "nl-en-512", vector: [0.1, 0.2, 0.3])
    let first = try #require(try store.embeddings.vector(of: memory.id))
    #expect(first.model == "nl-en-512" && first.vector == [0.1, 0.2, 0.3])
    try store.embeddings.upsert(memory: memory.id, model: "nl-en-512", vector: [1, 0, 0])
    let all = try store.embeddings.all(model: "nl-en-512")
    #expect(all.count == 1 && all[0].0 == memory.id && all[0].1 == [1, 0, 0])
    #expect(try store.embeddings.memoryIDsWithRows() == [memory.id])
    #expect(try store.embeddings.all(model: "other").isEmpty)
    try store.embeddings.delete(memory: memory.id)
    #expect(try store.embeddings.vector(of: memory.id) == nil)
}

@Test func spansInASessionIncludeLaterSpans() throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (session1, segs1) = try StoreFixtures.session(in: store.sessions)
    let (session2, segs2) = try StoreFixtures.session(in: store.sessions, segments: ["we talked about the tree again"])
    let c1 = StoreFixtures.candidate(segs1[0].id)
    let c2 = StoreFixtures.candidate(segs2[0].id)
    try store.candidates.insert(c1); try store.candidates.insert(c2)
    let a = StoreFixtures.memory(from: c1.id)
    try store.memories.insert(a, spans: [MemorySpan(memoryID: a.id, segmentID: segs1[0].id, startMs: 0, endMs: 500, order: 0)],
                              people: [], places: [], anchors: [])
    #expect(try store.memories.nextSpanOrder(of: a.id) == 1)
    let later = MemorySpan(memoryID: a.id, segmentID: segs2[0].id, startMs: 0, endMs: 900, order: 1, titleText: "The tree again", candidateID: c2.id)
    try store.memories.insertSpan(later)
    let inTwo = try store.memories.spans(in: session2)
    #expect(inTwo.map { $0.0.id } == [a.id] && inTwo.first?.1.order == 1 && inTwo.first?.1.titleText == "The tree again" && inTwo.first?.1.candidateID == c2.id)
    let inOne = try store.memories.spans(in: session1)
    #expect(inOne.map { $0.1.order } == [0])
    #expect(try store.memories.nextSpanOrder(of: a.id) == 2)
    try store.memories.updateFields(a.id, title: "New", summaryQuote: "new words", createdFromCandidateID: c2.id)
    let updated = try #require(try store.memories.fetch(a.id))
    #expect(updated.title == "New" && updated.summaryQuote == "new words" && updated.createdFromCandidateID == c2.id)
    try store.memories.deleteSpans(of: a.id)
    #expect(try store.memories.spans(of: a.id).isEmpty)
}
