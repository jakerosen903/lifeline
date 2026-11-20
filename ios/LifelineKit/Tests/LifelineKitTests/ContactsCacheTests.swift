import Testing
@testable import LifelineKit

@Suite struct ContactsCacheTests {
    private let robyn = ContactCard(identifier: "c1", fullName: "Robyn Vale", givenName: "Robyn",
                                    familyName: "Vale", nickname: "Rob", hasPicture: true)
    private let tomas = ContactCard(identifier: "c2", fullName: "Tomas Robles", givenName: "Tomas",
                                    familyName: "Robles", nickname: "", hasPicture: false)

    @Test func deniedLeavesTheCacheEmpty() async {
        let cache = ContactsCache()
        await cache.refresh(from: ScriptedContactsDirectory(cards: [robyn], access: .denied))
        #expect(cache.cards.isEmpty)
    }
    @Test func notAskedLeavesTheCacheEmpty() async {
        let cache = ContactsCache()
        await cache.refresh(from: ScriptedContactsDirectory(cards: [robyn], access: .notAsked))
        #expect(cache.cards.isEmpty)
    }
    @Test func limitedHoldsTheSharedCards() async {
        let cache = ContactsCache()
        await cache.refresh(from: ScriptedContactsDirectory(cards: [robyn, tomas], access: .limited))
        #expect(cache.cards == [robyn, tomas])
    }
    @Test func accessLostEmptiesAFullCache() async {
        let cache = ContactsCache()
        cache.replace(with: [robyn])
        await cache.refresh(from: ScriptedContactsDirectory(cards: [robyn], access: .denied))
        #expect(cache.cards.isEmpty)
    }
    @Test func aThrownReadKeepsTheOldCards() async {
        let cache = ContactsCache()
        cache.replace(with: [robyn])
        let directory = ScriptedContactsDirectory(cards: [tomas], access: .full)
        directory.failsOnRead = true
        await cache.refresh(from: directory)
        #expect(cache.cards == [robyn])
    }
    @Test func forGuessMapsEveryField() {
        let cache = ContactsCache()
        cache.replace(with: [robyn])
        #expect(cache.forGuess == [PersonGuess.Contact(identifier: "c1", fullName: "Robyn Vale", givenName: "Robyn", nickname: "Rob")])
    }
    @Test func scriptedCardsReturnsOnlyThoseThatExist() async throws {
        let directory = ScriptedContactsDirectory(cards: [robyn], access: .full)
        #expect(try await directory.cards(identifiers: ["c1", "gone"]) == [robyn])
    }
}
