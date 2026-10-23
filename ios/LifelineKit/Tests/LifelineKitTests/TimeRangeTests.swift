import Testing
@testable import LifelineKit

private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }

@Test func rangeDisplayTextFollowsTheCanvases() {
    #expect(TimeRange.year(1998, origin: .stated, evidence: "in 1998").displayText == "1998")
    #expect(TimeRange.year(1998, origin: .inferred, evidence: "when I was twelve").displayText == "around 1998")
    let probable = TimeRange(earliest: d("1996-01-01"), latest: d("2001-12-31"), likelyStart: d("1997-01-01"), likelyEnd: d("1998-12-31"),
                             granularity: .year, origin: .inferred, evidenceText: "one of those summers")
    #expect(probable.displayText == "probably 1997–98")
    #expect(TimeRange(earliest: d("1994-03-01"), latest: d("1994-03-31"), likelyStart: nil, likelyEnd: nil, granularity: .month, origin: .stated, evidenceText: nil).displayText == "March 1994")
    #expect(TimeRange(earliest: d("1994-03-12"), latest: d("1994-03-12"), likelyStart: nil, likelyEnd: nil, granularity: .day, origin: .confirmed, evidenceText: nil).displayText == "12 March 1994")
    #expect(TimeRange(earliest: d("1990-01-01"), latest: d("1999-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .decade, origin: .inferred, evidenceText: "the nineties").displayText == "sometime in the 1990s")
    #expect(TimeRange(earliest: d("1998-06-01"), latest: d("1998-08-31"), likelyStart: nil, likelyEnd: nil, granularity: .season, origin: .stated, evidenceText: "summer of 98").displayText == "summer 1998")
    #expect(TimeRange(earliest: d("1996-01-01"), latest: d("2001-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .era, origin: .inferred, evidenceText: "the Boston years").displayText == "sometime in the Boston years")
    #expect(TimeRange.unplaced.displayText == "no date yet")
    #expect(!TimeRange.unplaced.isPlaced && TimeRange.year(1998, origin: .stated, evidence: nil).isPlaced)
}

@Test func rangeIntersectionIsNilWhenApart() {
    let y1998 = TimeRange.year(1998, origin: .stated, evidence: nil)
    let early = TimeRange(earliest: d("1992-01-01"), latest: d("1993-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: nil)
    #expect(y1998.intersect(early) == nil)
    let wide = TimeRange(earliest: d("1996-01-01"), latest: d("2001-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: nil)
    let narrowed = wide.intersect(y1998)
    #expect(narrowed?.earliest == d("1998-01-01") && narrowed?.latest == d("1998-12-31"))
}

@Test func widenedMovesOneEdgeByYears() {
    let y1998 = TimeRange.year(1998, origin: .stated, evidence: nil)
    let after = y1998.widened(by: 5, toward: .later)
    #expect(after.earliest == d("1998-01-01") && after.latest == d("2003-12-31"))
    let before = y1998.widened(by: 5, toward: .earlier)
    #expect(before.earliest == d("1993-01-01") && before.latest == d("1998-12-31"))
}

@Test func aGuessOverTwoCalendarYearsStillReadsAsAround() {
    // An age band from a May birthday: 1992-05-10 to 1993-05-09 is one year that touches two calendar years.
    let ageBand = TimeRange(earliest: d("1992-05-10"), latest: d("1993-05-09"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: "when I was six")
    #expect(ageBand.displayText == "around 1992–93")
    let wide = TimeRange(earliest: d("1993-01-01"), latest: d("1998-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: nil)
    #expect(wide.displayText == "sometime between 1993–98")
}
