import Foundation
import Testing
@testable import LifelineKit

private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }
private let seg = SegmentID()
private func ref(_ title: String, range: TimeRange = .unplaced) -> MemoryRef {
    MemoryRef(id: .init(), title: title, range: range, primarySpan: MemoryRef.Span(segmentID: seg, startMs: 0, endMs: 1_000))
}
private func anchor(_ memory: MemoryRef, _ phrase: String, _ relation: AnchorRelation, target: String? = nil, targetID: MemoryID? = nil) -> Anchor {
    Anchor(id: .init(), memoryID: memory.id, phrase: phrase, relation: relation, targetKind: targetID == nil ? .none : .memory,
           targetID: targetID?.rawValue, targetText: target, value: nil, resolved: false)
}

@Test func beforeOrAfterAPlacedTarget() throws {
    let lake = ref("Dad fell in at Mirror Lake", range: .year(2000, origin: .stated, evidence: "in 2000"))
    let carsick = ref("The carsick trip", range: TimeRange.span(d("1996-01-01"), d("2001-12-31"), granularity: .year, origin: .inferred, evidence: "one of those summers"))
    let a = anchor(carsick, "the same trip, I think", .during, target: "Mirror Lake", targetID: lake.id)
    let q = try #require(RelativeQuestions.question(for: carsick, anchors: [a], placed: [lake], siblings: [], birthDate: nil, config: .default))
    #expect(q.prompt == "Was this before or after Dad fell in at Mirror Lake?")
    #expect(q.choices.map(\.label) == ["Before (2000)", "After (2000)"])
    #expect(q.choices[0].resultingRange.earliest == d("1996-01-01") && q.choices[0].resultingRange.latest == d("2000-12-31"))
    #expect(q.choices[1].resultingRange.earliest == d("2000-01-01") && q.choices[1].resultingRange.latest == d("2001-12-31"))
}

@Test func relativeAnchorWithoutARangeUsesTheSlack() throws {
    let lake = ref("Dad fell in at Mirror Lake", range: .year(2000, origin: .stated, evidence: "in 2000"))
    let bear = ref("The bear at the campsite")
    let a = anchor(bear, "around the time Dad fell in", .during, target: "Mirror Lake", targetID: lake.id)
    let q = try #require(RelativeQuestions.question(for: bear, anchors: [a], placed: [lake], siblings: [], birthDate: nil, config: .default))
    #expect(q.choices[0].resultingRange.earliest == d("1995-01-01") && q.choices[0].resultingRange.latest == d("2000-12-31"))
    #expect(q.choices[1].resultingRange.earliest == d("2000-01-01") && q.choices[1].resultingRange.latest == d("2005-12-31"))
}

@Test func sameYearAsASiblingInTheCollection() throws {
    let wagon = ref("The green station wagon", range: .year(1998, origin: .stated, evidence: "in 1998"))
    let bear = ref("The bear at the campsite", range: TimeRange.span(d("1996-01-01"), d("2001-12-31"), granularity: .year, origin: .inferred, evidence: "one of those summers"))
    let q = try #require(RelativeQuestions.question(for: bear, anchors: [], placed: [wagon], siblings: [wagon], birthDate: nil, config: .default))
    #expect(q.prompt == "Was this the same year as The green station wagon?")
    #expect(q.choices.map(\.label) == ["Yes (1998)", "No"])
    #expect(q.choices[0].resultingRange.earliest == d("1998-01-01") && q.choices[0].resultingRange.latest == d("1998-12-31"))
    // "No" keeps the larger side of the band without 1998: 1999–2001 (3 years) beats 1996–1997 (2 years).
    #expect(q.choices[1].resultingRange.earliest == d("1999-01-01") && q.choices[1].resultingRange.latest == d("2001-12-31"))
}

@Test func noQuestionWhenNothingTheOwnerSaidCanNarrowIt() {
    let lonely = ref("Sunday pancakes")
    #expect(RelativeQuestions.question(for: lonely, anchors: [], placed: [], siblings: [], birthDate: d("1986-05-10"), config: .default) == nil,
            "a birthday alone would make a date question, which is not allowed")
    let narrow = ref("Graduation", range: .year(2004, origin: .stated, evidence: "in 2004"))
    #expect(RelativeQuestions.question(for: narrow, anchors: [], placed: [narrow], siblings: [narrow], birthDate: nil, config: .default) == nil)
}

@Test func applyingAChoiceConfirmsTheRange() throws {
    let lake = ref("Dad fell in at Mirror Lake", range: .year(2000, origin: .stated, evidence: "in 2000"))
    let bear = ref("The bear at the campsite")
    let a = anchor(bear, "around then", .during, target: "Mirror Lake", targetID: lake.id)
    let q = try #require(RelativeQuestions.question(for: bear, anchors: [a], placed: [lake], siblings: [], birthDate: nil, config: .default))
    let range = RelativeQuestions.apply(q.choices[0], to: bear)
    #expect(range.origin == .confirmed && range.evidenceText == "Before (2000)" && range.earliest == q.choices[0].resultingRange.earliest)
}

@Test func confirmedRangeSurvivesATargetChange() throws {
    let lake = ref("Dad fell in at Mirror Lake", range: .year(2000, origin: .stated, evidence: "in 2000"))
    var bear = ref("The bear at the campsite")
    let a = anchor(bear, "around then", .during, target: "Mirror Lake", targetID: lake.id)
    let q = try #require(RelativeQuestions.question(for: bear, anchors: [a], placed: [lake], siblings: [], birthDate: nil, config: .default))
    bear.range = RelativeQuestions.apply(q.choices[0], to: bear)
    // The target later moves to 2003; the resolver must leave the confirmed range alone.
    let movedLake = MemoryRef(id: lake.id, title: lake.title, range: .year(2003, origin: .confirmed, evidence: "After the wedding"), primarySpan: lake.primarySpan)
    let out = Resolver.resolve(ResolverInput(memories: [movedLake, bear], anchors: [a], birthDate: nil, chapters: []))
    #expect(out.placements[bear.id] == nil)
    #expect(RelativeQuestions.question(for: bear, anchors: [a], placed: [movedLake], siblings: [], birthDate: nil, config: .default) == nil,
            "a confirmed memory is not asked again")
}
