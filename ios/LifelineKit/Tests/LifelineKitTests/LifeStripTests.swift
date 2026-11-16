import Testing
@testable import LifelineKit

private func said(_ y: Int) -> TimeRange { .year(y, origin: .stated, evidence: "in \(y)") }
private func guess(_ y: Int) -> TimeRange { .year(y, origin: .inferred, evidence: nil) }

@Suite struct LifeStripTests {
    @Test func theSentenceCountsMoments() {
        #expect(LifeStrip(moments: [], birthYear: 1990, currentYear: 2026).sentence == nil)
        #expect(LifeStrip(moments: [.unplaced], birthYear: 1990, currentYear: 2026).sentence == "In one moment")
        #expect(LifeStrip(moments: [.unplaced, .unplaced, .unplaced], birthYear: 1990, currentYear: 2026).sentence == "In 3 moments")
    }
    @Test func oneDatedMomentSaysItsOwnDate() {
        #expect(LifeStrip(moments: [said(1995)], birthYear: 1990, currentYear: 2026).sentence == "In one moment, in 1995")
        #expect(LifeStrip(moments: [guess(1995)], birthYear: 1990, currentYear: 2026).sentence == "In one moment, around 1995")
        #expect(LifeStrip(moments: [.stated(between: 1996, and: 1999)], birthYear: 1990, currentYear: 2026).sentence == "In one moment, from 1996 to 1999")
    }
    @Test func severalDatedMomentsSayTheirRange() {
        let years = [1999, 2000, 2001, 2003]
        #expect(LifeStrip(moments: years.map(said), birthYear: 1990, currentYear: 2026).sentence == "In 4 moments, from 1999 to 2003")
        #expect(LifeStrip(moments: years.map(guess), birthYear: 1990, currentYear: 2026).sentence == "In 4 moments, between 1999 and 2003")
        #expect(LifeStrip(moments: [said(1999), said(2003), .unplaced], birthYear: 1990, currentYear: 2026).sentence == "In 3 moments, from 1999 to 2003")
    }
    @Test func aClusterSaysMost() {
        let years = [1992, 1999, 1999, 2000, 2001, 2001, 2002, 2003, 2003, 2010, 2016, 2020]
        #expect(LifeStrip(moments: years.map(said), birthYear: 1990, currentYear: 2026).sentence == "In 12 moments, most between 1999 and 2003")
        #expect(LifeStrip(moments: Array(years.map(said).dropLast()) + [guess(2020)], birthYear: 1990, currentYear: 2026).sentence == "In 12 moments, most between about 1999 and 2003")
    }
    @Test func fiveMomentsInOneYearDoNotSayMost() {
        let strip = LifeStrip(moments: Array(repeating: said(2000), count: 5), birthYear: 1990, currentYear: 2026)
        #expect(strip.sentence == "In 5 moments, in 2000")
    }
    @Test func marksSitOnTheAxisFromBirthToNow() {
        let strip = LifeStrip(moments: [said(1999), guess(2010), .unplaced], birthYear: 1990, currentYear: 2025)
        #expect(strip.startYear == 1990 && strip.endYear == 2025)
        #expect(strip.marks.count == 2 && strip.showsAxis)
        #expect(abs(strip.marks[0].position - 9.5 / 36) < 0.0001 && !strip.marks[0].isGuess)
        #expect(strip.marks[1].isGuess)
    }
    @Test func aMomentBeforeBirthWidensTheAxis() {
        let strip = LifeStrip(moments: [said(1985), said(2000)], birthYear: 1990, currentYear: 2025)
        #expect(strip.startYear == 1985 && strip.marks[0].position >= 0 && strip.marks[0].position < 0.05)
    }
    @Test func withNoBirthDateTheAxisStartsAtTheFirstMoment() {
        #expect(LifeStrip(moments: [said(2005), said(2012)], birthYear: nil, currentYear: 2025).startYear == 2005)
    }
    @Test func fewerThanTwoDatedMomentsHideTheAxis() {
        #expect(!LifeStrip(moments: [said(2012), .unplaced], birthYear: 1990, currentYear: 2025).showsAxis)
    }
    @Test func onlyAStatedSpanDrawsABar() {
        #expect(LifeStrip(moments: [said(1999), said(2001)], birthYear: 1990, currentYear: 2025).statedSpan == nil)
        let bar = LifeStrip(moments: [said(1999), said(2001)], stated: .stated(between: 1995, and: 2004), birthYear: 1990, currentYear: 2025).statedSpan
        #expect(bar.map { abs($0.lowerBound - 5.0 / 36) < 0.0001 && abs($0.upperBound - 15.0 / 36) < 0.0001 } == true)
    }
    @Test func theAxisNeverBreaksWithNothingToPlace() {
        let strip = LifeStrip(moments: [], birthYear: nil, currentYear: 2025)
        #expect(strip.startYear == 2025 && strip.marks.isEmpty && !strip.showsAxis)
        let future = LifeStrip(moments: [said(2030)], birthYear: 2030, currentYear: 2025)
        #expect(future.marks[0].position >= 0 && future.marks[0].position <= 1)
    }
}
