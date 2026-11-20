import Testing
@testable import LifelineKit

// S7: which group each thing on the shelf sits in, and in what order. Invented things and years only.
// Birth year 1990 unless a test says otherwise.

private func said(_ y: Int) -> TimeRange { .stated(year: y) }
private func guess(_ y: Int) -> TimeRange { .year(y, origin: .inferred, evidence: nil) }
private func thing(_ title: String, _ moments: [TimeRange] = [], stated: TimeRange = .unplaced) -> EntitySummary {
    EntitySummary(entity: Entity(id: EntityID(rawValue: title), type: .thing, title: title, range: stated),
                  ownWords: nil, momentRanges: moments, span: stated)
}
/// The titles of each group, top to bottom; one array for `.flat`.
private func titles(_ layout: ThingShelf.Layout) -> [[String]] {
    switch layout {
    case .flat(let tiles): return [tiles.map(\.summary.entity.title)]
    case .grouped(let groups): return groups.map { $0.tiles.map(\.summary.entity.title) }
    }
}
/// `Heading.text` of each group; empty for `.flat`.
private func headings(_ layout: ThingShelf.Layout) -> [String] {
    if case .grouped(let groups) = layout { return groups.map(\.heading.text) }
    return []
}
/// The tile with this title, in any group.
private func tile(_ title: String, in layout: ThingShelf.Layout) -> ThingShelf.Tile? {
    switch layout {
    case .flat(let tiles): return tiles.first { $0.summary.entity.title == title }
    case .grouped(let groups): return groups.flatMap(\.tiles).first { $0.summary.entity.title == title }
    }
}

@Test func aThingSitsOnceInThePeriodOfItsEarliestDatedMoment() {
    let layout = ThingShelf.layout([thing("The red bike", [said(2004), said(1999)])], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age"])
    #expect(titles(layout) == [["The red bike"]], "not again under Teens")
}
@Test func groupsRunInLifeOrderAndNotPlacedComesLast() {
    let layout = ThingShelf.layout([thing("The radiator", [guess(2012)]), thing("Grandpa's watch", [.unplaced]), thing("The red bike", [said(1999)])], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age", "Twenties · by your age", "Not placed in time yet"])
}
@Test func tilesInAPeriodRunByPlacingDateThenTitle() {
    let layout = ThingShelf.layout([thing("Dad's Volvo", [said(2001)]), thing("The red bike", [said(1999)]),
                                    thing("another bike", [said(1999)]), thing("The piano", stated: .stated(between: 1996, and: 2002))], birthYear: 1990)
    #expect(titles(layout) == [["The piano", "another bike", "The red bike", "Dad's Volvo"]])
}
@Test func notPlacedRunsByTitleIgnoringCase() {
    let layout = ThingShelf.layout([thing("the guitar"), thing("The blue kite", [.unplaced]), thing("Grandpa's watch"), thing("The red bike", [said(1999)])], birthYear: 1990)
    #expect(titles(layout).last == ["Grandpa's watch", "The blue kite", "the guitar"])
}
@Test func twoThingsWithOneTitleKeepAnOrderById() {
    let a = EntitySummary(entity: Entity(id: EntityID(rawValue: "a"), type: .thing, title: "The box"), ownWords: nil, momentRanges: [], span: .unplaced)
    let b = EntitySummary(entity: Entity(id: EntityID(rawValue: "b"), type: .thing, title: "The box"), ownWords: nil, momentRanges: [], span: .unplaced)
    guard case .flat(let tiles) = ThingShelf.layout([b, a], birthYear: 1990) else { Issue.record("flat"); return }
    #expect(tiles.map(\.id.rawValue) == ["a", "b"])
}
@Test func withNoPlacedThingTheShelfIsFlat() {
    let watch = thing("Grandpa's watch", [.unplaced]), guitar = thing("The guitar")
    #expect(ThingShelf.layout([guitar, watch], birthYear: 1990)
            == .flat([ThingShelf.Tile(summary: watch, placedByGuess: false), ThingShelf.Tile(summary: guitar, placedByGuess: false)]))
}
@Test func noThingIsAnEmptyFlatShelf() {
    #expect(ThingShelf.layout([], birthYear: 1990) == .flat([]))
}
@Test func aStatedSpanPlacesAThingWithNoDatedMoment() {
    let layout = ThingShelf.layout([thing("The piano", [.unplaced], stated: .stated(between: 1996, and: 2002))], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age"])
    #expect(tile("The piano", in: layout)?.placedByGuess == false)
}
// R5: the person's own dated span places the thing before any moment, said or guessed.
@Test func theStatedSpanBeatsADatedMoment() {
    let layout = ThingShelf.layout([thing("The piano", [said(2012)], stated: .stated(between: 1996, and: 2002))], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age"])
}
@Test func theStatedSpanBeatsAGuessedMomentAndShowsNoMark() {
    let layout = ThingShelf.layout([thing("The piano", [guess(2012)], stated: .stated(between: 1996, and: 2002))], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age"])
    #expect(titles(layout) == [["The piano"]], "not again under Twenties")
    #expect(tile("The piano", in: layout)?.placedByGuess == false)
}
@Test func aHalfOpenStatedSpanLetsADatedMomentPlace() {
    let halfOpen = TimeRange(earliest: CivilDate(iso: "1999-01-01"), latest: nil, likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .stated, evidenceText: nil)
    let layout = ThingShelf.layout([thing("The piano", [guess(2012)], stated: halfOpen)], birthYear: 1990)
    #expect(headings(layout) == ["Twenties · by your age"])
    #expect(tile("The piano", in: layout)?.placedByGuess == true)
}
@Test func withNoStatedSpanTheEarliestMomentStillPlaces() {
    let layout = ThingShelf.layout([thing("The kite", [said(2012), guess(2003)])], birthYear: 1990)
    #expect(headings(layout) == ["Teens · by your age"])
    #expect(tile("The kite", in: layout)?.placedByGuess == true)
}
@Test func aGuessedDateMarksTheTile() {
    let layout = ThingShelf.layout([thing("The radiator", [guess(2012)]), thing("The red bike", [said(1999)])], birthYear: 1990)
    #expect(tile("The radiator", in: layout)?.placedByGuess == true)
    #expect(tile("The red bike", in: layout)?.placedByGuess == false)
}
@Test func aSettledMomentInThePeriodClearsTheMark() {
    #expect(tile("The kite", in: ThingShelf.layout([thing("The kite", [guess(1999), said(2001)])], birthYear: 1990))?.placedByGuess == false)
}
@Test func aGuessInAnEarlierPeriodDecidesAndKeepsItsMark() {
    let layout = ThingShelf.layout([thing("The kite", [said(2012), guess(2003)])], birthYear: 1990)
    #expect(headings(layout) == ["Teens · by your age"])
    #expect(tile("The kite", in: layout)?.placedByGuess == true)
}
// R4: "before Graduation" is confirmed, but its year is the builder's slack (2004 less 5 years), not the person's word.
@Test func aConfirmedRelationDoesNotClearTheMark() {
    let before = TimeRange.span(.firstOfYear(1999), .lastOfYear(2004), granularity: .year, origin: .confirmed, evidence: "before Graduation (2004)")
    let layout = ThingShelf.layout([thing("The kite", [before]), thing("The red bike", [before, said(2001)])], birthYear: 1990)
    #expect(headings(layout) == ["Childhood · by your age"])
    #expect(tile("The kite", in: layout)?.placedByGuess == true)
    #expect(tile("The red bike", in: layout)?.placedByGuess == false, "a year the person said in the same period clears it")
}
@Test func thePersonsOwnAroundIsNotAGuess() {
    #expect(tile("The kite", in: ThingShelf.layout([thing("The kite", [.stated(around: 1999)])], birthYear: 1990))?.placedByGuess == false)
}
@Test func aPhotoDateIsNotAGuess() {
    #expect(tile("The kite", in: ThingShelf.layout([thing("The kite", [.fromPhoto(CivilDate(year: 1999, month: 7, day: 4)!)])], birthYear: 1990))?.placedByGuess == false)
}
@Test func withNoBirthYearPeriodsAreDecades() {
    let layout = ThingShelf.layout([thing("The radiator", [said(2012)]), thing("The red bike", [said(1999)])], birthYear: nil)
    #expect(headings(layout) == ["The 1990s", "The 2010s"])
}
@Test func aMomentBeforeBirthUsesItsDecadeAndComesFirst() {
    let layout = ThingShelf.layout([thing("The red bike", [said(1999)]), thing("Mum's radio", [said(1985)])], birthYear: 1990)
    #expect(headings(layout) == ["The 1980s", "Childhood · by your age"])
}
@Test func theLikelyBandDecidesThePeriodAsOnTheSpine() {
    let band = TimeRange(earliest: CivilDate(iso: "1998-01-01"), latest: CivilDate(iso: "2006-12-31"), likelyStart: CivilDate(iso: "2003-01-01"),
                         likelyEnd: CivilDate(iso: "2004-12-31"), granularity: .year, origin: .inferred, evidenceText: nil)
    #expect(headings(ThingShelf.layout([thing("The kite", [band])], birthYear: 1990)) == ["Teens · by your age"])
}
@Test func aHalfOpenRangePlacesNothing() {
    let halfOpen = TimeRange(earliest: CivilDate(iso: "1999-01-01"), latest: nil, likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .stated, evidenceText: nil)
    let kite = thing("The kite", [halfOpen])
    #expect(ThingShelf.layout([kite], birthYear: 1990) == .flat([ThingShelf.Tile(summary: kite, placedByGuess: false)]))
}
