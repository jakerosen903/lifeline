import Foundation
import Testing
@testable import LifelineKit

/// The worker sorts recordings that have ended; the fixture leaves them open, so end them.
private func ended(_ store: ExtractionStore, _ id: SessionID) throws {
    var session = try #require(try store.sessions.fetch(id)); session.endedAt = .now; try store.sessions.update(session)
}

private func gardenOutput() -> ExtractorOutput {
    ExtractorOutput(memories: [MemoryOut(ref: "m1", kind: .event, title: "The pomegranate tree", quote: "had a pomegranate tree",
                                         segmentSpan: WordSpan(startWord: 2, endWord: 5), peopleRefs: [], placeText: nil, anchors: [],
                                         collectionHint: nil, chapterHint: nil, confidence: 0.9)],
                    mentions: [], flags: .none)
}

@Test func launchWorkerReenqueuesPendingSegments() async throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (older, _) = try StoreFixtures.session(in: store.sessions, segments: ["the garden had a pomegranate tree"])
    let (newer, newerSegs) = try StoreFixtures.session(in: store.sessions, segments: ["the garden had a pomegranate tree", "my sister climbed it"])
    try ended(store, older); try ended(store, newer)
    try store.sessions.setStatus(.extracted, for: newerSegs[1].id)
    let service = FakeExtractionService([.success(gardenOutput()), .success(gardenOutput())])
    let worker = SortingWorker(store: store, service: service)
    let done = await worker.start()
    #expect(done == 2, "one pending segment in each session")
    #expect(try store.sessions.segments(in: older, status: .pending).isEmpty)
    #expect(try store.sessions.segments(in: newer, status: .pending).isEmpty)
    #expect(try store.candidates.pending(in: older).count == 1)
    #expect(try store.candidates.pending(in: newer).count == 1)
    #expect(try store.sessions.sessionsWithPendingSegments().isEmpty)
}

@Test func workerSkipsSessionsBeingDeleted() async throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (doomed, _) = try StoreFixtures.session(in: store.sessions, segments: ["the garden had a pomegranate tree"])
    let (kept, _) = try StoreFixtures.session(in: store.sessions, segments: ["the garden had a pomegranate tree"])
    try ended(store, doomed); try ended(store, kept)
    let service = FakeExtractionService([.success(gardenOutput()), .success(gardenOutput())])
    let worker = SortingWorker(store: store, service: service)
    await worker.cancel(session: doomed)
    _ = await worker.start()
    #expect(service.requests.count == 1)
    #expect(try store.sessions.segments(in: doomed, status: .pending).count == 1)
    #expect(try store.sessions.segments(in: kept, status: .pending).isEmpty)
}

@Test func workerWithNoKeyStopsAfterOneFailure() async throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (two, _) = try StoreFixtures.session(in: store.sessions, segments: ["one two three", "four five six"])
    try ended(store, two)
    let service = FakeExtractionService([.failure(.noKey), .failure(.noKey), .failure(.noKey)])
    let worker = SortingWorker(store: store, service: service)
    let done = await worker.start()
    #expect(done == 0 && service.requests.count == 1, "no key: one try, then leave everything pending for next time")
}

@Test func startWhileRunningIsANoOp() async throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (slow, _) = try StoreFixtures.session(in: store.sessions, segments: ["the garden had a pomegranate tree", "my sister climbed it"])
    try ended(store, slow)
    let service = FakeExtractionService([.success(gardenOutput()), .success(gardenOutput())])
    service.delay.withLock { $0 = .milliseconds(300) }
    let reporter = SortingReporter()
    let worker = SortingWorker(store: store, service: service, reporter: reporter)
    async let first = worker.start()
    try await Task.sleep(for: .milliseconds(100))
    #expect(reporter.snapshot().active, "the worker reports itself active")
    let second = await worker.start()
    #expect(second == 0, "a second start while a pass runs does nothing")
    #expect(await first == 2)
    #expect(service.requests.count == 2, "each segment was sent once")
    #expect(!reporter.snapshot().active)
}

@Test func workerReportsANoKeyFailure() async throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (one, _) = try StoreFixtures.session(in: store.sessions, segments: ["the garden had a pomegranate tree"])
    try ended(store, one)
    let reporter = SortingReporter()
    let worker = SortingWorker(store: store, service: FakeExtractionService([.failure(.noKey)]), reporter: reporter)
    _ = await worker.start()
    #expect(reporter.snapshot().lastFailure == .noKey)
}

@Test func workerSkipsASessionStillRecording() async throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (live, _) = try StoreFixtures.session(in: store.sessions, segments: ["the garden had a pomegranate tree"])
    let (done, _) = try StoreFixtures.session(in: store.sessions, segments: ["my sister climbed it"])
    try ended(store, done)
    let service = FakeExtractionService([.success(gardenOutput()), .success(gardenOutput())])
    let worker = SortingWorker(store: store, service: service)
    #expect(await worker.start() == 1, "the live session's queue owns its segments; the ended one is sorted")
    let stillPending = try store.sessions.segments(in: live, status: .pending).count
    let sorted = try store.sessions.segments(in: done, status: .pending).isEmpty
    #expect(stillPending == 1 && sorted)
}
