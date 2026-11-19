import Foundation
import GRDB
import Testing
@testable import LifelineKit

// PC-b Task 4: a contact that appears later (PC4). Names are invented.

private func card(_ identifier: String, _ given: String, _ family: String, nickname: String = "") -> ContactCard {
    ContactCard(identifier: identifier, fullName: "\(given) \(family)", givenName: given, familyName: family, nickname: nickname, hasPicture: false)
}

private let vale = card("c-vale", "Robyn", "Vale")
private let reyes = card("c-reyes", "Tomas", "Reyes")
private let okafor = card("c-okafor", "Robyn", "Okafor")

// MARK: - pick (pure)

@Test func pickFindsTheOneCardWhoseNameIsThePersonsNameOrAnAlias() {
    #expect(ContactSuggestion.pick(name: "Robyn Vale", aliases: [], cards: [vale, reyes], linked: [], declined: []) == vale)
    #expect(ContactSuggestion.pick(name: "Grandpa", aliases: ["my grandpa", "tomas"], cards: [vale, reyes], linked: [], declined: []) == reyes)
    #expect(ContactSuggestion.pick(name: "  ROBYN  ", aliases: [], cards: [vale, reyes], linked: [], declined: []) == vale, "the spec's comparison")
    #expect(ContactSuggestion.pick(name: "Bee", aliases: [], cards: [card("c-bee", "Beatrix", "Lund", nickname: "Bee")], linked: [], declined: [])?.identifier == "c-bee")
}

@Test func pickOffersNothingForTwoCardsOrNone() {
    #expect(ContactSuggestion.pick(name: "Robyn", aliases: [], cards: [vale, okafor], linked: [], declined: []) == nil)
    #expect(ContactSuggestion.pick(name: "Ines", aliases: [], cards: [vale, okafor], linked: [], declined: []) == nil)
    #expect(ContactSuggestion.pick(name: "", aliases: [" "], cards: [card("c-blank", "", "")], linked: [], declined: []) == nil)
}

@Test func pickNeverOffersALinkedOrDeclinedCard() {
    #expect(ContactSuggestion.pick(name: "Robyn Vale", aliases: [], cards: [vale], linked: ["c-vale"], declined: []) == nil)
    #expect(ContactSuggestion.pick(name: "Robyn Vale", aliases: [], cards: [vale], linked: [], declined: ["c-vale"]) == nil)
    #expect(ContactSuggestion.pick(name: "Robyn", aliases: [], cards: [vale, okafor], linked: ["c-okafor"], declined: []) == vale,
            "the one card left that is free")
}

// MARK: - suggestion and decline

private struct Fixture {
    let db: AppDatabase, store: ExtractionStore
    let actions: ContactLinkActions

    init() throws {
        db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        let root = FileManager.default.temporaryDirectory.appending(path: "contact-suggestion-\(UUID().uuidString)", directoryHint: .isDirectory)
        actions = ContactLinkActions(store: store, photos: PhotoLibrary(root: root, photos: store.photos),
                                     directory: ScriptedContactsDirectory(cards: [vale, reyes, okafor]), scratch: root)
    }

    func declined() throws -> [String] {
        try db.writer.read { try String.fetchAll($0, sql: "select person_id || '|' || contact_identifier from contact_declined") }
    }
}

@Test func aPersonWithNoContactIsOfferedTheOneThatFits() async throws {
    let f = try Fixture()
    let tomas = try f.store.people.insertPerson(displayName: "Tomas")
    #expect(try f.actions.suggestion(for: tomas.id, in: [vale, reyes, okafor]) == reyes)
}

@Test func aDeclinedContactIsNotOfferedAgain() async throws {
    let f = try Fixture()
    let tomas = try f.store.people.insertPerson(displayName: "Tomas")
    try f.actions.decline(reyes, for: tomas.id)
    #expect(try f.actions.suggestion(for: tomas.id, in: [vale, reyes, okafor]) == nil)
    try f.actions.decline(reyes, for: tomas.id)
    #expect(try f.declined() == ["\(tomas.id.rawValue)|c-reyes"], "a second decline writes nothing new")
    #expect(try f.actions.suggestion(for: tomas.id, in: [vale, reyes, okafor]) == nil, "and it stays declined")
}

@Test func aDeclineIsForThatPersonOnly() async throws {
    let f = try Fixture()
    let tomas = try f.store.people.insertPerson(displayName: "Tomas")
    let grandpa = try f.store.people.insertPerson(displayName: "Grandpa")
    try f.store.people.addAlias("Tomas", to: grandpa.id)
    try f.actions.decline(reyes, for: tomas.id)
    #expect(try f.actions.suggestion(for: grandpa.id, in: [reyes]) == reyes)
}

@Test func aContactAnotherPersonHoldsIsNotOffered() async throws {
    let f = try Fixture()
    let tomas = try f.store.people.insertPerson(displayName: "Tomas")
    let grandpa = try f.store.people.insertPerson(displayName: "Grandpa")
    try f.store.people.addAlias("Tomas", to: grandpa.id)
    try await f.actions.link(grandpa.id, to: reyes)
    #expect(try f.actions.suggestion(for: tomas.id, in: [vale, reyes, okafor]) == nil)
}

@Test func aLinkedPersonAndTheOwnerAreNeverOffered() async throws {
    let f = try Fixture()
    let tomas = try f.store.people.insertPerson(displayName: "Tomas")
    try await f.actions.link(tomas.id, to: okafor)
    #expect(try f.actions.suggestion(for: tomas.id, in: [reyes]) == nil)
    let owner = try f.store.people.insertPerson(displayName: "Robyn Vale")
    try await f.db.writer.write { db in try db.execute(sql: "update person set is_owner = 1 where id = ?", arguments: [owner.id.rawValue]) }
    #expect(try f.actions.suggestion(for: owner.id, in: [vale]) == nil)
}

@Test func aDeclineForAPersonWhoIsGoneIsNotFound() async throws {
    let f = try Fixture()
    #expect(throws: ContactLinkActions.Error.notFound) { try f.actions.decline(reyes, for: PersonID()) }
}
