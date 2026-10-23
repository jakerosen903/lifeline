import Testing
@testable import LifelineKit

@Test func civilDateRoundTripsISOAndOrders() throws {
    let d = try #require(CivilDate(iso: "1998-03-02"))
    #expect(d.year == 1998 && d.month == 3 && d.day == 2 && d.iso == "1998-03-02")
    #expect(d < CivilDate(iso: "1998-03-03")!)
    #expect(CivilDate(iso: "1998-3-2") == nil && CivilDate(iso: "19980302") == nil && CivilDate(iso: "1998-13-01") == nil && CivilDate(iso: "1998-02-30") == nil)
}

@Test func civilDateArithmeticHandlesYearEnds() throws {
    #expect(CivilDate(iso: "1999-12-31")!.adding(days: 1).iso == "2000-01-01")
    #expect(CivilDate.lastOfYear(2000).iso == "2000-12-31" && CivilDate.firstOfYear(2000).iso == "2000-01-01")
    #expect(CivilDate(iso: "2000-02-29")!.adding(years: 1).iso == "2001-02-28")
    #expect(CivilDate.last(ofMonth: 2, year: 2000).iso == "2000-02-29" && CivilDate.first(ofMonth: 12, year: 1990).iso == "1990-12-01")
    #expect(CivilDate(iso: "1986-05-10")!.adding(days: -1).iso == "1986-05-09")
}
