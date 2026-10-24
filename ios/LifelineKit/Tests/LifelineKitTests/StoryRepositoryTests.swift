import Testing
import Foundation
@testable import LifelineKit

@Test func storyMembershipIsOneStoryPerMemory() throws {
    let db = try AppDatabase.inMemory()
    let memories = MemoryRepository(db)
    let stories = StoryRepository(db)
    let (_, segments) = try StoreFixtures.session(in: SessionRepository(db), segments: ["one", "two"])
    let m1 = try StoreFixtures.memory(in: memories, candidates: CandidateRepository(db), segment: segments[0].id, title: "First")
    let m2 = try StoreFixtures.memory(in: memories, candidates: CandidateRepository(db), segment: segments[1].id, title: "Second")
    let s1 = try stories.insert(title: "One", chapterID: nil)
    let s2 = try stories.insert(title: nil, chapterID: nil)
    try stories.add(memory: m1.id, to: s1.id)
    #expect(throws: (any Error).self) { try stories.add(memory: m1.id, to: s2.id) }
    try stories.remove(memory: m1.id)
    try stories.add(memory: m1.id, to: s2.id)
    try stories.add(memory: m2.id, to: s2.id)
    #expect(try stories.story(of: m1.id)?.id == s2.id)
    #expect(try stories.members(of: s2.id).map(\.id) == [m1.id, m2.id])
    #expect(try stories.stories().count == 2)
    try stories.rename(s2.id, title: "Renamed")
    #expect(try stories.story(id: s2.id)?.title == "Renamed")
    try stories.delete(s2.id)
    #expect(try stories.story(of: m1.id) == nil)
    #expect(try memories.fetch(m1.id) != nil, "deleting a story never deletes a memory")
}

@Test func storyInsertCanTakeAGivenID() throws {
    let db = try AppDatabase.inMemory()
    let stories = StoryRepository(db)
    let id = StoryID()
    let story = try stories.insert(id: id, title: nil, chapterID: nil)
    let fetched = try stories.story(id: id)
    #expect(story.id == id && fetched != nil)
}
