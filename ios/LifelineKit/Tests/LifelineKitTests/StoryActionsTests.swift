import Foundation
import Testing
@testable import LifelineKit

/// Stories: joined on Keep, titled by hint, split and moved by the person (M5).
private struct Env {
    let store: ExtractionStore, actions: CandidateActions
    init() throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = CandidateActions(store: store)
    }

    func card(_ text: String, title: String, storyRef: String? = nil) throws -> (SessionID, Candidate) {
        let (session, segs) = try StoreFixtures.session(in: store.sessions, segments: [text])
        let words = text.split(separator: " ").count
        let out = MemoryOut(ref: "m1", kind: .event, title: title, quote: text, segmentSpan: WordSpan(startWord: 0, endWord: words - 1),
                            peopleRefs: [], placeText: nil, anchors: [], storyRef: storyRef, collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return (session, c)
    }

    func kept(_ text: String, title: String, storyRef: String? = nil, joinStory: Bool = true) throws -> Memory {
        try actions.acceptMemory(try card(text, title: title, storyRef: storyRef).1, joinStory: joinStory).memory
    }
}

@Test func keepWithAStoryRefCreatesOrJoins() throws {
    let env = try Env()
    let ref = StoryID()
    let first = try env.kept("the house had a blue door", title: "The blue door", storyRef: ref.rawValue)
    let story = try #require(try env.store.stories.story(id: ref))
    #expect(try env.store.stories.members(of: ref).map(\.id) == [first.id] && story.title == nil)
    let second = try env.kept("Maya climbed it", title: "Maya climbed it", storyRef: ref.rawValue)
    #expect(try env.store.stories.members(of: ref).map(\.id) == [first.id, second.id])
    let alone = try env.kept("we moved away", title: "We moved away", storyRef: ref.rawValue, joinStory: false)
    #expect(try env.store.stories.story(of: alone.id) == nil && (try env.store.stories.members(of: ref)).count == 2)
    #expect(try env.store.stories.stories().count == 1)
}

@Test func keepWithAVanishedStoryRefLandsAlone() throws {
    let env = try Env()
    let ref = StoryID()
    let first = try env.kept("the house had a blue door", title: "The blue door", storyRef: ref.rawValue)
    try env.actions.takeOutOfStory(first.id)
    #expect(try env.store.stories.story(id: ref) == nil, "an emptied story is deleted")
    let later = try env.kept("Maya climbed it", title: "Maya climbed it", storyRef: ref.rawValue)
    #expect(try env.store.stories.members(of: ref).map(\.id) == [later.id], "made again with just this member, nothing dangling")
    #expect(try env.store.stories.story(of: first.id) == nil)
}

@Test func splitMoveTakeOutAndEmptyDeletion() throws {
    let env = try Env()
    let a = try env.kept("one", title: "One")
    let b = try env.kept("two", title: "Two")
    let c = try env.kept("three", title: "Three")
    let chapter = try env.actions.createChapter(title: "Early", containing: a.id)
    let story = try env.actions.createStory(title: "  The thread ", containing: [a.id, b.id, c.id])
    #expect(story.title == "The thread" && story.chapterID == chapter.id, "the chapter comes from the first member")
    #expect(try env.store.stories.members(of: story.id).map(\.id) == [a.id, b.id, c.id])

    #expect(throws: CandidateActions.Error.emptyTitle) { try env.actions.renameStory(story.id, title: "   ") }
    try env.actions.renameStory(story.id, title: "Renamed")
    #expect(try env.store.stories.story(id: story.id)?.title == "Renamed")

    #expect(throws: CandidateActions.Error.nothingToSplit) { try env.actions.splitStory(story.id, taking: []) }
    #expect(throws: CandidateActions.Error.nothingToSplit) { try env.actions.splitStory(story.id, taking: [a.id, b.id, c.id]) }
    let split = try env.actions.splitStory(story.id, taking: [c.id])
    let splitMembers = try env.store.stories.members(of: split.id).map(\.id)
    #expect(split.title == nil && splitMembers == [c.id])
    #expect(try env.store.stories.members(of: story.id).map(\.id) == [a.id, b.id])

    try env.actions.moveToStory(b.id, story: split.id)
    #expect(try env.store.stories.members(of: split.id).map(\.id) == [c.id, b.id] && (try env.store.stories.members(of: story.id)).map(\.id) == [a.id])

    try env.actions.takeOutOfStory(a.id)
    #expect(try env.store.stories.story(id: story.id) == nil, "the emptied story goes")
    try env.store.memories.delete(c.id)
    #expect(try env.store.stories.members(of: split.id).map(\.id) == [b.id])
    try env.store.memories.delete(b.id)
    #expect(try env.store.stories.story(id: split.id) == nil, "deleting the last member deletes the story")
}

@Test func deletingASessionLeavesNoEmptyStory() throws {
    let env = try Env()
    let (session, c) = try env.card("the house had a blue door", title: "The blue door")
    let memory = try env.actions.acceptMemory(c).memory
    let story = try env.actions.createStory(title: nil, containing: [memory.id])
    try env.store.sessions.deleteSession(session)
    #expect(try env.store.memories.fetch(memory.id) == nil && (try env.store.stories.story(id: story.id)) == nil)
}

@Test func groupPairPutsBothInOneStory() throws {
    let env = try Env()
    let a = try env.kept("the house had a blue door", title: "The blue door")
    let b = try env.kept("Maya climbed it", title: "Maya climbed it")
    let c = try env.kept("we moved away", title: "We moved away")
    let pair = DuplicatePair(id: .init(), aMemoryID: a.id, bMemoryID: b.id, score: 0.8, verdict: .sameStory, status: .open, decidedAt: nil)
    try env.store.pairs.insert(pair)
    let story = try env.actions.groupPair(pair)
    #expect(try env.store.stories.members(of: story.id).map(\.id) == [a.id, b.id])
    #expect(try env.store.pairs.pair(id: pair.id)?.status == .grouped)
    #expect(throws: CandidateActions.Error.stale) { try env.actions.groupPair(pair) }
    // A second pair joins the existing story rather than making another.
    let second = DuplicatePair(id: .init(), aMemoryID: c.id, bMemoryID: b.id, score: 0.8, verdict: .sameStory, status: .open, decidedAt: nil)
    try env.store.pairs.insert(second)
    let same = try env.actions.groupPair(second)
    let all = try env.store.stories.members(of: story.id).map(\.id)
    #expect(same.id == story.id && all == [a.id, b.id, c.id])
}
