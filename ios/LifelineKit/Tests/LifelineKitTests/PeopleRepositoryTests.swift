import Foundation
import Testing
@testable import LifelineKit

@Test func findPersonMatchesDisplayNameAndAliasIgnoringCase() throws {
    let db = try AppDatabase.inMemory(); let people = PeopleRepository(db)
    let maya = try people.insertPerson(displayName: "Maya")
    try people.addAlias("my sister", to: maya.id)
    #expect(try people.findPerson(matching: "MY SISTER ")?.id == maya.id)
    #expect(try people.findPerson(matching: "maya")?.id == maya.id)
    #expect(try people.findPerson(matching: "Sam") == nil)
}

@Test func insertPersonAddsTheNameAsAnAlias() throws {
    let db = try AppDatabase.inMemory(); let people = PeopleRepository(db)
    let maya = try people.insertPerson(displayName: "Maya")
    #expect(try people.aliases(of: maya.id).map(\.text) == ["Maya"])
    try people.addAlias("Maya", to: maya.id)
    #expect(try people.aliases(of: maya.id).count == 1)
}

@Test func resolveMentionAddsAliasAndLinksPerson() throws {
    let db = try AppDatabase.inMemory(); let sessions = SessionRepository(db); let people = PeopleRepository(db)
    let (_, segs) = try StoreFixtures.session(in: sessions)
    let maya = try people.insertPerson(displayName: "Maya")
    let mention = Mention(id: .init(), segmentID: segs[0].id, text: "Mai", status: .unresolved, personID: nil)
    try people.insertMention(mention)
    #expect(try people.mentions(status: .unresolved).count == 1)
    try people.resolve(mention.id, to: maya.id)
    let stored = try #require(try people.mention(id: mention.id))
    #expect(stored.status == .resolved && stored.personID == maya.id)
    #expect(try people.aliases(of: maya.id).map(\.text).contains("Mai"))
    try people.markNotAPerson(mention.id)
    #expect(try people.mention(id: mention.id)?.status == .notAPerson)
}

@Test func insertPlaceReusesTheSameName() throws {
    let db = try AppDatabase.inMemory(); let people = PeopleRepository(db)
    let a = try people.insertPlace(nameText: "Fresno")
    let b = try people.insertPlace(nameText: "fresno")
    #expect(a.id == b.id)
}

@Test func peopleListsOwnerFirstThenByName() throws {
    let db = try AppDatabase.inMemory(); let people = PeopleRepository(db); let profile = ProfileRepository(db)
    _ = try people.insertPerson(displayName: "Zed")
    _ = try people.insertPerson(displayName: "Amy")
    try profile.save(Profile(displayName: "Jake", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    #expect(try people.people().map(\.displayName) == ["Jake", "Amy", "Zed"])
}

@Test func segmentStatusCanBeSet() throws {
    let db = try AppDatabase.inMemory(); let sessions = SessionRepository(db)
    let (session, segs) = try StoreFixtures.session(in: sessions, segments: ["a b", "c d"])
    try sessions.setStatus(.extracted, for: segs[0].id)
    #expect(try sessions.segments(in: session, status: .pending).map(\.index) == [1])
    #expect(try sessions.fetchSegment(segs[0].id)?.status == .extracted)
}

@Test func renameKeepsTheOldSpellingAsAnAlias() throws {
    let db = try AppDatabase.inMemory(); let people = PeopleRepository(db)
    let marcel = try people.insertPerson(displayName: "Marcel")
    try people.rename(marcel.id, to: " Marcelle ")
    #expect(try people.person(id: marcel.id)?.displayName == "Marcelle")
    #expect(try people.aliases(of: marcel.id).map(\.text).sorted() == ["Marcel", "Marcelle"])
    #expect(try people.findPerson(matching: "marcel")?.id == marcel.id)
    #expect(throws: PeopleRepository.Error.emptyName) { try people.rename(marcel.id, to: "  ") }
}

@Test func relationAliasIsTheOnesStartingWithMyOrOur() throws {
    let db = try AppDatabase.inMemory(); let people = PeopleRepository(db)
    let marcel = try people.insertPerson(displayName: "Marcelle")
    try people.addAlias("Marcel", to: marcel.id)
    try people.addAlias("my mom", to: marcel.id)
    #expect(PeopleRepository.relationLabel(aliases: try people.aliases(of: marcel.id)) == "my mom")
    #expect(PeopleRepository.relationLabel(aliases: [Alias(personID: marcel.id, text: "Mai")]) == nil)
}
