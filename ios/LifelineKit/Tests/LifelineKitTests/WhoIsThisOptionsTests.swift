import Testing
@testable import LifelineKit

private func person(_ id: String, _ name: String, owner: Bool = false) -> Person {
    Person(id: PersonID(rawValue: id), displayName: name, notes: nil, isOwner: owner, birthDate: nil, birthDateOrigin: nil)
}

private let robin = person("p-robin", "Robin Okafor")
private let robyn = person("p-robyn", "Robyn Vale")
private let tove = person("p-tove", "Tove Brandt")
private let me = person("p-me", "Ada Quill", owner: true)

private func build(current: PersonID?, isGuess: Bool = true, candidates: [PersonID], others: Int = 2,
                   people: [(Person, stories: Int)], contacts: [ContactCard] = [], saidName: String = "Robin") -> WhoIsThisOptions {
    WhoIsThisOptions.build(saidName: saidName, quote: "Robin and I split the deposit.", current: current, currentIsGuess: isGuess,
                           candidates: candidates, people: people, contacts: contacts, otherMoments: others)
}

@Test func theGuessIsFirstAndSaysItIsAGuess() {
    let o = build(current: robin.id, candidates: [robyn.id], people: [(robyn, 3), (robin, 12)])
    #expect(o.rows[0].target == .person(robin.id))
    #expect(o.rows[0].isCurrent)
    #expect(o.rows[0].title == "Robin Okafor")
    #expect(o.rows[0].line == "In 12 of your stories \u{00B7} my guess")
    #expect(o.rows[1].isCurrent == false)
    #expect(o.saidName == "Robin")
    #expect(o.quote == "Robin and I split the deposit.")
}

@Test func aSettledCurrentChoiceDoesNotSayGuess() {
    let o = build(current: robin.id, isGuess: false, candidates: [], people: [(robin, 12)])
    #expect(o.rows[0].line == "In 12 of your stories")
}

@Test func otherCandidatesFollowInOrder() {
    let o = build(current: robin.id, candidates: [robyn.id, tove.id], people: [(tove, 1), (robin, 12), (robyn, 3)])
    #expect(o.rows.map(\.target) == [.person(robin.id), .person(robyn.id), .person(tove.id)])
    #expect(o.rows[1].line == "In 3 of your stories")
}

@Test func aCandidateListedTwiceOrAsTheCurrentChoiceShowsOnce() {
    let o = build(current: robin.id, candidates: [robin.id, robyn.id, robyn.id], people: [(robin, 1), (robyn, 1)])
    #expect(o.rows.map(\.target) == [.person(robin.id), .person(robyn.id)])
}

@Test func aPersonInNoStory() {
    let o = build(current: nil, candidates: [robyn.id], people: [(robyn, 0)])
    #expect(o.rows[0].line == "Not in a story yet")
}

@Test func everyoneElseLeavesOutTheCandidatesAndTheOwner() {
    let o = build(current: robin.id, candidates: [robyn.id], people: [(tove, 2), (me, 9), (robyn, 3), (robin, 12)])
    #expect(o.everyoneElse.map(\.target) == [.person(tove.id)])
    #expect(o.everyoneElse[0].line == "In 2 of your stories")
}

@Test func everyoneElseIsByName() {
    let zed = person("p-zed", "zed Hart")
    let amy = person("p-amy", "Amy Hart")
    let o = build(current: nil, candidates: [], people: [(zed, 1), (amy, 1)])
    #expect(o.everyoneElse.map(\.title) == ["Amy Hart", "zed Hart"])
}

@Test func groupLabels() {
    #expect(WhoIsThisOptions.groupLabel(1) == "Also change the 1 other moment from this recording")
    #expect(WhoIsThisOptions.groupLabel(2) == "Also change the 2 other moments from this recording")
}

@Test func aWaitingCardHasNoCurrentPersonForANewName() {
    let o = build(current: nil, candidates: [robyn.id], people: [(robyn, 3)])
    #expect(o.rows.allSatisfy { !$0.isCurrent })
    #expect(o.rows.map(\.target) == [.person(robyn.id)])
}

@Test func otherMomentsPassThrough() {
    #expect(build(current: nil, candidates: [], others: 0, people: []).otherMoments == 0)
}

// PC-b Task 6: the contacts that fit the said name, after the people on file. Names are invented.

private func card(_ id: String, _ full: String, given: String = "", nickname: String = "") -> ContactCard {
    ContactCard(identifier: id, fullName: full, givenName: given, familyName: "", nickname: nickname, hasPicture: false)
}

private let hale = card("c-hale", "Robin Hale", given: "Robin")
private let birdie = card("c-birdie", "Wren Abbot", given: "Wren", nickname: "Robin")
private let okafor = card("c-okafor", "Robin Okafor", given: "Robin")
private let brandt = card("c-brandt", "Tove Brandt", given: "Tove")

@Test func contactsThatFitComeAfterThePeopleOnFile() {
    let o = build(current: robyn.id, candidates: [tove.id], people: [(robyn, 3), (tove, 1)], contacts: [hale, brandt, birdie])
    #expect(o.rows.map(\.target) == [.person(robyn.id), .person(tove.id), .contact(hale), .contact(birdie)],
            "full name, given name or nickname; by full name")
    #expect(o.rows[2].id == "contact:c-hale")
    #expect(o.rows[2].title == "Robin Hale")
    #expect(o.rows[2].line == "In your contacts \u{00B7} not in a story yet")
    #expect(o.rows[2].isCurrent == false)
}

@Test func aLinkedContactIsNotListedButItsPersonIs() {
    var okaforPerson = robin
    okaforPerson.contactIdentifier = "c-okafor"
    let o = build(current: nil, candidates: [], people: [(okaforPerson, 12), (tove, 1)], contacts: [okafor, hale])
    #expect(o.rows.map(\.target) == [.person(robin.id), .contact(hale)])
    #expect(o.everyoneElse.map(\.target) == [.person(tove.id)], "the person is listed once")
}

@Test func aContactListedTwiceOrWithNoFullNameShowsOnceOrNotAtAll() {
    let blank = card("c-blank", "  ", given: "Robin")
    let o = build(current: nil, candidates: [], people: [], contacts: [hale, hale, blank])
    #expect(o.rows.map(\.target) == [.contact(hale)])
}

@Test func aSaidNameWithNoNameFitsNoContact() {
    let o = build(current: nil, candidates: [], people: [], contacts: [hale], saidName: "my brother")
    #expect(o.rows.isEmpty)
}

@Test func noAccessGivesNoContactRow() {
    for access in [ContactsAccess.notAsked, .denied] {
        #expect(WhoIsThisOptions.offered([hale], access: access).isEmpty)
    }
    #expect(WhoIsThisOptions.offered([hale], access: .full) == [hale])
    #expect(WhoIsThisOptions.offered([hale], access: .limited) == [hale])
}

@Test func aPickedContactBecomesARow() {
    let o = build(current: robin.id, candidates: [], people: [(robin, 12)], contacts: [])
    let picked = o.adding(brandt, heldBy: nil)
    #expect(picked.rows.map(\.target) == [.person(robin.id), .contact(brandt)])
    #expect(picked.rows[1].line == "In your contacts \u{00B7} not in a story yet")
    #expect(picked.adding(brandt, heldBy: nil) == picked, "a contact already listed is not added again")
    let held = o.adding(okafor, heldBy: "Robin Okafor")
    #expect(held.rows[1].line == "In a story as Robin Okafor")
}

// I-1 (fix wave): a waiting card whose chip is the app's guess from a contact opens on that contact, first and marked.
@Test func theContactKeepWouldLinkIsTheCurrentChoice() {
    let o = build(current: nil, candidates: [robyn.id], people: [(robyn, 3)], contacts: [hale, okafor])
    let guessed = o.withCurrentContact(okafor)
    #expect(guessed.rows.map(\.target) == [.contact(okafor), .person(robyn.id), .contact(hale)], "first, and listed once")
    #expect(guessed.rows[0].isCurrent)
    #expect(guessed.rows[0].line == "In your contacts \u{00B7} my guess")
    #expect(guessed.rows.dropFirst().allSatisfy { !$0.isCurrent })
    #expect(o.withCurrentContact(brandt).rows.first?.target == .contact(brandt), "a contact that does not fit by name is still the guess")
}
