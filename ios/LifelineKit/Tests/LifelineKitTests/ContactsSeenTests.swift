import Testing
@testable import LifelineKit

// PC-b Task 5 (PB1): what a "New" chip says about the contacts. Names are invented.

private let vale = ContactCard(identifier: "c-vale", fullName: "Robyn Vale", givenName: "Robyn", familyName: "Vale", nickname: "", hasPicture: true)
private let reyes = ContactCard(identifier: "c-reyes", fullName: "Tomás Reyes", givenName: "Tomás", familyName: "Reyes", nickname: "Tom", hasPicture: false)

private func seen(_ said: String?, access: ContactsAccess = .full, cards: [ContactCard] = [vale, reyes],
                  held: Set<String> = []) -> PersonChipLine.ContactsSeen {
    PersonChipLine.ContactsSeen.of(saidName: said, access: access, cards: cards, held: held)
}

@Test(arguments: [ContactsAccess.notAsked, .denied])
func withoutAccessAChipSaysNothingAboutContacts(access: ContactsAccess) {
    #expect(seen("Robyn", access: access) == .none)
    #expect(seen("Somebody", access: access) == .none)
}

@Test(arguments: [ContactsAccess.full, .limited])
func aSaidNameMatchesByFullNameGivenNameOrNickname(access: ContactsAccess) {
    #expect(seen("Robyn Vale", access: access) == .someMatch)
    #expect(seen("robyn", access: access) == .someMatch, "given name, any case")
    #expect(seen("Tomas", access: access) == .someMatch, "diacritics folded")
    #expect(seen("Tom", access: access) == .someMatch, "nickname")
    #expect(seen("my friend, Robyn", access: access) == .someMatch, "the name part of a said name")
}

@Test func aFamilyNameAloneIsNoMatch() {
    #expect(seen("Vale") == .noMatch, "the guess does not match by family name")
}

@Test func noFittingContactIsNoMatch() {
    #expect(seen("Marguerite") == .noMatch)
    #expect(seen("Robyn", cards: []) == .noMatch, "access and no contacts")
}

@Test func aContactAnotherPersonHoldsIsNotFree() {
    #expect(seen("Robyn", held: ["c-vale"]) == .noMatch)
    #expect(seen("Robyn", cards: [vale, ContactCard(identifier: "c-oka", fullName: "Robyn Okafor", givenName: "Robyn",
                                                    familyName: "Okafor", nickname: "", hasPicture: false)],
                 held: ["c-vale"]) == .someMatch)
}

@Test func noNameIsNoMatch() {
    #expect(seen(nil) == .noMatch)
    #expect(seen("   ") == .noMatch)
    #expect(seen("my sister") == .noMatch, "a relation phrase has no name to match")
}
