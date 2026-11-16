import Foundation
import Testing
@testable import LifelineKit

/// A title names one story (audit F14): a hint joins the story that already has the title, two
/// stories can be merged, and copies made before the fix are joined once.
private struct Env {
    let store: ExtractionStore, actions: CandidateActions
    init() throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = CandidateActions(store: store)
    }

    /// A kept moment in a session of its own, in no story.
    func kept(_ text: String, kind: MemoryKind = .event) throws -> Memory {
        let (_, segs) = try StoreFixtures.session(in: store.sessions, segments: [text])
        let words = text.split(separator: " ").count
        let out = MemoryOut(ref: "m1", kind: kind, title: text, quote: text, segmentSpan: WordSpan(startWord: 0, endWord: words - 1),
                            peopleRefs: [], placeText: nil, anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return try actions.acceptMemory(c, joinStory: false).memory
    }

    func members(_ story: StoryID) throws -> [MemoryID] { try store.stories.members(of: story).map(\.id) }
}

@Test func threeHintsWithOneTitleMakeOneStory() throws {
    let env = try Env()
    let a = try env.kept("we packed the car"), b = try env.kept("the tire went flat"), c = try env.kept("we saw the ocean")
    let first = try env.actions.acceptStoryHint("The road trip", for: a.id)
    let second = try env.actions.acceptStoryHint("the road trip.", for: b.id)
    let third = try env.actions.acceptStoryHint("  The Road Trip ", for: c.id)
    #expect(second.id == first.id && third.id == first.id, "the same title, however it is typed, names the same story")
    #expect(try env.store.stories.stories().count == 1)
    #expect(try env.members(first.id) == [a.id, b.id, c.id], "each joins at the end")
    #expect(try env.store.stories.story(id: first.id)?.title == "The road trip", "the first spelling stays")
}

@Test func aDifferentTitleStillMakesItsOwnStory() throws {
    let env = try Env()
    let a = try env.kept("we packed the car"), b = try env.kept("the school play")
    let trip = try env.actions.acceptStoryHint("The road trip", for: a.id)
    let play = try env.actions.acceptStoryHint("The school play", for: b.id)
    #expect(trip.id != play.id)
    #expect(try env.store.stories.stories().count == 2)
}

@Test func aHintOnAStoryMemberJoinsItsStoryToTheNamedOne() throws {
    let env = try Env()
    let a = try env.kept("we packed the car"), b = try env.kept("the tire went flat"), c = try env.kept("we saw the ocean")
    let trip = try env.actions.acceptStoryHint("The road trip", for: a.id)
    let other = try env.actions.createStory(title: nil, containing: [b.id, c.id])
    let result = try env.actions.acceptStoryHint("The road trip", for: b.id)
    #expect(result.id == trip.id)
    #expect(try env.store.stories.story(id: other.id) == nil, "the member's story joined the named one and is gone")
    #expect(try env.members(trip.id) == [a.id, b.id, c.id], "its members keep their order, after the ones already there")
}

@Test func aHintThatNamesTheMembersOwnStoryOnlyRenamesIt() throws {
    let env = try Env()
    let a = try env.kept("we packed the car")
    let trip = try env.actions.acceptStoryHint("The road trip", for: a.id)
    let again = try env.actions.acceptStoryHint("THE ROAD TRIP", for: a.id)
    #expect(again.id == trip.id && again.title == "THE ROAD TRIP")
    #expect(try env.store.stories.stories().count == 1 && (try env.members(trip.id)) == [a.id])
}

@Test func untitledStoriesNeverMatchATitle() throws {
    let env = try Env()
    let a = try env.kept("we packed the car"), b = try env.kept("the tire went flat"), c = try env.kept("we saw the ocean")
    _ = try env.actions.createStory(title: nil, containing: [a.id, b.id])
    #expect(try env.store.stories.story(matching: "") == nil)
    #expect(try env.store.stories.story(matching: " ... ") == nil, "an empty key names no story")
    let named = try env.actions.acceptStoryHint("The ocean", for: c.id)
    #expect(try env.store.stories.stories().count == 2 && (try env.members(named.id)) == [c.id])
}

@Test func mergeMovesMembersInOrderAndKeepsTheTargetsTitle() throws {
    let env = try Env()
    let a = try env.kept("we packed the car"), b = try env.kept("the tire went flat"), c = try env.kept("we saw the ocean")
    let target = try env.actions.createStory(title: "The road trip", containing: [a.id])
    let source = try env.actions.createStory(title: "Driving west", containing: [b.id, c.id])
    try env.store.stories.merge(source.id, into: target.id)
    #expect(try env.members(target.id) == [a.id, b.id, c.id])
    #expect(try env.store.stories.story(id: source.id) == nil)
    #expect(try env.store.stories.story(id: target.id)?.title == "The road trip")
    #expect(try env.store.stories.story(of: b.id)?.id == target.id)
}

@Test func mergeWithAMissingOrSameStoryChangesNothing() throws {
    let env = try Env()
    let a = try env.kept("we packed the car")
    let story = try env.actions.createStory(title: "The road trip", containing: [a.id])
    try env.store.stories.merge(story.id, into: story.id)
    try env.store.stories.merge(StoryID(), into: story.id)
    try env.store.stories.merge(story.id, into: StoryID())
    #expect(try env.store.stories.stories().map(\.id) == [story.id])
    #expect(try env.members(story.id) == [a.id])
}

@Test func copiesMadeBeforeTheFixAreJoinedOnce() throws {
    let env = try Env()
    let a = try env.kept("we packed the car"), b = try env.kept("the tire went flat"), c = try env.kept("we saw the ocean")
    let d = try env.kept("the school play"), e = try env.kept("the long walk")
    // As the old code left them: one story for each memory, with one title.
    let first = try env.actions.createStory(title: "The road trip", containing: [a.id])
    _ = try env.actions.createStory(title: "the road trip", containing: [b.id])
    _ = try env.actions.createStory(title: "The road trip.", containing: [c.id])
    let play = try env.actions.createStory(title: "The school play", containing: [d.id])
    let untitled = try env.actions.createStory(title: nil, containing: [e.id])

    let report = try ArchiveRepair.run(env.store)
    #expect(report.joinedStories == [StoryRepository.MergedTitle(title: "The road trip", copies: 3)])
    #expect(report.notice == "Joined 3 copies of “The road trip”.")
    #expect(try env.members(first.id) == [a.id, b.id, c.id])
    #expect(Set(try env.store.stories.stories().map(\.id)) == Set([first.id, play.id, untitled.id]), "other stories are left alone")

    let again = try ArchiveRepair.run(env.store)
    #expect(again.joinedStories.isEmpty && again.notice == nil, "a second run finds nothing to do")
}

@Test func twoRepairedTitlesGiveOneNotice() throws {
    let env = try Env()
    let a = try env.kept("we packed the car"), b = try env.kept("the tire went flat")
    let c = try env.kept("the school play"), d = try env.kept("the costume")
    _ = try env.actions.createStory(title: "The road trip", containing: [a.id])
    _ = try env.actions.createStory(title: "The road trip", containing: [b.id])
    _ = try env.actions.createStory(title: "The play", containing: [c.id])
    _ = try env.actions.createStory(title: "The play", containing: [d.id])
    let report = try ArchiveRepair.run(env.store)
    #expect(report.joinedStories.map(\.copies) == [2, 2])
    #expect(report.notice == "Joined copies of 2 stories that had the same title.")
    #expect(try env.store.stories.stories().count == 2)
}

@Test func anEmptyArchiveNeedsNoRepair() throws {
    let env = try Env()
    let report = try ArchiveRepair.run(env.store)
    #expect(report == ArchiveRepair.Report() && report.notice == nil)
}

// MARK: - Chapters with no title and no memory

@Test func anEmptyUntitledChapterIsRemovedAndANamedOneIsKept() throws {
    let env = try Env()
    let a = try env.kept("we packed the car")
    let untitledEmpty = try env.store.chapters.insertChapter(title: nil)
    let blankEmpty = try env.store.chapters.insertChapter(title: "   ")
    let namedEmpty = try env.store.chapters.insertChapter(title: "The Boston years")
    let untitledWithAMemory = try env.store.chapters.insertChapter(title: nil)
    try env.store.chapters.assign(memory: a.id, toChapter: untitledWithAMemory.id)

    let report = try ArchiveRepair.run(env.store)
    #expect(report.removedChapters == 2)
    let left = Set(try env.store.chapters.chapters().map(\.id))
    #expect(left == Set([namedEmpty.id, untitledWithAMemory.id]), "a named chapter stays; so does one that holds a memory")
    #expect(!left.contains(untitledEmpty.id) && !left.contains(blankEmpty.id))
    #expect(try env.store.memories.fetch(a.id)?.chapterID == untitledWithAMemory.id, "no memory is touched")
}

@Test func movingTheLastMemoryOutRemovesAnUntitledChapter() throws {
    let env = try Env()
    let a = try env.kept("we packed the car")
    let untitled = try env.actions.createChapter(title: nil, containing: a.id)
    let named = try env.actions.createChapter(title: "The Boston years", containing: a.id)
    #expect(try env.store.chapters.chapter(id: untitled.id) == nil, "it emptied when the memory moved, and had no title")
    try env.actions.assign(memory: a.id, toChapter: nil)
    #expect(try env.store.chapters.chapter(id: named.id) != nil, "a named chapter stays when it empties")
}
