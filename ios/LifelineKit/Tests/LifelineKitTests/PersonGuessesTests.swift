import Testing
@testable import LifelineKit

private func link(_ memory: String, _ relation: EntityRelation, _ origin: LinkOrigin?) -> PersonLink {
    let person = Person(id: PersonID(rawValue: "p1"), displayName: "Robyn Vale", notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                        nameOrigin: .said, createdByGuess: false, contactIdentifier: nil, contactName: nil, contactState: nil)
    return PersonLink(memoryID: MemoryID(rawValue: memory), person: person, saidName: "Robin", origin: origin, relation: relation)
}

@Test func onlyAssumedLinksAreGuesses() {
    let guesses = PersonLink.guesses(among: [link("m1", .mention, .assumed), link("m2", .mention, .confirmed),
                                             link("m3", .mention, .said), link("m4", .mention, nil), link("m5", .mention, .new)])
    #expect(Set(guesses.keys) == [MemoryID(rawValue: "m1")])
}

@Test func aMentionWinsOverADetailOnTheSameMemoryInEitherOrder() {
    let mention = link("m1", .mention, .assumed), detail = link("m1", .detail, .assumed)
    #expect(PersonLink.guesses(among: [mention, detail])[MemoryID(rawValue: "m1")] == mention)
    #expect(PersonLink.guesses(among: [detail, mention])[MemoryID(rawValue: "m1")] == mention)
}

@Test func aDetailAloneIsShownAndASettledMentionDoesNotHideAGuessedDetail() {
    let detail = link("m1", .detail, .assumed)
    #expect(PersonLink.guesses(among: [detail])[MemoryID(rawValue: "m1")] == detail)
    #expect(PersonLink.guesses(among: [link("m1", .mention, .confirmed), detail])[MemoryID(rawValue: "m1")] == detail)
    #expect(PersonLink.guesses(among: []).isEmpty)
}
