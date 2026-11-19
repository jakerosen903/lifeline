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
                   people: [(Person, stories: Int)]) -> WhoIsThisOptions {
    WhoIsThisOptions.build(saidName: "Robin", quote: "Robin and I split the deposit.", current: current, currentIsGuess: isGuess,
                           candidates: candidates, people: people, otherMoments: others)
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
