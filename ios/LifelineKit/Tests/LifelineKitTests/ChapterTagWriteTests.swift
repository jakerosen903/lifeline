import Foundation
import GRDB
import Testing
@testable import LifelineKit

// The chapter tag's write path (final review I1, I2, M2): a tag and its prune commit as one
// write, a session delete prunes the chapter it emptied, and a new chapter takes the next order.

/// Counts the commits that changed at least one row. A read and an empty write do not count.
private final class CommitCounter: TransactionObserver, @unchecked Sendable {
    private(set) var commits = 0
    private var changed = false
    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool { true }
    func databaseDidChange(with event: DatabaseEvent) { changed = true }
    func databaseDidCommit(_ db: Database) { if changed { commits += 1 }; changed = false }
    func databaseDidRollback(_ db: Database) { changed = false }
}

private struct Env {
    let db: AppDatabase, store: ExtractionStore, actions: ChapterActions, session: SessionID, segment: Segment
    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        actions = ChapterActions(store: store)
        (session, _) = try StoreFixtures.session(in: store.sessions, segments: ["we lived on Elm Street for years"])
        segment = try store.sessions.segments(in: session)[0]
    }

    func memory(_ title: String) throws -> Memory {
        let card = StoreFixtures.candidate(segment.id, ordinal: try store.memories.allMemories().count)
        try store.candidates.insert(card)
        let m = StoreFixtures.memory(from: card.id, title: title)
        try store.memories.insert(m, spans: [MemorySpan(memoryID: m.id, segmentID: segment.id, startMs: 0, endMs: 1000, order: 0)], people: [], places: [], anchors: [])
        return m
    }

    /// The commits that `body` made.
    func commits(_ body: () throws -> Void) throws -> Int {
        let counter = CommitCounter()
        db.writer.add(transactionObserver: counter)
        defer { db.writer.remove(transactionObserver: counter) }
        try body()
        return counter.commits
    }
}

@Test func addingToAChapterTagsAndPrunesInOneWrite() throws {
    let env = try Env()
    let untitled = try env.store.chapters.insertChapter(title: nil)
    let target = try env.store.chapters.insertChapter(title: "Maple Street")
    let m = try env.memory("Fence")
    try env.actions.add(m.id, to: untitled.id)
    let commits = try env.commits { try env.actions.add(m.id, to: target.id) }
    #expect(commits == 1)
    #expect(try env.store.chapters.chapter(id: untitled.id) == nil)
    #expect(try env.store.memories.fetch(m.id)?.chapterID == target.id)
}

@Test func addingToANewNameMakesTagsAndPrunesInOneWrite() throws {
    let env = try Env()
    let untitled = try env.store.chapters.insertChapter(title: nil)
    let m = try env.memory("Fence")
    try env.actions.add(m.id, to: untitled.id)
    var made: Chapter?
    let commits = try env.commits { made = try env.actions.add(m.id, toChapterNamed: "Maple Street") }
    #expect(commits == 1)
    let chapter = try #require(made)
    #expect(try env.store.chapters.chapter(id: untitled.id) == nil)
    #expect(try env.store.memories.fetch(m.id)?.chapterID == chapter.id)
}

@Test func takingOutClearsAndPrunesInOneWrite() throws {
    let env = try Env()
    let untitled = try env.store.chapters.insertChapter(title: nil)
    let m = try env.memory("Fence")
    try env.actions.add(m.id, to: untitled.id)
    let commits = try env.commits { try env.actions.takeOut(m.id) }
    #expect(commits == 1)
    #expect(try env.store.chapters.chapter(id: untitled.id) == nil)
}

@Test func deletingASessionPrunesTheUntitledChapterItEmptied() throws {
    let env = try Env()
    let untitled = try env.store.chapters.insertChapter(title: nil)
    let named = try env.store.chapters.insertChapter(title: "Maple Street")
    let a = try env.memory("Fence"), b = try env.memory("Porch")
    try env.actions.add(a.id, to: untitled.id)
    try env.actions.add(b.id, to: named.id)
    try env.store.sessions.deleteSession(env.session)
    #expect(try env.store.memories.fetch(a.id) == nil)
    #expect(try env.store.chapters.chapter(id: untitled.id) == nil)
    #expect(try env.store.chapters.chapter(id: named.id) != nil, "a named chapter stays, empty")
}

@Test func aNewChapterTakesTheOrderAfterTheLastOne() throws {
    let env = try Env()
    #expect(try env.store.chapters.insertChapter(title: "Elm").order == 0)
    let second = try env.store.chapters.insertChapter(title: "Maple Street")
    _ = try env.store.chapters.insertChapter(title: "Swim team")
    _ = try env.actions.remove(second.id)
    let fourth = try env.store.chapters.insertChapter(title: "College")
    #expect(fourth.order == 3)
    let orders = try env.store.chapters.chapters().map(\.order)
    #expect(Set(orders).count == orders.count, "no two chapters share an order")
}
