import Foundation
import Testing
@testable import LifelineKit

// S6a Task 2: the spine's marks, margin years, gaps and waypoints. Invented years only.

private func stops(_ ranges: [TimeRange], birthYear: Int? = nil) -> [SpineLayout.Stop] {
    SpineLayout.stops(for: ranges.enumerated().map { (id: "m\($0.offset)", range: $0.element) }, birthYear: birthYear)
}

private func inferred(_ year: Int) -> TimeRange { .year(year, origin: .inferred, evidence: nil) }

@Test func emptyInGivesEmptyOut() {
    #expect(stops([]).isEmpty)
}

@Test func oneMomentHasNoGapAndStartsItsPeriod() {
    let result = stops([.stated(year: 1999)], birthYear: 1990)
    #expect(result.count == 1)
    #expect(result[0].id == "m0")
    #expect(result[0].gapAbove == nil)
    #expect(result[0].periodAbove?.name == "Childhood")
    #expect(result[0].showsYears)
}

@Test func aStatedYearIsASolidDotAndAnInferredOneIsDashed() {
    let result = stops([.stated(year: 1999), inferred(2001)])
    #expect(result[0].mark == .solidDot)
    #expect(result[0].qualifier == nil)
    #expect(result[1].mark == .dashedDot)
    #expect(result[1].qualifier == "around")
}

@Test func aStatedAroundIsADashedDot() {
    let stop = stops([.stated(around: 1999)])[0]
    #expect(stop.mark == .dashedDot)
    #expect(stop.years == "1999")
    #expect(stop.qualifier == "around")
    #expect(stop.rowDateText == nil)
}

@Test func aRangeOfYearsIsACapsule() {
    let stop = stops([.stated(between: 2008, and: 2010)])[0]
    #expect(stop.mark == .dashedCapsule)
    #expect(stop.years == "2008–10")
    #expect(stop.qualifier == nil)
    #expect(stop.rowDateText == nil)
}

@Test func aFinerDateKeepsItsFullTextInTheRow() {
    let june = TimeRange.span(.first(ofMonth: 6, year: 2012), .last(ofMonth: 6, year: 2012), granularity: .month, origin: .stated, evidence: nil)
    let stop = stops([june])[0]
    #expect(stop.years == "2012")
    #expect(stop.rowDateText == "June 2012")
}

@Test func aRelationKeepsItsFullTextInTheRow() {
    let relation = TimeRange.span(.firstOfYear(2002), .lastOfYear(2004), granularity: .year, origin: .confirmed, evidence: "before Graduation (2004)")
    #expect(stops([relation])[0].rowDateText == "before Graduation (2004)")
}

@Test func theGapTable() {
    let expected: [(years: Int, units: Int, label: String?)] = [
        (0, 0, nil), (1, 0, nil), (2, 1, nil), (3, 2, "3 years"), (4, 2, "4 years"),
        (5, 3, "5 years"), (9, 3, "9 years"), (10, 4, "10 years"), (40, 4, "40 years"),
    ]
    for row in expected {
        let gap = SpineLayout.gap(years: row.years)
        #expect(gap.years == row.years)
        #expect(gap.units == row.units, "units for \(row.years) years")
        #expect(gap.label == row.label, "label for \(row.years) years")
        #expect(gap.isDashed == (row.label != nil))
    }
}

@Test func aGapIsMeasuredFromTheEndOfARange() {
    let result = stops([.stated(between: 2008, and: 2010), .stated(year: 2011)])
    #expect(result[1].gapAbove?.years == 1)
}

@Test func overlappingRangesHaveNoGap() {
    let result = stops([.stated(between: 2000, and: 2005), .stated(year: 2003)])
    #expect(result[1].gapAbove?.years == 0, "never negative")
}

@Test func aRangeInsideARangeDoesNotMakeAGapAfterIt() {
    let result = stops([.stated(between: 2000, and: 2010), .stated(year: 2003), .stated(year: 2012)])
    #expect(result[2].gapAbove?.years == 2, "measured from 2010, the latest end above, not from 2003")
}

@Test func theSameYearIsWrittenOnce() {
    let result = stops([.stated(year: 2001), .stated(year: 2001), .stated(year: 2002)])
    #expect(result[0].showsYears)
    #expect(!result[1].showsYears)
    #expect(result[2].showsYears)
}

@Test func aGuessInTheSameYearKeepsItsWords() {
    let result = stops([.stated(year: 2001), inferred(2001)])
    #expect(result[1].showsYears, "the word around must show somewhere")
}

@Test func aPeriodShowsOnlyWhereItStarts() {
    let result = stops([.stated(year: 1999), .stated(year: 2001), .stated(year: 2003), .stated(year: 2006)], birthYear: 1990)
    #expect(result[0].periodAbove?.name == "Childhood")
    #expect(result[1].periodAbove == nil)
    #expect(result[2].periodAbove?.name == "Teens")
    #expect(result[3].periodAbove == nil)
}

@Test func aMomentBeforeBirthGetsADecade() {
    let result = stops([.stated(year: 1985), .stated(year: 1995)], birthYear: 1990)
    #expect(result[0].periodAbove == LifePeriod(name: "The 1980s", byAge: false))
    #expect(result[1].periodAbove?.name == "Childhood")
}

@Test func noBirthYearGivesDecades() {
    let result = stops([.stated(year: 1985), .stated(year: 1987)])
    #expect(result[0].periodAbove?.name == "The 1980s")
    #expect(result[1].periodAbove == nil)
}

@Test func undatedItemsAreSkipped() {
    let halfOpen = TimeRange(earliest: .firstOfYear(1990), latest: nil, likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: nil)
    let result = stops([.stated(year: 2000), halfOpen, .stated(year: 2001)])
    #expect(result.map(\.id) == ["m0", "m2"])
    #expect(result[1].gapAbove?.years == 1, "2000 to 2001, as if the half-open range were not there")
    #expect(result[1].showsYears)
}
