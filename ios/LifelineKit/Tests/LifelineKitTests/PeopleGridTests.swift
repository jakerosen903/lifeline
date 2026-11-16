import Foundation
import Testing
@testable import LifelineKit

// S2, Task 6: the People grid's sorts, monograms and tints.

private func person(_ title: String, moments: [Int?]) -> EntitySummary {
    let ranges = moments.map { $0.map { TimeRange.year($0, origin: .stated, evidence: nil) } ?? .unplaced }
    return EntitySummary(entity: Entity(type: .person, title: title), ownWords: nil, momentRanges: ranges, span: .unplaced)
}

/// maya: 4 moments, first 1999; dad: 3, first 1999; sam: 1, first 2012; lena: 0, none.
private let all = [
    person("Sam", moments: [2012]),
    person("Lena", moments: []),
    person("Maya", moments: [1999, 2003, nil, 2010]),
    person("Dad", moments: [1999, 2001, 2005]),
]

@Test func theSortsOrderPeopleAsNamed() {
    #expect(PeopleSort.mostTold.sorted(all).map(\.entity.title) == ["Maya", "Dad", "Sam", "Lena"])
    #expect(PeopleSort.firstInStory.sorted(all).map(\.entity.title) == ["Dad", "Maya", "Sam", "Lena"])
    #expect(PeopleSort.byName.sorted(all).map(\.entity.title) == ["Dad", "Lena", "Maya", "Sam"])
    #expect(PeopleSort.allCases.map(\.title) == ["Most told", "First in your story", "By name"])
}

@Test func tiesGoByNameIgnoringCase() {
    let tied = [person("zed", moments: [2000]), person("Amy", moments: [2000]), person("bo", moments: [2000])]
    for sort in PeopleSort.allCases { #expect(sort.sorted(tied).map(\.entity.title) == ["Amy", "bo", "zed"]) }
}

@Test func theMonogramIsTheFirstLetter() {
    #expect(Monogram.letter(for: "maya") == "M")
    #expect(Monogram.letter(for: "Mr. Alvarez") == "M")
    #expect(Monogram.letter(for: "“Bird”") == "B")
    #expect(Monogram.letter(for: "Élodie") == "É")
    #expect(Monogram.letter(for: "42") == "4")
}

@Test func aTitleWithNoLetterKeepsItsFirstCharacter() {
    #expect(Monogram.letter(for: "…") == "…")
    #expect(Monogram.letter(for: "") == "")
}

@Test func theTintIsFixedByTheID() {
    #expect(Monogram.tintIndex(for: EntityID(rawValue: "00000000-0000-0000-0000-000000000000")) == 0)
    #expect(Monogram.tintIndex(for: EntityID(rawValue: "A")) == 2)
    let id = EntityID()
    #expect(Monogram.tintIndex(for: id) == Monogram.tintIndex(for: EntityID(rawValue: id.rawValue)))
    #expect((0..<3).contains(Monogram.tintIndex(for: id)))
}
