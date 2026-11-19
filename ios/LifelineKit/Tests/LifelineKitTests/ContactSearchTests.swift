import Testing
@testable import LifelineKit

@Suite struct ContactSearchTests {
    private func card(_ id: String, _ full: String, nickname: String = "") -> ContactCard {
        let parts = full.split(separator: " ").map(String.init)
        return ContactCard(identifier: id, fullName: full, givenName: parts.first ?? "",
                           familyName: parts.dropFirst().joined(separator: " "), nickname: nickname, hasPicture: false)
    }
    private var cards: [ContactCard] {
        [card("3", "Tomas Robles"), card("1", "Robyn Vale"), card("2", "Ines Quill", nickname: "Nessie")]
    }

    @Test func prefixOfAnyWordMatchesInFullNameOrder() {
        #expect(ContactSearch.results("rob", in: cards).map(\.fullName) == ["Robyn Vale", "Tomas Robles"])
    }
    @Test func diacriticsAndCaseAreFolded() {
        #expect(ContactSearch.results("RÓByn", in: cards).map(\.fullName) == ["Robyn Vale"])
    }
    @Test func emptyOrBlankTextGivesNothing() {
        #expect(ContactSearch.results("", in: cards).isEmpty)
        #expect(ContactSearch.results("   ", in: cards).isEmpty)
    }
    @Test func nicknameMatches() {
        #expect(ContactSearch.results("ness", in: cards).map(\.fullName) == ["Ines Quill"])
    }
    @Test func middleOfAWordDoesNotMatch() {
        #expect(ContactSearch.results("obyn", in: cards).isEmpty)
    }
}
