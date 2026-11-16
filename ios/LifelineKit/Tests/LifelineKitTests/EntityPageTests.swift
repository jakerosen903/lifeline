import Foundation
import Testing
@testable import LifelineKit

private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }
private func range(_ a: Int, _ b: Int, _ origin: RangeOrigin) -> TimeRange {
    TimeRange(earliest: d("\(a)-01-01"), latest: d("\(b)-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: origin, evidenceText: nil)
}

@Test func spanTextSaysWhatIsKnown() {
    #expect(EntityPage.spanText(.unplaced) == "no dates yet")
    #expect(EntityPage.spanText(range(1993, 1998, .stated)) == "from 1993 to 1998")
    #expect(EntityPage.spanText(range(1993, 1998, .inferred)) == "between 1993 and 1998", "a guess never reads as fact")
    #expect(EntityPage.spanText(range(1993, 1998, .derived)) == "between 1993 and 1998")
    #expect(EntityPage.spanText(range(1998, 1998, .inferred)) == "around 1998")
    #expect(EntityPage.spanText(range(1998, 1998, .stated)) == "in 1998")
    // A hedge or a relation the person settled still reads as a guess.
    #expect(EntityPage.spanText(.stated(around: 1998)) == "around 1998")
    #expect(EntityPage.spanText(.span(d("1996-01-01"), d("2004-12-31"), granularity: .year, origin: .confirmed, evidence: "before Graduation (2004)")) == "between 1996 and 2004")
}

@Test func anIdeasMomentsOrderByDate() {
    func memory(_ title: String, _ r: TimeRange = .unplaced, created: TimeInterval) -> Memory {
        Memory(id: .init(), title: title, summaryQuote: title, visibility: .timeline, chapterID: nil, createdFromCandidateID: CandidateID(),
               createdAt: Date(timeIntervalSince1970: created), range: r)
    }
    let now = memory("Now I think rest matters", created: 2_000_000_000)              // undated, told in 2033
    let then = memory("I used to think work was everything", range(1995, 1995, .inferred), created: 2_000_000_100)
    let middle = memory("The burnout year", range(2010, 2010, .stated), created: 1_999_000_000)
    let ordered = EntityPage.ordered([now, middle, then], toldAt: [now.id: Date(timeIntervalSince1970: 2_000_000_000)])
    #expect(ordered.map(\.title) == ["I used to think work was everything", "The burnout year", "Now I think rest matters"])
}

// S2, Task 3: readable sections and copy.

private func said(_ year: Int) -> TimeRange { .year(year, origin: .stated, evidence: nil) }

private func page(_ title: String, kind: MemoryKind = .event, year: Int? = nil, hidden: Bool = false, floating: Bool = false, told: Int) -> Memory {
    Memory(id: .init(), title: title, summaryQuote: title, visibility: .timeline, chapterID: nil,
           createdFromCandidateID: floating ? nil : CandidateID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(told) * 60),
           range: year.map(said) ?? .unplaced, hiddenFromTimeline: hidden, kind: kind)
}

@Test func thePageSplitsWhatWasSaidFromMoments() {
    let d1 = page("Has a blue door", kind: .fact, told: 1)
    let m2 = page("Picnic", year: 2001, told: 2)
    let m1 = page("Move", year: 1999, told: 3)
    let f1 = page("Always early", kind: .fact, told: 4)
    let h1 = page("Hidden", hidden: true, told: 5)
    let s1 = page("Floating", floating: true, told: 6)
    let m3 = page("Undated trip", told: 7)
    let sections = EntityPage.sections(details: [d1], mentions: [m2, m1, f1, h1, s1, m3])
    #expect(sections.said.map(\.id) == [d1.id, f1.id])
    #expect(sections.moments.map(\.id) == [m1.id, m2.id, m3.id])
}

@Test func whatIsSaidIsDistinctOldestFirstAndNeverHidden() {
    let fact = page("Likes tea", kind: .fact, told: 2)
    let older = page("Lives by the sea", kind: .fact, told: 1)
    let hiddenDetail = page("Hidden detail", kind: .fact, hidden: true, told: 3)
    let floatingDetail = page("Floating detail", kind: .fact, floating: true, told: 4)
    // A fact linked as both a detail and a mention shows once.
    let sections = EntityPage.sections(details: [fact, hiddenDetail, floatingDetail], mentions: [fact, older])
    #expect(sections.said.map(\.id) == [older.id, fact.id])
    #expect(sections.moments.isEmpty)
}

@Test func thePageCountsWhatTheGridCounts() throws {
    let db = try AppDatabase.inMemory()
    let store = ExtractionStore(db)
    let (_, segments) = try StoreFixtures.session(in: store.sessions, segments: (1...6).map { "we were at the house, time \($0)" })
    let maya = try store.people.insertPerson(displayName: "Maya")
    let mayaEntity = try #require(try store.entities.entity(id: maya.entityID))
    func memory(_ n: Int, kind: MemoryKind = .event, year: Int? = nil, hidden: Bool = false) throws -> Memory {
        let made = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[n].id, title: "Memory \(n)",
                                            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 60))
        if kind != .event { try store.memories.setKind(made.id, kind) }
        if let year { try store.memories.updateRange(made.id, said(year)) }
        if hidden { try store.memories.setHidden(made.id, true) }
        try store.entities.link(made.id, mayaEntity.id, relation: .mention, roleText: nil)
        return made
    }
    _ = try memory(0, year: 1999)
    _ = try memory(1, year: 2001)
    _ = try memory(2, kind: .fact)
    _ = try memory(3, hidden: true)
    _ = try memory(4)
    // A floating stand-in linked by mention is not told: neither the page nor the grid counts it.
    let floating = try memory(5)
    try db.writer.write { try $0.execute(sql: "update memory set created_from_candidate_id = null where id = ?", arguments: [floating.id.rawValue]) }
    let sections = EntityPage.sections(details: try store.entities.details(of: mayaEntity.id), mentions: try store.entities.moments(of: mayaEntity.id))
    let summary = try #require(try store.entities.summaries(type: .person).first { $0.id == mayaEntity.id })
    #expect(sections.moments.count == 3)
    #expect(sections.moments.count == summary.momentCount)
    #expect(sections.said.count == 1)
}

@Test func headingsNeverGuessAGender() {
    #expect(EntityPage.saidHeading(.person, isOwner: false) == "What you've said about them")
    #expect(EntityPage.saidHeading(.place, isOwner: false) == "What you've said about it")
    #expect(EntityPage.saidHeading(.thing, isOwner: false) == "What you've said about it")
    #expect(EntityPage.saidHeading(.person, isOwner: true) == "What you've said about yourself")
    #expect(EntityPage.momentsHeading(title: "Sam", isOwner: false) == "Moments with Sam")
    #expect(EntityPage.momentsHeading(title: "Jordan", isOwner: true) == "Your moments")
    #expect(EntityPage.invitation(title: "Lena", isOwner: false) == "Stories you tell about Lena will show here.")
    #expect(EntityPage.invitation(title: "Jordan", isOwner: true) == "Stories you tell about yourself will show here.")
}

// Final review: a quote made only of fillers never shows an empty row.

@Test func aQuoteOfOnlyFillersHasNoOwnWordsSoCallersShowTheTitleUnquoted() {
    let fillers = page("Rainy afternoons", kind: .fact, told: 1)
    var onlyFillers = fillers
    onlyFillers.summaryQuote = "um, uh"
    #expect(EntityPage.ownWordsQuote(of: onlyFillers) == nil)
    #expect(EntityPage.readableQuote(of: onlyFillers) == "Rainy afternoons")
    var spoken = fillers
    spoken.summaryQuote = "um, it rained, you know, every day"
    #expect(EntityPage.ownWordsQuote(of: spoken) == "It rained, every day")
    #expect(EntityPage.readableQuote(of: spoken) == "It rained, every day")
    #expect(EntityPage.ownWordsQuote(of: spoken, maxWords: 2) == "It rained…")
    #expect(EntityPage.readableQuote(of: spoken, maxWords: 2) == "It rained…")
}

@Test func aHedgedMemberMakesTheDerivedSpanAGuess() {
    #expect(EntityRepository.derivedSpan(over: [said(1999), said(2003)]).origin == .stated)
    #expect(EntityRepository.derivedSpan(over: [said(1999), .stated(around: 2003)]).origin == .inferred)
    let before = TimeRange.span(d("1996-01-01"), d("2004-12-31"), granularity: .year, origin: .confirmed, evidence: "before Graduation (2004)")
    #expect(EntityRepository.derivedSpan(over: [said(1999), before]).origin == .inferred)
}
