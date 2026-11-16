import Foundation
import Testing
@testable import LifelineKit

// S3, Task 2: the portrait decides the You page's parts, its lead line, and its copy. Invented words only.

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

private func told(_ n: Int, ms: Int = 1_000) -> Telling {
    Telling(sessionID: .init(), audioPath: "s\(n).m4a", range: MsRange(start: 0, end: ms), toldAt: date(2026, 9, n + 1))
}

private func memory(_ title: String, quote: String, kind: MemoryKind, at n: Int, hidden: Bool = false, floating: Bool = false) -> Memory {
    Memory(id: .init(), title: title, summaryQuote: quote, visibility: .timeline, chapterID: nil,
           createdFromCandidateID: floating ? nil : CandidateID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)),
           hiddenFromTimeline: hidden, kind: kind)
}

private func moment(_ year: Int, at n: Int) -> Memory {
    var m = memory("Moment \(year)", quote: "it happened", kind: .event, at: n)
    m.range = TimeRange(earliest: .firstOfYear(year), latest: .lastOfYear(year), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .stated, evidenceText: nil)
    return m
}

private func makeSource(owner: Entity? = nil, profile: Profile? = nil, birth: CivilDate? = nil, ownerMoments: [Memory] = [], memories: [Memory] = [],
                    links: [MemoryID: [AboutLink]] = [:], tags: [MemoryID: [String]] = [:], tellings: [MemoryID: Telling] = [:],
                    ideas: [Entity] = [], ideaTellings: [EntityID: Telling] = [:]) -> PortraitSource {
    PortraitSource(profile: profile, owner: owner, birth: birth, ownerMoments: ownerMoments, aboutMemories: memories, links: links,
                   memoryTags: Dictionary(uniqueKeysWithValues: tags.map { ($0.key.rawValue, $0.value) }),
                   memoryTellings: tellings, ideas: ideas, ideaTellings: ideaTellings)
}

private let jordan = Entity(type: .person, title: "Jordan")
private let maya = Entity(type: .person, title: "Maya")
private func link(_ e: Entity, _ r: EntityRelation) -> AboutLink { AboutLink(entity: e, relation: r) }

/// Facts f1 to f6, feelings e1 e2 e3, goal g1, and an idea; each with own words and a recording except where noted.
private struct World {
    let f1 = memory("Took things apart", quote: "um, I was always the kid who took things apart", kind: .fact, at: 1)
    let f2 = memory("Liked school", quote: "I liked school well enough", kind: .fact, at: 2)
    let f3 = memory("Maya's habit", quote: "she hums while she cooks", kind: .fact, at: 3)
    let f4 = memory("Mentions Maya", quote: "my sister and I shared a room", kind: .fact, at: 4)
    let f5 = memory("Family dinners", quote: "we ate together every Sunday", kind: .fact, at: 5)
    let f6 = memory("Something about Ohio", quote: "um, uh", kind: .fact, at: 6)
    let e1 = memory("Lake feeling", quote: "I felt small by the lake", kind: .feeling, at: 7)
    let e2 = memory("Quiet feeling", quote: "I get quiet when people argue", kind: .feeling, at: 8)
    let e3 = memory("Loose feeling", quote: "I feel lucky", kind: .feeling, at: 9)
    let g1 = memory("Learn the cello", quote: "I want to learn the cello", kind: .goal, at: 10)
    let lake = Entity(type: .place, title: "The lake")
    let alder = Entity(type: .place, title: "Alder Street")
    var idea = Entity(type: .idea, title: "Saying yes to things")

    func source() -> PortraitSource {
        let all = [f1, f2, f3, f4, f5, f6, e1, e2, e3, g1]
        var hiddenMaya = maya; hiddenMaya.hiddenFromTimeline = true
        // f6 has a recording but only filler; f2 has none; e2 has none.
        let withTelling = [f1, f3, f4, f5, f6, e1, e3, g1]
        return makeSource(
            owner: jordan, memories: all,
            links: [f1.id: [link(jordan, .detail)], f3.id: [link(maya, .detail)], f4.id: [link(maya, .mention)], f5.id: [link(jordan, .detail), link(maya, .detail)],
                    e1.id: [link(lake, .detail), link(alder, .mention)], e2.id: [link(jordan, .mention), link(hiddenMaya, .mention)]],
            tags: [f1.id: ["Family"], f2.id: ["school"], f5.id: ["Family", "family"]],
            tellings: Dictionary(uniqueKeysWithValues: withTelling.enumerated().map { ($1.id, told($0)) }),
            ideas: [idea])
    }
}

@Test func factsAboutYouOrNobodyAreWhoYouAre() {
    let w = World()
    #expect(Portrait(w.source(), currentYear: 2026).whoYouAre.map(\.id) == [w.f1, w.f4, w.f5, w.f6, w.f2].map { "memory:\($0.id.rawValue)" })
}

@Test func feelingsAndGoalsShowWhateverTheyAreAbout() {
    let portrait = Portrait(World().source(), currentYear: 2026)
    #expect(portrait.howItFelt.count == 3 && portrait.hopingFor.count == 1)
}

@Test func aFeelingNamesWhatItIsAboutAndNeverGuesses() {
    let portrait = Portrait(World().source(), currentYear: 2026)
    #expect(portrait.howItFelt.map { $0.about?.title } == ["The lake", nil, nil])
    #expect(portrait.whoYouAre.allSatisfy { $0.about == nil }, "only feelings say what they are about")
}

@Test func ownWordsAreQuotedAndTitlesAreNot() {
    let portrait = Portrait(World().source(), currentYear: 2026)
    #expect(portrait.whoYouAre[0].text == "I was always the kid who took things apart" && portrait.whoYouAre[0].isOwnWords)
    #expect(portrait.whatYouThink[0].text == "Saying yes to things" && !portrait.whatYouThink[0].isOwnWords)
}

@Test func aQuoteOfOnlyFillerShowsTheTitleAndNeverLeads() {
    let w = World()
    let portrait = Portrait(w.source(), currentYear: 2026)
    let line = portrait.whoYouAre.first { $0.id == "memory:\(w.f6.id.rawValue)" }!
    #expect(line.text == "Something about Ohio" && !line.isOwnWords && line.telling != nil)
    #expect(!portrait.leadPool.contains { $0.id == line.id })
}

@Test func theLeadPoolHasOwnWordsAndARecordingInPartOrder() {
    let portrait = Portrait(World().source(), currentYear: 2026)
    // f1, f4, f5 (f2 has no recording, f6 no own words), e1, e3 (e2 has no recording), g1; the idea has neither own words nor a pool place
    #expect(portrait.leadPool.map(\.part) == [.whoYouAre, .whoYouAre, .whoYouAre, .howItFelt, .howItFelt, .hopingFor])
}

@Test func theLeadIsPickedAndKept() {
    let portrait = Portrait(World().source(), currentYear: 2026)
    var asked: [Int] = []
    let lead = portrait.lead(keeping: nil) { asked.append($0); return 2 }
    #expect(asked == [portrait.leadPool.count] && lead == portrait.leadPool[2])
    #expect(portrait.lead(keeping: lead?.id) { _ in Issue.record("no pick while the lead is kept"); return 0 } == lead)
    #expect(portrait.lead(keeping: "memory:gone") { _ in 0 } == portrait.leadPool[0])
}

@Test func aLeadWhoseMemoryWasHiddenOrDeletedIsPickedAgain() {
    // The kept line leaves the pool when its memory is hidden or deleted between refreshes: the next portrait no longer has it.
    let w = World()
    let before = Portrait(w.source(), currentYear: 2026)
    let kept = before.lead(keeping: nil) { _ in 0 }
    var hidden = w.f1; hidden.hiddenFromTimeline = true
    var source = w.source(); source.aboutMemories = source.aboutMemories.map { $0.id == hidden.id ? hidden : $0 }
    let after = Portrait(source, currentYear: 2026)
    #expect(!after.leadPool.contains { $0.id == kept?.id })
    #expect(after.lead(keeping: kept?.id) { _ in 0 } == after.leadPool[0])
}

@Test func aHiddenOrUntoldMemoryNeverAppears() {
    let w = World()
    var source = w.source()
    let hidden = memory("Hidden", quote: "keep this away", kind: .fact, at: 20, hidden: true)
    let floating = memory("Floating", quote: "never told", kind: .goal, at: 21, floating: true)
    source.aboutMemories += [hidden, floating]
    let portrait = Portrait(source, currentYear: 2026)
    #expect(!portrait.whoYouAre.contains { $0.id == "memory:\(hidden.id.rawValue)" } && portrait.hopingFor.count == 1)
}

@Test func oneLineLeadsAndItsPartHides() {
    let fact = memory("Took things apart", quote: "I took things apart", kind: .fact, at: 1)
    let one = Portrait(makeSource(memories: [fact], tellings: [fact.id: told(1)]), currentYear: 2026)
    let lead = one.lead(keeping: nil) { _ in 0 }
    #expect(lead != nil && one.lines(.whoYouAre, leaving: lead?.id, tag: nil).isEmpty)
}

@Test func anEmptyPoolPicksNothing() {
    #expect(Portrait(makeSource(), currentYear: 2026).lead(keeping: nil) { _ in Issue.record("no pick"); return 0 } == nil)
    #expect(Portrait(makeSource(), currentYear: 2026).isEmpty)
}

@Test func onlyIdeasIsNotEmptyAndHasNoLead() {
    // An idea is a line in "What you think", so the page is not empty; ideas are never own words, so nothing leads.
    let portrait = Portrait(makeSource(ideas: [Entity(type: .idea, title: "Keeping quiet")]), currentYear: 2026)
    #expect(!portrait.isEmpty && portrait.leadPool.isEmpty)
    #expect(portrait.lead(keeping: nil) { _ in Issue.record("no pick"); return 0 } == nil)
}

@Test func aFactWithNoOwnWordsHasNoQuoteAndNoRecordingNoControl() {
    let fact = memory("Something about Ohio", quote: "", kind: .fact, at: 1)
    let line = Portrait(makeSource(memories: [fact]), currentYear: 2026).whoYouAre[0]
    #expect(line.text == "Something about Ohio" && !line.isOwnWords && line.telling == nil)
}

@Test func theChipsFilterWhoYouAre() {
    let w = World()
    let portrait = Portrait(w.source(), currentYear: 2026)
    #expect(portrait.tags(leaving: nil) == ["Family", "school"])
    #expect(portrait.lines(.whoYouAre, leaving: nil, tag: "family").map(\.id) == [w.f1, w.f5].map { "memory:\($0.id.rawValue)" })
}

@Test func theLeadsTagLeavesTheChips() {
    let w = World()
    let portrait = Portrait(w.source(), currentYear: 2026)
    #expect(portrait.tags(leaving: "memory:\(w.f2.id.rawValue)") == ["Family"])
    #expect(portrait.lines(.whoYouAre, leaving: "memory:\(w.f1.id.rawValue)", tag: nil).count == 4)
}

@Test func aTagThatIsGoneShowsEverything() {
    let portrait = Portrait(World().source(), currentYear: 2026)
    #expect(portrait.lines(.whoYouAre, leaving: nil, tag: "Work") == portrait.whoYouAre)
}

@Test func theHeaderSaysOnlyWhatWasTyped() {
    #expect(Portrait.birthLine(birthYear: 1990, place: "Dayton") == "born 1990 in Dayton")
    #expect(Portrait.birthLine(birthYear: 1990, place: nil) == "born 1990")
    #expect(Portrait.birthLine(birthYear: nil, place: " Dayton ") == "born in Dayton")
    #expect(Portrait.birthLine(birthYear: nil, place: "  ") == nil)
    #expect(Portrait.birthLine(birthYear: nil, place: nil) == nil)
    let blank = Profile(displayName: "  ", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now)
    #expect(Portrait(makeSource(profile: blank), currentYear: 2026).name == nil)
    let typed = Profile(displayName: " Jo ", birthDate: nil, birthPlaceText: " Dayton ", freeText: nil, updatedAt: .now)
    let portrait = Portrait(makeSource(owner: jordan, profile: typed, birth: CivilDate(year: 1990, month: 5, day: 1)), currentYear: 2026)
    #expect(portrait.name == "Jo" && portrait.birthLine == "born 1990 in Dayton")
    #expect(Portrait(makeSource(owner: jordan), currentYear: 2026).name == "Jordan", "the owner's title when no name was typed")
    #expect(Portrait(makeSource(owner: jordan), currentYear: 2026).birthLine == nil, "no date and no place: no line")
}

@Test func theStripIsTheOwnersMoments() {
    let birth = CivilDate(year: 1990, month: 1, day: 1)
    let portrait = Portrait(makeSource(owner: jordan, birth: birth, ownerMoments: [moment(1999, at: 1), moment(2000, at: 2)]), currentYear: 2026)
    #expect(portrait.strip?.sentence == "In 2 moments, from 1999 to 2000")
    #expect(Portrait(makeSource(owner: jordan, birth: birth), currentYear: 2026).strip == nil)
    #expect(Portrait(makeSource(birth: birth, ownerMoments: [moment(1999, at: 1)]), currentYear: 2026).strip == nil, "no owner, no strip")
}

private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

@Test func aGoalSaysWhenItWasSaid() {
    #expect(Portrait.saidWhen(date(2026, 10, 3), now: date(2026, 11, 16), calendar: utc) == "said in October")
    #expect(Portrait.saidWhen(date(2025, 10, 3), now: date(2026, 11, 16), calendar: utc) == "said in October 2025")
}

@Test func saidWhenCrossesTheYearBoundary() {
    let lateDecember = utc.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23))!
    let earlyJanuary = utc.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 30))!
    #expect(Portrait.saidWhen(lateDecember, now: earlyJanuary, calendar: utc) == "said in December 2025")
    #expect(Portrait.saidWhen(earlyJanuary, now: date(2026, 1, 2), calendar: utc) == "said in January")
}

@Test func saidWhenReadsGregorianYearsWhateverCalendarTheDeviceUses() {
    var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = TimeZone(identifier: "UTC")!
    #expect(Portrait.saidWhen(date(2025, 10, 3), now: date(2026, 11, 16), calendar: buddhist) == "said in October 2025")
    #expect(Portrait.saidWhen(date(2026, 10, 3), now: date(2026, 11, 16), calendar: buddhist) == "said in October")
}

@Test func anIdeaIsNeverWhatAFeelingIsAbout() {
    let feeling = memory("Feeling", quote: "I felt brave", kind: .feeling, at: 1)
    let idea = Entity(type: .idea, title: "Saying yes")
    let portrait = Portrait(makeSource(owner: jordan, memories: [feeling], links: [feeling.id: [link(idea, .detail)]]), currentYear: 2026)
    #expect(portrait.howItFelt[0].about == nil)
}

@Test func aFactDetailedOnlyToAnIdeaLeavesYou() {
    // Decision 2: a detail link only to something other than the owner sends the fact to that page, an idea's included.
    let fact = memory("About an idea", quote: "I think about saying yes", kind: .fact, at: 1)
    let idea = Entity(type: .idea, title: "Saying yes")
    #expect(Portrait(makeSource(owner: jordan, memories: [fact], links: [fact.id: [link(idea, .detail)]]), currentYear: 2026).whoYouAre.isEmpty)
}

@Test func oldestToldFirstIgnoresTheOrderTheyArriveIn() {
    // Decision 7: by when it was told, then the span's start, then id. A line with no recording comes after those with one.
    let a = memory("A", quote: "first said", kind: .fact, at: 9), b = memory("B", quote: "second said", kind: .fact, at: 1)
    let c = memory("C", quote: "same day, later in the session", kind: .fact, at: 5), none = memory("N", quote: "no recording", kind: .fact, at: 0)
    let day = date(2026, 9, 1)
    func telling(_ at: Date, _ start: Int) -> Telling { Telling(sessionID: .init(), audioPath: "s.m4a", range: MsRange(start: start, end: start + 500), toldAt: at) }
    let portrait = Portrait(makeSource(memories: [none, c, b, a], tellings: [a.id: telling(day, 0), c.id: telling(day.addingTimeInterval(86_400), 9_000), b.id: telling(day.addingTimeInterval(86_400), 2_000)]), currentYear: 2026)
    #expect(portrait.whoYouAre.map(\.text) == ["First said", "Second said", "Same day, later in the session", "No recording"])
}

@Test func aFactDetailedOnlyToAHiddenPersonFollowsThemAndLeavesYou() {
    // Decision 2, controller's ruling: the person hid that entity; the fact follows it. A detail link to the owner keeps it here.
    let fact = memory("Hidden one's habit", quote: "hums", kind: .fact, at: 1), both = memory("Both", quote: "we ate", kind: .fact, at: 2)
    var hiddenMaya = maya; hiddenMaya.hiddenFromTimeline = true
    let portrait = Portrait(makeSource(owner: jordan, memories: [fact, both], links: [fact.id: [link(hiddenMaya, .detail)], both.id: [link(hiddenMaya, .detail), link(jordan, .detail)]]), currentYear: 2026)
    #expect(portrait.whoYouAre.map(\.text) == ["We ate"])
}

@Test func theOwnerIsNeverWhatAFeelingIsAbout() {
    let feeling = memory("Feeling", quote: "I felt small", kind: .feeling, at: 1)
    let hiddenLake = { var e = Entity(type: .place, title: "Hidden lake"); e.hiddenFromTimeline = true; return e }()
    let lake = Entity(type: .place, title: "The lake")
    let portrait = Portrait(makeSource(owner: jordan, memories: [feeling], links: [feeling.id: [link(jordan, .detail), link(hiddenLake, .detail), link(lake, .mention)]]), currentYear: 2026)
    #expect(portrait.howItFelt[0].about?.title == "The lake", "not the owner, not the hidden place")
}

@Test func aTagOnlyOnAnUnlistedMemoryMakesNoChip() {
    let listed = memory("Listed", quote: "shown", kind: .fact, at: 1), hidden = memory("Hidden", quote: "away", kind: .fact, at: 2, hidden: true)
    let portrait = Portrait(makeSource(memories: [listed, hidden], tags: [listed.id: ["home"], hidden.id: ["secret"]]), currentYear: 2026)
    #expect(portrait.tags(leaving: nil) == ["home"])
}
