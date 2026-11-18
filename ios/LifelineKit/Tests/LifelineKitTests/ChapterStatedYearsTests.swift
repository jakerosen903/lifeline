import Testing
@testable import LifelineKit

@Suite struct ChapterStatedYearsTests {
    @Test func aStatedRangeIsTheChaptersYears() {
        let c = Chapter(id: .init(), title: "Maple Street", range: .stated(between: 1998, and: 2001), order: 0)
        #expect(c.statedYears?.displayText == "1998–2001")
    }
    @Test func aConfirmedRangeIsTheChaptersYears() {
        let c = Chapter(id: .init(), title: "A", range: .year(2003, origin: .confirmed, evidence: nil), order: 0)
        #expect(c.statedYears != nil)
    }
    @Test(arguments: [RangeOrigin.derived, .inferred, .photo]) func aRangeFromBeforeThisChangeIsNotStated(origin: RangeOrigin) {
        let c = Chapter(id: .init(), title: "A", range: .year(2003, origin: origin, evidence: nil), order: 0)
        #expect(c.statedYears == nil)
    }
    @Test func anUnplacedChapterHasNoStatedYears() {
        #expect(Chapter(id: .init(), title: "A", range: .unplaced, order: 0).statedYears == nil)
    }
    @Test func theAnchorRangeIsTheStatedYearsWhenThereAreAny() {
        let c = Chapter(id: .init(), title: "A", range: .stated(between: 2008, and: 2012), order: 0)
        #expect(c.anchorRange(members: [.stated(year: 1990)]).earliest?.year == 2008)
    }
    @Test func theAnchorRangeIsTheMemberSpanWhenNothingIsStated() {
        let c = Chapter(id: .init(), title: "A", range: .year(1970, origin: .derived, evidence: nil), order: 0)
        let r = c.anchorRange(members: [.stated(year: 1998), .stated(year: 2001)])
        #expect(r.earliest?.year == 1998 && r.latest?.year == 2001)
        #expect(c.anchorRange(members: []).isPlaced == false)
    }
    @Test func theNameIsTheTrimmedTitleOrNothing() {
        #expect(Chapter(id: .init(), title: "  Maple Street ", range: .unplaced, order: 0).name == "Maple Street")
        #expect(Chapter(id: .init(), title: "  ", range: .unplaced, order: 0).name == nil)
        #expect(Chapter(id: .init(), title: nil, range: .unplaced, order: 0).name == nil)
    }
}
