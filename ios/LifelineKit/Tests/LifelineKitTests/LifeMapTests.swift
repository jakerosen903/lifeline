import Testing
@testable import LifelineKit

@Suite struct LifeMapTests {
    private func chapter(_ title: String?, _ range: TimeRange, order: Int = 0) -> Chapter {
        Chapter(id: .init(), title: title, range: range, order: order)
    }
    private func map(_ chapters: [Chapter], counts: [ChapterID: Int] = [:], birth: Int? = 1990, now: Int = 2026) -> LifeMap {
        LifeMap(chapters: chapters, momentCounts: counts, birthYear: birth, currentYear: now)
    }

    @Test func rowsAreInOrderOfStartThenLongestFirst() {
        let a = chapter("A", .stated(between: 2000, and: 2003))
        let b = chapter("B", .stated(between: 1998, and: 2001))
        let c = chapter("C", .stated(between: 2000, and: 2010))
        #expect(map([a, b, c]).rows.map(\.title) == ["B", "C", "A"])
    }
    @Test func theAxisRunsFromTheBirthYearToNow() {
        let m = map([chapter("A", .stated(between: 2008, and: 2012))])
        #expect(m.startYear == 1990 && m.endYear == 2026)
        #expect(m.rows[0].start == 18.0 / 37.0)
        #expect(m.rows[0].end == 23.0 / 37.0)
    }
    @Test func withNoBirthYearTheAxisStartsAtTheEarliestChapter() {
        let m = map([chapter("A", .stated(between: 2008, and: 2012)), chapter("B", .stated(between: 2003, and: 2004))], birth: nil)
        #expect(m.startYear == 2003)
        #expect(m.rows[0].start == 0)
    }
    @Test func aChapterBeforeTheBirthYearMovesTheAxisStart() {
        let m = map([chapter("A", .stated(between: 1985, and: 1988))])
        #expect(m.startYear == 1985)
        #expect(m.rows.allSatisfy { $0.start >= 0 })
    }
    @Test func aChapterWithNoStatedEndRunsToTheRightEdge() {
        var range = TimeRange.stated(year: 2010)
        range.latest = nil
        #expect(map([chapter("A", range)]).rows[0].end == 1)
    }
    @Test func aChapterThatEndsAfterNowIsCutAtTheRightEdge() {
        #expect(map([chapter("A", .stated(between: 2020, and: 2030))]).rows[0].end == 1)
    }
    @Test func chaptersWithoutStatedYearsAreUnplaced() {
        let a = chapter("A", .unplaced, order: 0)
        let b = chapter("B", .year(2003, origin: .derived, evidence: nil), order: 1)
        let m = map([a, b])
        #expect(m.unplaced.map(\.title) == ["A", "B"])
        #expect(m.rows.isEmpty)
    }
    @Test func aChapterWithNoNameReadsNoNameYet() {
        let m = map([chapter(nil, .stated(year: 2000)), chapter("  ", .unplaced)])
        #expect(m.rows[0].title == "No name yet")
        #expect(m.unplaced[0].title == "No name yet")
    }
    @Test func periodsCoverTheAxisByAge() {
        let m = map([])
        #expect(m.periods.map(\.name) == ["Childhood", "Teens", "Twenties", "Thirties"])
        #expect(m.periods[0].start == 0)
        #expect(m.periods[0].end == 13.0 / 37.0)
        #expect(m.periods[1].start == 13.0 / 37.0)
        #expect(m.periods[1].end == 20.0 / 37.0)
        for (a, b) in zip(m.periods, m.periods.dropFirst()) { #expect(a.end == b.start) }
        #expect(m.periods.last?.end == 1)
    }
    @Test func withNoBirthYearThePeriodsAreDecades() {
        let m = map([chapter("A", .stated(between: 2000, and: 2012))], birth: nil)
        #expect(m.periods.map(\.name) == ["The 2000s", "The 2010s", "The 2020s"])
    }
    @Test func thirtyChaptersAllGetARow() {
        let chapters = (0..<30).map { chapter("C\($0)", .stated(between: 1990 + $0, and: 1991 + $0), order: $0) }
        #expect(map(chapters).rows.count == 30)
    }
    @Test func noChaptersIsEmpty() {
        let m = map([])
        #expect(m.isEmpty && m.rows.isEmpty && m.unplaced.isEmpty)
    }
    @Test func aSingleYearAxisHasOneBand() {
        let m = map([], birth: nil, now: 2026)
        #expect(m.startYear == 2026 && m.endYear == 2026)
        #expect(m.periods.count == 1 && m.periods[0].start == 0 && m.periods[0].end == 1)
    }
    @Test func axisYearsAreEveryFifthYear() {
        #expect(map([], birth: 1998, now: 2012).axisYears == [2000, 2005, 2010])
    }
    @Test func theSummaryNamesTheYearsAndTheCount() {
        let c = chapter("Maple Street", .stated(between: 1998, and: 2001))
        let three = map([c], counts: [c.id: 3])
        #expect(three.summary(of: three.rows[0]) == "Maple Street, 1998–2001, 3 moments")
        let one = map([c], counts: [c.id: 1])
        #expect(one.summary(of: one.rows[0]) == "Maple Street, 1998–2001, 1 moment")
        let zero = map([c])
        #expect(zero.summary(of: zero.rows[0]) == "Maple Street, 1998–2001")
    }
}
