import Testing
@testable import LifelineKit

// S6a: the life period a year falls in, by age when the birth year is known. Invented years only.

@Test func agesMapToTheirPeriod() {
    func name(_ year: Int) -> String { LifePeriod.containing(year: year, birthYear: 1990).name }
    #expect(name(1990) == "Childhood")
    #expect(name(2002) == "Childhood")
    #expect(name(2003) == "Teens")
    #expect(name(2009) == "Teens")
    #expect(name(2010) == "Twenties")
    #expect(name(2089) == "Nineties")
    #expect([1990, 2002, 2003, 2009, 2010, 2089].allSatisfy { LifePeriod.containing(year: $0, birthYear: 1990).byAge })
}

@Test func everyDecadeOfAdulthoodHasItsName() {
    let names = [30: "Thirties", 40: "Forties", 50: "Fifties", 60: "Sixties", 70: "Seventies", 80: "Eighties"]
    for (age, name) in names {
        #expect(LifePeriod.containing(year: 1990 + age, birthYear: 1990).name == name)
        #expect(LifePeriod.containing(year: 1990 + age + 9, birthYear: 1990).name == name)
    }
    #expect(LifePeriod.containing(year: 1990 + 12, birthYear: 1990).name == "Childhood")
    #expect(LifePeriod.containing(year: 1990 + 13, birthYear: 1990).name == "Teens")
    #expect(LifePeriod.containing(year: 1990 + 19, birthYear: 1990).name == "Teens")
    #expect(LifePeriod.containing(year: 1990 + 20, birthYear: 1990).name == "Twenties")
}

@Test func withNoBirthYearItIsTheDecade() {
    let period = LifePeriod.containing(year: 2004, birthYear: nil)
    #expect(period.name == "The 2000s")
    #expect(!period.byAge)
}

@Test func beforeBirthAndPastAHundredAreDecades() {
    let before = LifePeriod.containing(year: 1984, birthYear: 1990)
    #expect(before.name == "The 1980s")
    #expect(!before.byAge)
    let after = LifePeriod.containing(year: 2090, birthYear: 1990)
    #expect(after.name == "The 2090s")
    #expect(!after.byAge)
    #expect(LifePeriod.containing(year: 2089, birthYear: 1990).byAge, "age 99 is still by age")
}

@Test func aNegativeYearStillFloorsToItsDecade() {
    // Decade of a year before 1 CE: floor division, not truncation toward zero.
    #expect(LifePeriod.containing(year: -5, birthYear: nil).name == "The -10s")
}

@Test func headingTextSaysByYourAgeOnlyForAnAgePeriod() {
    #expect(LifePeriod.containing(year: 2005, birthYear: 1990).headingText == "Teens · by your age")
    #expect(LifePeriod.containing(year: 2005, birthYear: nil).headingText == "The 2000s")
}
