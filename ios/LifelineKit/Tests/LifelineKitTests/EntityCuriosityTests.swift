import Foundation
import Testing
@testable import LifelineKit

// M7, PR B: curiosity about entities asks for a scene, never a date or an opinion.

@Test func entityCuriosityFiresAndStops() throws {
    let store = ExtractionStore(try AppDatabase.inMemory())
    let (session, _) = try StoreFixtures.session(in: store.sessions, segments: ["the house had a blue door", "we painted the house"])
    let segments = try store.sessions.segments(in: session)
    let detail = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[0].id, title: "Blue door")
    try store.memories.setKind(detail.id, .fact)
    let house = try store.entities.insert(type: .thing, title: "the house")
    try store.entities.link(detail.id, house.id, relation: .detail)
    _ = try ResolverRunner(store: store).run()
    let open = try store.curiosity.open().filter { $0.entityID == house.id }
    #expect(open.map(\.text) == ["What do you remember first about the house?"])

    let moment = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[1].id, title: "Painting")
    try store.entities.link(moment.id, house.id, relation: .mention)
    _ = try ResolverRunner(store: store).run()
    #expect(try store.curiosity.open().filter { $0.entityID == house.id }.isEmpty, "a linked moment closes the question")
}

@Test func aDismissedEntityQuestionNeverReturns() throws {
    let store = ExtractionStore(try AppDatabase.inMemory())
    let idea = try store.entities.insert(type: .idea, title: "hard work was everything")
    _ = try ResolverRunner(store: store).run()
    let item = try #require(try store.curiosity.open().first { $0.entityID == idea.id })
    try store.curiosity.setStatus(item.id, .dismissed)
    _ = try ResolverRunner(store: store).run()
    #expect(try store.curiosity.open().filter { $0.entityID == idea.id }.isEmpty)
}

@Test func noEntityQuestionAsksForADateOrAnOpinion() {
    let entities = EntityType.allCases.map { Entity(type: $0, title: "Example") }
    let links = entities.map { MomentEntity(memoryID: MemoryID(), entityID: $0.id, relation: .detail) }
    let names = Dictionary(uniqueKeysWithValues: entities.filter { $0.type == .person }.map { ($0.id, $0.title) })
    let drafts = EntityCuriosity.drafts(entities: entities, links: links, memories: [:], owner: nil, personNames: names)
    #expect(drafts.count == 4)
    for draft in drafts {
        let lower = draft.text.lowercased()
        for word in ["when", "date", "year", "still", "think that", "believe", "right", "wrong", "how long"] {
            #expect(!lower.contains(word), "“\(draft.text)” must not ask for “\(word)”")
        }
        #expect(draft.payoffCount == 1)
    }
}

@Test func theOwnerAndHiddenEntitiesNeverAsk() {
    let owner = Entity(type: .person, title: "Sam")
    var hidden = Entity(type: .idea, title: "secret")
    hidden.hiddenFromTimeline = true
    var excluded = Entity(type: .person, title: "Rosa")
    excluded.excludedFromAI = true
    let bare = Entity(type: .thing, title: "the car")
    #expect(EntityCuriosity.drafts(entities: [owner, hidden, excluded, bare], links: [], memories: [:], owner: owner.id,
                                   personNames: [owner.id: "Sam", excluded.id: "Rosa"]).isEmpty,
            "a thing with nothing said about it does not ask either")
}

@Test func datedQuestionsOutrankEntityQuestions() {
    let dated = CuriosityItem(id: .init(), kind: .unresolvedAnchor, text: "Zebra summer", payoffCount: 1, status: .open, sourceMemoryID: nil, targetMemoryID: nil)
    let entity = CuriosityItem(id: .init(), kind: .ideaWithoutMoment, text: "Is there a moment that brought that to mind?", payoffCount: 1, status: .open,
                               sourceMemoryID: nil, targetMemoryID: nil, entityID: EntityID())
    let opening = OpeningChooser.choose(curiosity: [entity, dated], bank: [], lastUsed: [:], now: .now)
    #expect(opening.main == .curiosity(dated, text: "Tell me about Zebra summer."))
    let alone = OpeningChooser.choose(curiosity: [entity], bank: [], lastUsed: [:], now: .now)
    #expect(alone.main == .curiosity(entity, text: "Is there a moment that brought that to mind?"), "the question is asked as written")
}

// PC-b, PB10: a question goes to the interviewer's model, so a person is named only by a name the owner said.
@Test func aPersonIsAskedAboutByTheirNameForTheModelOnly() {
    let robyn = Entity(type: .person, title: "Robyn Vale")
    let unnamed = Entity(type: .person, title: "Tomas Okafor")
    let drafts = EntityCuriosity.drafts(entities: [robyn, unnamed], links: [], memories: [:], owner: nil, personNames: [robyn.id: "Robyn"])
    #expect(drafts.map(\.text) == ["Is there one time with Robyn that stands out?"], "a person with no name for the model is not asked about")
    #expect(drafts.map(\.entityID) == [robyn.id])
}

@Test func namesForTheModelUseTheOldestSaidNameOfAPersonFromAContact() throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let maya = try store.people.insertPerson(displayName: "Maya")
    let robyn = Person(id: .init(), displayName: "Robyn Vale", notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                       nameOrigin: .contact, createdByGuess: true, contactIdentifier: "c-vale", contactName: "Robyn Vale", contactState: "linked")
    let bare = Person(id: .init(), displayName: "Tomas Okafor", notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                      nameOrigin: .contact, createdByGuess: true, contactIdentifier: "c-okafor", contactName: "Tomas Okafor", contactState: "linked")
    try db.writer.write { db in
        try robyn.insertWithEntity(db); try bare.insertWithEntity(db)
        _ = try PeopleRepository.insertAlias("Robyn", robyn.id, db)
        _ = try PeopleRepository.insertAlias("Bee", robyn.id, db)
    }
    #expect(try store.people.namesForModel() == [maya.entityID: "Maya", robyn.entityID: "Robyn"])
    #expect(try store.people.nameForModel(of: robyn.id) == "Robyn")
    #expect(try store.people.nameForModel(of: bare.id) == nil)
    #expect(NameForModel.of(bare, aliasesOldestFirst: []) == nil)
}
