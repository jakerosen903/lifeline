import Foundation
import Testing
@testable import LifelineKit

@Suite struct PersonGuessTests {
    private func known(_ name: String, aliases: [String] = [], last: Date? = nil, contact: String? = nil) -> PersonGuess.Known {
        .init(id: PersonID(), name: name, aliases: aliases, lastLinked: last, contactIdentifier: contact)
    }
    private func contact(_ id: String, full: String, given: String = "", nick: String = "") -> PersonGuess.Contact {
        .init(identifier: id, fullName: full, givenName: given, nickname: nick)
    }
    private let early = Date(timeIntervalSince1970: 1_000)
    private let late = Date(timeIntervalSince1970: 2_000)

    @Test func rule1NameAndRelationPointToOne() {
        let a = known("Danielle", aliases: ["my sister"]), b = known("Danielle")
        let r = PersonGuess.guess(SaidName(ref: "Danielle", mentionRelation: "my sister"), people: [b, a], contacts: [])
        #expect(r.choice == .person(a.id)); #expect(r.origin == .said); #expect(r.rule == 1)
        #expect(r.others == [.person(b.id)])
    }

    @Test func rule1NeedsBothOnOnePerson() {
        let a = known("Danielle"), kira = known("Kira", aliases: ["my sister"])
        let r = PersonGuess.guess(SaidName(ref: "Danielle", mentionRelation: "my sister"), people: [a, kira], contacts: [])
        #expect(r.choice == .person(a.id)); #expect(r.origin == .assumed); #expect(r.rule == 4)
    }

    @Test func rule2RelationAlone() {
        let m = known("Marcel", aliases: ["my mom"])
        let r = PersonGuess.guess(SaidName(ref: "my mom"), people: [m, known("Kira")], contacts: [])
        #expect(r.choice == .person(m.id)); #expect(r.origin == .said); #expect(r.rule == 2)
    }

    @Test func rule2RelationHeldByTwo() {
        let a = known("Ana", aliases: ["my roommate"], last: early), b = known("Bo", aliases: ["my roommate"], last: late)
        let r = PersonGuess.guess(SaidName(ref: "my roommate"), people: [a, b], contacts: [])
        #expect(r.choice == .person(b.id)); #expect(r.origin == .assumed); #expect(r.rule == 4)
        #expect(r.others == [.person(a.id)])
    }

    @Test func rule3FullerNameFitsThePersonOnly() {
        let p = known("Robin Okafor")
        let r = PersonGuess.guess(SaidName(ref: "Robin Okafor"), people: [p], contacts: [contact("c1", full: "Robin Vale", given: "Robin")])
        #expect(r.choice == .person(p.id)); #expect(r.origin == .assumed); #expect(r.rule == 3)
    }

    @Test func rule3FullerNameFitsTheContactOnly() {
        let r = PersonGuess.guess(SaidName(ref: "Robyn Vale"), people: [known("Robyn")],
                                  contacts: [contact("c1", full: "Robyn Vale", given: "Robyn")])
        #expect(r.choice == .contact("c1")); #expect(r.origin == .assumed); #expect(r.rule == 3)
    }

    @Test func rule4PersonBeatsContact() {
        let p = known("Robin Okafor", aliases: ["Robin"])
        let r = PersonGuess.guess(SaidName(ref: "Robin"), people: [p], contacts: [contact("c1", full: "Robin Vale", given: "Robin")])
        #expect(r.choice == .person(p.id)); #expect(r.origin == .assumed); #expect(r.rule == 4)
        #expect(r.others == [.contact("c1")])
    }

    @Test func rule4TwoPersonsMostRecentWins() {
        let a = known("Robin", last: early), b = known("Robin", last: late)
        let r = PersonGuess.guess(SaidName(ref: "Robin"), people: [a, b], contacts: [])
        #expect(r.choice == .person(b.id)); #expect(r.rule == 4); #expect(r.others == [.person(a.id)])
    }

    @Test func rule4NeverLinkedLosesToLinkedThenNameBreaksTies() {
        let never = known("Robin"), linked = known("Robin", last: early)
        #expect(PersonGuess.guess(SaidName(ref: "Robin"), people: [never, linked], contacts: []).choice == .person(linked.id))
        let a = known("Robin", aliases: ["Rob"]), b = known("Robin")
        let first = PersonGuess.guess(SaidName(ref: "Robin"), people: [a, b], contacts: [])
        let second = PersonGuess.guess(SaidName(ref: "Robin"), people: [b, a], contacts: [])
        #expect(first.choice == second.choice)
    }

    @Test func rule4KnownNameNewRelation() {
        let p = known("Robin")
        let r = PersonGuess.guess(SaidName(ref: "Robin", mentionRelation: "my roommate"), people: [p], contacts: [])
        #expect(r.choice == .person(p.id)); #expect(r.origin == .assumed); #expect(r.rule == 4)
    }

    @Test func rule5OneContact() {
        let r = PersonGuess.guess(SaidName(ref: "Priya"), people: [], contacts: [contact("c1", full: "Priya Rao", given: "Priya")])
        #expect(r.choice == .contact("c1")); #expect(r.origin == .assumed); #expect(r.rule == 5); #expect(r.others.isEmpty)
    }

    @Test func rule6TwoContacts() {
        let r = PersonGuess.guess(SaidName(ref: "Sam"), people: [],
                                  contacts: [contact("c2", full: "Sam Wu", given: "Sam"), contact("c1", full: "Sam Ode", given: "Sam")])
        #expect(r.choice == .newPerson); #expect(r.origin == .new); #expect(r.rule == 6)
        #expect(Set(r.others) == [.contact("c1"), .contact("c2")]); #expect(r.others.count == 2)
    }

    @Test func rule7Nothing() {
        let r = PersonGuess.guess(SaidName(ref: "Tomas"), people: [known("Kira")], contacts: [contact("c1", full: "Priya Rao", given: "Priya")])
        #expect(r.choice == .newPerson); #expect(r.origin == .new); #expect(r.rule == 7); #expect(r.others.isEmpty)
    }

    @Test func aLinkedContactIsThatPerson() {
        let p = known("Robin Okafor", contact: "c1")
        let r = PersonGuess.guess(SaidName(ref: "Robin"), people: [p], contacts: [contact("c1", full: "Robin Okafor", given: "Robin")])
        #expect(r.choice == .person(p.id)); #expect(r.others.isEmpty)
    }

    @Test func caseAndDiacritics() {
        let p = known("José")
        let r = PersonGuess.guess(SaidName(ref: "josé"), people: [p], contacts: [])
        #expect(r.choice == .person(p.id)); #expect(r.rule == 4)
    }

    @Test func nicknameFitsAContact() {
        let r = PersonGuess.guess(SaidName(ref: "Bee"), people: [], contacts: [contact("c1", full: "Beatrix Lund", given: "Beatrix", nick: "Bee")])
        #expect(r.choice == .contact("c1")); #expect(r.rule == 5)
    }

    @Test func aCommaPartOfTheSaidNameFitsAPerson() {
        let m = known("Marcel")
        let r = PersonGuess.guess(SaidName(ref: "my mom, Marcel"), people: [m], contacts: [])
        #expect(r.choice == .person(m.id))
    }

    @Test func emptyRefMatchesNothing() {
        let r = PersonGuess.guess(SaidName(ref: "  "), people: [known("")], contacts: [contact("c1", full: "")])
        #expect(r.rule == 7)
    }

    // The relation part of a comma-form ref never picks a candidate.
    @Test func commaFormRelationHeldByAnotherPersonIsRule7() {
        let marcel = known("Marcel", aliases: ["my mom"])
        let r = PersonGuess.guess(SaidName(ref: "Priya, my mom"), people: [marcel], contacts: [])
        #expect(r.choice == .newPerson); #expect(r.origin == .new); #expect(r.rule == 7); #expect(r.others.isEmpty)
    }

    @Test func commaFormNameOnFileIsRule4() {
        let marcel = known("Marcel", aliases: ["my mom"]), priya = known("Priya")
        let r = PersonGuess.guess(SaidName(ref: "Priya, my mom"), people: [marcel, priya], contacts: [])
        #expect(r.choice == .person(priya.id)); #expect(r.origin == .assumed); #expect(r.rule == 4); #expect(r.others.isEmpty)
    }

    @Test func commaFormNameAndRelationOnOnePersonIsRule1() {
        let marcel = known("Marcel", aliases: ["my mom"]), priya = known("Priya", aliases: ["my mom"])
        let r = PersonGuess.guess(SaidName(ref: "Priya, my mom"), people: [marcel, priya], contacts: [])
        #expect(r.choice == .person(priya.id)); #expect(r.origin == .said); #expect(r.rule == 1)
    }
}
