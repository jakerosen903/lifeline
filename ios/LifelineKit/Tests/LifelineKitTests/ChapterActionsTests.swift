import Foundation
import Testing
@testable import LifelineKit

// Chapters, Task 4: what a person does to a chapter. The tag write path lives in ChapterActions.

private struct Env {
    let store: ExtractionStore, actions: ChapterActions, segment: Segment
    init() throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = ChapterActions(store: store)
        let (session, _) = try StoreFixtures.session(in: store.sessions, segments: ["we lived on Elm Street for years"])
        segment = try store.sessions.segments(in: session)[0]
    }

    func memory(_ title: String, range: TimeRange = .unplaced) throws -> Memory {
        let card = StoreFixtures.candidate(segment.id, ordinal: try store.memories.allMemories().count)
        try store.candidates.insert(card)
        let m = StoreFixtures.memory(from: card.id, title: title)
        try store.memories.insert(m, spans: [MemorySpan(memoryID: m.id, segmentID: segment.id, startMs: 0, endMs: 1000, order: 0)], people: [], places: [], anchors: [])
        if range.isPlaced { try store.memories.updateRange(m.id, range) }
        return try #require(try store.memories.fetch(m.id))
    }

    func chapter(_ title: String?, range: TimeRange = .unplaced) throws -> Chapter {
        let c = try store.chapters.insertChapter(title: title)
        if range.isPlaced { try store.chapters.setRange(c.id, range) }
        return try #require(try store.chapters.chapter(id: c.id))
    }

    func tag(_ m: Memory) throws -> ChapterID? { try store.memories.fetch(m.id)?.chapterID }
}

@Test func renameTrimsAndSaves() throws {
    let env = try Env()
    let c = try env.chapter("Elm")
    #expect(try env.actions.rename(c.id, to: "  Maple St ") == .renamed)
    #expect(try env.store.chapters.chapter(id: c.id)?.title == "Maple St")
}

@Test func renameToNothingIsRefused() throws {
    let env = try Env()
    let c = try env.chapter("Elm")
    #expect(try env.actions.rename(c.id, to: "   ") == .empty)
    #expect(try env.store.chapters.chapter(id: c.id)?.title == "Elm")
}

@Test func renameToAnotherChaptersNameIsRefused() throws {
    let env = try Env()
    _ = try env.chapter("Maple Street")
    let second = try env.chapter("Swim team")
    #expect(try env.actions.rename(second.id, to: "maple street.") == .taken)
    #expect(try env.store.chapters.chapter(id: second.id)?.title == "Swim team")
    #expect(try env.actions.rename(second.id, to: "SWIM Team") == .renamed)
    #expect(try env.store.chapters.chapter(id: second.id)?.title == "SWIM Team")
}

@Test func sayWhenStoresTheRangeAsStated() throws {
    let env = try Env()
    let c = try env.chapter("Elm")
    try env.actions.sayWhen(c.id, .stated(between: 2008, and: 2012))
    #expect(try env.store.chapters.chapter(id: c.id)?.statedYears == .stated(between: 2008, and: 2012))

    var guess = TimeRange.stated(between: 1990, and: 1994)
    guess.origin = .inferred
    try env.actions.sayWhen(c.id, guess)
    let stored = try #require(try env.store.chapters.chapter(id: c.id)?.range)
    #expect(stored.origin == .stated)
    #expect(try env.store.chapters.chapter(id: c.id)?.statedYears != nil)
}

private func filledChapter(_ env: Env) throws -> (chapter: Chapter, a: Memory, b: Memory, story: Story) {
    let c = try env.chapter("Maple Street", range: .stated(between: 1998, and: 2001))
    let a = try env.memory("Fence"), b = try env.memory("Porch")
    try env.actions.add(a.id, to: c.id)
    try env.actions.add(b.id, to: c.id)
    let story = try env.store.stories.insert(title: "Summer", chapterID: c.id)
    return (c, a, b, story)
}

@Test func removeTakesTheChapterAndClearsItsTags() throws {
    let env = try Env()
    let f = try filledChapter(env)
    let receipt = try #require(try env.actions.remove(f.chapter.id))
    #expect(try env.store.chapters.chapter(id: f.chapter.id) == nil)
    #expect(try env.tag(f.a) == nil && env.tag(f.b) == nil)
    #expect(try env.store.memories.fetch(f.a.id) != nil)
    #expect(try env.store.stories.story(id: f.story.id)?.chapterID == nil)
    #expect(receipt.chapter == f.chapter)
    #expect(Set(receipt.members) == [f.a.id, f.b.id])
    #expect(receipt.stories == [f.story.id])
}

@Test func removeOfAMissingChapterReturnsNothing() throws {
    let env = try Env()
    #expect(try env.actions.remove(ChapterID()) == nil)
}

@Test func undoPutsEverythingBack() throws {
    let env = try Env()
    let f = try filledChapter(env)
    let receipt = try #require(try env.actions.remove(f.chapter.id))
    try env.actions.undoRemove(receipt)
    #expect(try env.store.chapters.chapter(id: f.chapter.id) == f.chapter)
    #expect(try env.tag(f.a) == f.chapter.id && env.tag(f.b) == f.chapter.id)
    #expect(try env.store.stories.story(id: f.story.id)?.chapterID == f.chapter.id)
}

@Test func undoSkipsAMemberThatWasDeleted() throws {
    let env = try Env()
    let f = try filledChapter(env)
    let receipt = try #require(try env.actions.remove(f.chapter.id))
    try env.store.memories.delete(f.a.id)
    try env.actions.undoRemove(receipt)
    #expect(try env.store.chapters.chapter(id: f.chapter.id) != nil)
    #expect(try env.tag(f.b) == f.chapter.id)
}

@Test func undoSkipsAMemberTaggedElsewhere() throws {
    let env = try Env()
    let f = try filledChapter(env)
    let other = try env.chapter("Swim team")
    let receipt = try #require(try env.actions.remove(f.chapter.id))
    try env.actions.add(f.a.id, to: other.id)
    try env.actions.undoRemove(receipt)
    #expect(try env.tag(f.a) == other.id)
    #expect(try env.tag(f.b) == f.chapter.id)
}

@Test func undoTwiceIsHarmless() throws {
    let env = try Env()
    let f = try filledChapter(env)
    let receipt = try #require(try env.actions.remove(f.chapter.id))
    try env.actions.undoRemove(receipt)
    try env.actions.undoRemove(receipt)
    #expect(try env.store.chapters.chapters().count == 1)
    #expect(try env.tag(f.a) == f.chapter.id)
}

@Test func addToANewNameMakesTheChapter() throws {
    let env = try Env()
    let m = try env.memory("Fence")
    let c = try #require(try env.actions.add(m.id, toChapterNamed: "  Maple Street "))
    #expect(c.title == "Maple Street")
    #expect(try env.tag(m) == c.id)
}

@Test func addToAnExistingNameReusesIt() throws {
    let env = try Env()
    let existing = try env.chapter("Maple Street")
    let m = try env.memory("Fence")
    let c = try #require(try env.actions.add(m.id, toChapterNamed: "maple street"))
    #expect(c.id == existing.id)
    #expect(try env.store.chapters.chapters().count == 1)
}

@Test func addWithAnEmptyNameCreatesNothing() throws {
    let env = try Env()
    let first = try env.chapter("Elm")
    let m = try env.memory("Fence")
    try env.actions.add(m.id, to: first.id)
    #expect(try env.actions.add(m.id, toChapterNamed: "  ") == nil)
    #expect(try env.store.chapters.chapters().count == 1)
    #expect(try env.tag(m) == first.id)
}

@Test func addMovesTheTagAndPrunesTheChapterItLeft() throws {
    let env = try Env()
    let untitled = try env.chapter(nil)
    let target = try env.chapter("Maple Street")
    let m = try env.memory("Fence")
    try env.actions.add(m.id, to: untitled.id)
    try env.actions.add(m.id, to: target.id)
    #expect(try env.store.chapters.chapter(id: untitled.id) == nil)
    #expect(try env.tag(m) == target.id)
}

@Test func takeOutClearsTheTagAndPrunes() throws {
    let env = try Env()
    let untitled = try env.chapter(nil)
    let named = try env.chapter("Maple Street")
    let a = try env.memory("Fence"), b = try env.memory("Porch")
    try env.actions.add(a.id, to: untitled.id)
    try env.actions.add(b.id, to: named.id)
    try env.actions.takeOut(a.id)
    try env.actions.takeOut(b.id)
    #expect(try env.tag(a) == nil && env.tag(b) == nil)
    #expect(try env.store.chapters.chapter(id: untitled.id) == nil)
    #expect(try env.store.chapters.chapter(id: named.id) != nil)
}

@Test func deletingTheLastMemberPrunesAnUntitledChapter() throws {
    let env = try Env()
    let untitled = try env.chapter(nil)
    let m = try env.memory("Fence")
    try env.actions.add(m.id, to: untitled.id)
    try env.store.memories.delete(m.id)   // the call the Timeline's "Delete…" makes
    #expect(try env.store.chapters.chapter(id: untitled.id) == nil)
}

@Test func aMomentDatedOutsideTheStatedYearsKeepsItsTag() throws {
    let env = try Env()
    let c = try env.chapter("Elm", range: .stated(between: 2008, and: 2012))
    let m = try env.memory("Fence", range: .stated(year: 1990))
    try env.actions.add(m.id, to: c.id)
    _ = try ResolverRunner(store: env.store).run()
    #expect(try env.tag(m) == c.id)
}

@Test func aNameOfOnlyPunctuationIsNotUsable() {
    #expect(ChapterActions.isUsableName("Maple Street"))
    #expect(ChapterActions.isUsableName("C++"))
    #expect(!ChapterActions.isUsableName(""))
    #expect(!ChapterActions.isUsableName("   "))
    #expect(!ChapterActions.isUsableName(" ...!? "))
    #expect(!ChapterActions.isUsableName("“”"))
}
