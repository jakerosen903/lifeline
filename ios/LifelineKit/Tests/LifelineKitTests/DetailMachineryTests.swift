import Foundation
import Testing
@testable import LifelineKit

// M7, PR B: a detail pairs like a memory, never joins a story, and moves between entities by tap.

@Test func detailsTakePartInPairs() throws {
    var env = try PairEnv()
    let a = try env.memory("The house had a blue door", vector: [1, 0, 0])
    let b = try env.memory("Our house had a blue door", vector: [0.99, 0.05, 0])
    try env.store.memories.setKind(a.id, .fact)
    try env.store.memories.setKind(b.id, .fact)
    let matcher = env.matcher()
    try env.indexAll(matcher)
    let found = try PairFinder(store: env.store, matcher: matcher, config: .default).candidates()
    #expect(found.contains { Set([$0.a.id, $0.b.id]) == Set([a.id, b.id]) }, "a fact told twice can merge into one")
}

@Test func aDetailDoesNotJoinAStory() throws {
    var env = try PairEnv()
    let scene = try env.memory("Painting the house", vector: [1, 0, 0])
    let fact = try env.memory("The house had a blue door", vector: [0, 1, 0])
    try env.store.memories.setKind(fact.id, .fact)
    let actions = CandidateActions(store: env.store)
    let story = try actions.createStory(title: "The house", containing: [scene.id, fact.id])
    #expect(try env.store.stories.members(of: story.id).map(\.id) == [scene.id], "stories are for scenes")
    try actions.addToStory(fact.id, story: story.id)
    #expect(try env.store.stories.story(of: fact.id) == nil)

    let other = try env.memory("The garden", vector: [0, 0, 1])
    try actions.addToStory(other.id, story: story.id)
    try actions.setKind(other.id, .feeling)
    #expect(try env.store.stories.story(of: other.id) == nil, "a moment turned feeling leaves its story")
}

@Test func moveDetailBetweenEntities() throws {
    var env = try PairEnv()
    let fact = try env.memory("It had a blue door", vector: [1, 0, 0])
    try env.store.memories.setKind(fact.id, .fact)
    let actions = CandidateActions(store: env.store)
    let house = try env.store.entities.insert(type: .thing, title: "the house")
    let shed = try env.store.entities.insert(type: .thing, title: "the shed")
    try actions.moveDetail(fact.id, to: house.id)
    #expect(try env.store.entities.details(of: house.id).map(\.id) == [fact.id])
    try actions.moveDetail(fact.id, to: shed.id)
    #expect(try env.store.entities.details(of: house.id).isEmpty && env.store.entities.details(of: shed.id).map(\.id) == [fact.id])
    try actions.moveDetail(fact.id, to: nil)
    #expect(try env.store.entities.links(of: fact.id).isEmpty, "nil leaves it under About")

    try actions.moveDetail(fact.id, to: house.id)
    try actions.setKind(fact.id, .event)
    #expect(try env.store.entities.links(of: fact.id).map(\.link.relation) == [.mention], "a moment names the house instead")
    #expect(throws: CandidateActions.Error.wrongKind) { try actions.moveDetail(fact.id, to: shed.id) }
}
