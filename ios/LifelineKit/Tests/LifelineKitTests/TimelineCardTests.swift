import Testing
@testable import LifelineKit

@Suite struct TimelineCardTests {
    private func chapter(_ title: String?, _ range: TimeRange) -> Chapter {
        Chapter(id: .init(), title: title, range: range, order: 0)
    }
    private func openEnded(from year: Int) -> TimeRange {
        var range = TimeRange.stated(year: year)
        range.latest = nil
        return range
    }
    private func card(moments: [TimeRange] = [.stated(year: 1999)], chapters: [Chapter] = [], onScreen: [ClosedRange<Int>],
                      birth: Int? = 1990, now: Int = 2026) -> TimelineCard {
        TimelineCard(moments: moments, chapters: chapters, onScreen: onScreen, birthYear: birth, currentYear: now)
    }

    // MARK: Frame

    @Test func theFrameCoversTheYearsOnScreen() {
        let c = card(onScreen: [1999...1999, 2000...2000, 2003...2003])
        #expect(c.frameYears == 1999...2003)
        #expect(c.frame == (9.0 / 37.0)...(14.0 / 37.0))
    }
    @Test func nothingOnScreenIsNoFrame() {
        let c = card(onScreen: [])
        #expect(c.frame == nil && c.frameYears == nil)
    }
    @Test func aFrameIsClampedToTheStrip() {
        let c = card(onScreen: [1980...1985])
        #expect(c.frame.map { $0.lowerBound >= 0 && $0.upperBound <= 1 } == true)
    }
    @Test func aFrameAfterNowIsClampedToTheStrip() {
        let c = card(onScreen: [2030...2031])
        #expect(c.frame == 1...1)
    }
    @Test func aRowThatLeftDoesNotHoldTheFrame() {
        let moments: [TimeRange] = [.stated(year: 1999), .stated(year: 2010)]
        let before = card(moments: moments, onScreen: [1999...1999, 2010...2010])
        let after = card(moments: moments, onScreen: [1999...1999])
        #expect(before.frameYears == 1999...2010)
        #expect(after.frameYears == 1999...1999)
    }

    // MARK: During

    @Test func duringNamesTheChaptersThatOverlapTheFrame() {
        let chapters = [chapter("Maple Street", .stated(between: 1998, and: 2001)), chapter("The band", .stated(between: 2005, and: 2007))]
        #expect(card(chapters: chapters, onScreen: [1999...2003]).during.map(\.name) == ["Maple Street"])
    }
    @Test func aChapterThatTouchesTheFrameByOneYearCounts() {
        let chapters = [chapter("Maple Street", .stated(between: 1998, and: 2001))]
        #expect(card(chapters: chapters, onScreen: [2001...2003]).during.map(\.name) == ["Maple Street"])
    }
    @Test func theLongestChapterComesFirst() {
        let chapters = [chapter("Short", .stated(between: 1998, and: 2001)), chapter("Long", .stated(between: 1995, and: 2010))]
        #expect(card(chapters: chapters, onScreen: [1999...2000]).during.map(\.name) == ["Long", "Short"])
    }
    @Test func tiesGoToTheEarlierStartThenTheName() {
        let chapters = [chapter("B", .stated(between: 2000, and: 2002)), chapter("A", .stated(between: 2000, and: 2002)),
                        chapter("Early", .stated(between: 1999, and: 2001))]
        #expect(card(chapters: chapters, onScreen: [2000...2001]).during.map(\.name) == ["Early", "A", "B"])
    }
    @Test func aChapterWithNoEndRunsToNow() {
        let chapters = [chapter("Now", openEnded(from: 2015)), chapter("Closed", .stated(between: 2020, and: 2025))]
        let c = card(chapters: chapters, onScreen: [2024...2025])
        #expect(c.during.map(\.name) == ["Now", "Closed"], "2015 to 2026 is 12 years; 2020 to 2025 is 6")
    }
    @Test func aChapterWithoutStatedYearsIsNeverDuring() {
        let chapters = [chapter("Unplaced", .unplaced),
                        chapter("Derived", .year(2001, origin: .derived, evidence: nil)),
                        chapter("Inferred", .year(2001, origin: .inferred, evidence: nil))]
        #expect(card(chapters: chapters, onScreen: [1999...2003]).during.isEmpty)
    }
    @Test func aChapterWithNoNameIsNeverDuring() {
        let chapters = [chapter(nil, .stated(between: 1998, and: 2001)), chapter("  ", .stated(between: 1998, and: 2001))]
        #expect(card(chapters: chapters, onScreen: [1999...2003]).during.isEmpty)
    }
    @Test func aChapterWhoseYearsHoldNoMomentCanBeDuring() {
        let chapters = [chapter("The band", .stated(between: 2005, and: 2007))]
        let c = card(moments: [.stated(year: 1999), .stated(year: 2003)], chapters: chapters, onScreen: [2003...2006])
        #expect(c.during.map(\.name) == ["The band"])
    }
    @Test func noFrameIsNoDuring() {
        let chapters = [chapter("Maple Street", .stated(between: 1998, and: 2001))]
        #expect(card(chapters: chapters, onScreen: []).during.isEmpty)
    }

    // MARK: Text

    private func thirty() -> TimelineCard {
        card(chapters: (1...30).map { chapter("Chapter \($0)", .stated(between: 1998, and: 2001)) }, onScreen: [1999...2000])
    }
    @Test func thirtyChaptersKeepTheirOrder() {
        let c = thirty()
        #expect(c.during.count == 30)
        #expect(c.duringText(showing: 2) == "Chapter 1 · Chapter 10")
        #expect(c.overflow(showing: 2) == "+28")
        #expect(c.overflow(showing: 30) == nil)
    }
    @Test func duringTextForNoneIsNil() {
        #expect(thirty().duringText(showing: 0) == nil)
        let none = card(onScreen: [1999...2000])
        #expect(none.duringText(showing: 3) == nil)
        #expect(none.overflow(showing: 0) == nil)
    }

    // MARK: Strip

    @Test func withNoDatedMomentTheCardIsEmpty() {
        #expect(card(moments: [.unplaced], onScreen: []).isEmpty)
        #expect(card(moments: [], onScreen: []).isEmpty)
        let one = card(onScreen: [1999...1999])
        #expect(!one.isEmpty && one.strip.marks.count == 1)
    }
    @Test func withNoBirthDateTheStripStartsAtTheFirstMoment() {
        #expect(card(moments: [.stated(year: 2004), .stated(year: 2001)], onScreen: [], birth: nil).strip.startYear == 2001)
    }
    @Test func aMomentBeforeTheBirthYearMovesTheStart() {
        #expect(card(moments: [.stated(year: 1985)], onScreen: [1985...1985]).strip.startYear == 1985)
    }

    // MARK: Spoken text

    /// Each name gets a shorter chapter than the one before, so the order is the order given.
    private func spoken(_ names: [String]) -> String {
        let chapters = names.enumerated().map { chapter($1, .stated(between: 1998, and: 2010 - $0)) }
        return card(moments: [.stated(year: 1998)], chapters: chapters, onScreen: [1998...2003], birth: 1998).spokenText
    }
    @Test func theSpokenTextIsTheSpecsSentence() {
        let text = spoken(["Maple Street", "Summers at the lake", "Third", "Fourth"])
        #expect(text == "Your life from 1998 to now. On screen: 1998 to 2003. During Maple Street, Summers at the lake and 2 more.")
    }
    @Test func theSpokenTextNamesOneTwoOrThreeChapters() {
        #expect(spoken(["Maple Street"]).hasSuffix("During Maple Street."))
        #expect(spoken(["Maple Street", "Summers at the lake"]).hasSuffix("During Maple Street and Summers at the lake."))
        #expect(spoken(["Maple Street", "Summers at the lake", "Third"]).hasSuffix("During Maple Street, Summers at the lake and 1 more."))
    }
    @Test func theSpokenTextWithNoChapterHasNoDuringSentence() {
        #expect(spoken([]) == "Your life from 1998 to now. On screen: 1998 to 2003.")
    }
    @Test func theSpokenTextWithNoFrameIsTheLifeAlone() {
        #expect(card(moments: [.stated(year: 1998)], onScreen: [], birth: 1998).spokenText == "Your life from 1998 to now.")
    }
    @Test func theSpokenTextForOneYearOnScreen() {
        #expect(card(onScreen: [1999...1999]).spokenText == "Your life from 1990 to now. On screen: 1999.")
    }
}
