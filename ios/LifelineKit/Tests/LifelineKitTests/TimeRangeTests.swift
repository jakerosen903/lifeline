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

// MARK: - Stated ranges (M4.1: "Tell me when")

@Test func statedShapesDisplayAsSaid() {
    let year = TimeRange.stated(year: 1998)
    #expect(year.displayText == "1998" && year.origin == .stated && year.isSettled && year.evidenceText == "1998")
    let around = TimeRange.stated(around: 1998)
    #expect(around.displayText == "around 1998" && around.earliest?.year == 1997 && around.latest?.year == 1999 && around.likelyStart?.year == 1998 && around.origin == .stated)
    let between = TimeRange.stated(between: 1999, and: 1996)
    #expect(between.displayText == "1996–99" && between.earliest?.year == 1996 && between.latest?.year == 1999 && between.origin == .stated)
    #expect(TimeRange.stated(year: 1800).earliest?.year == 1900 && TimeRange.stated(year: 2500).latest?.year == 2099, "years clamp to the resolver's range")
    #expect(TimeRange.year(1998, origin: .stated, evidence: "in 1998").displayText == "1998", "an anchor's evidence still reads as a year")
}

@Test func statedAgeUsesTheBirthday() throws {
    let birth = try #require(CivilDate(iso: "1990-06-15"))
    let range = TimeRange.stated(age: .approximate(center: 8, slack: 0), birth: birth, evidence: "about 8")
    #expect(range.earliest == CivilDate(iso: "1998-06-15") && range.latest == CivilDate(iso: "1999-06-14"))
    #expect(range.origin == .stated && range.evidenceText == "about 8" && range.displayText == "about 8")
}
