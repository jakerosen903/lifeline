import Foundation
import Testing
@testable import LifelineKit

private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }
private let seg = SegmentID()

private func ref(_ title: String, range: TimeRange = .unplaced, id: MemoryID = MemoryID()) -> MemoryRef {
    MemoryRef(id: id, title: title, range: range, primarySpan: MemoryRef.Span(segmentID: seg, startMs: 0, endMs: 1_000))
}
private func anchor(_ memory: MemoryRef, _ phrase: String, _ relation: AnchorRelation, target: String? = nil, value: String? = nil) -> Anchor {
    Anchor(id: .init(), memoryID: memory.id, phrase: phrase, relation: relation, targetKind: .none, targetID: nil,
           targetText: target, value: value, resolved: false)
}
private func input(_ memories: [MemoryRef], _ anchors: [Anchor], birth: String? = "1986-05-10", chapters: [Chapter] = []) -> ResolverInput {
    ResolverInput(memories: memories, anchors: anchors, birthDate: birth.map { d($0) }, chapters: chapters, config: .default)
}

@Test func absoluteYearPlacesStated() {
    let m = ref("Mirror Lake")
    let out = Resolver.resolve(input([m], [anchor(m, "in 2000", .absolute)]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("2000-01-01") && range?.latest == d("2000-12-31") && range?.origin == .stated && range?.evidenceText == "in 2000")
    #expect(out.resolvedAnchorIDs.count == 1 && out.floating.isEmpty && out.curiosity.isEmpty)
}

@Test func ageWithBirthDateGivesOneYearBandInferred() {
    let m = ref("The blue door")
    let out = Resolver.resolve(input([m], [anchor(m, "when I was six", .age)]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("1992-05-10") && range?.latest == d("1993-05-09") && range?.origin == .inferred && range?.evidenceText == "when I was six")
    #expect(range?.granularity == .year)
}

@Test func gradePhraseGivesTheSchoolYear() {
    let m = ref("Mr. Alvarez")
    let out = Resolver.resolve(input([m], [anchor(m, "third grade", .age)]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("1994-09-01") && range?.latest == d("1995-06-30") && range?.origin == .inferred)
}

@Test func twoAgesSpanExactlyThoseYears() {
    let m = ref("Road trip")
    let out = Resolver.resolve(input([m], [anchor(m, "eleven or twelve", .age)]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("1997-05-10") && range?.latest == d("1999-05-09"))
}

@Test func approximateAgeWidensBothWays() {
    let m = ref("Road trip")
    let out = Resolver.resolve(input([m], [anchor(m, "around eleven", .age)]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("1996-05-10") && range?.latest == d("1999-05-09"))
}

@Test func aMemoryNeverTargetsItselfAndEvidenceIsNotATarget() {
    // "The move" was placed last run from "after graduation"; its own evidence must not count as the target now.
    let move = ref("The move", range: TimeRange(earliest: d("2004-01-01"), latest: d("2009-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: .inferred, evidenceText: "after graduation"))
    let out = Resolver.resolve(input([move], [anchor(move, "after graduation", .after, target: "graduation")]))
    // With no graduation memory in sight, the old guess is withdrawn rather than fed back into itself.
    #expect(out.placements[move.id] == .unplaced, "no self-targeting: \(String(describing: out.placements[move.id]))")
    #expect(out.floating.count == 1, "graduation is still an unplaced target")
}

@Test func nonConfirmedRangesAreRecomputedFromScratch() {
    // A stale inferred range with no anchor behind it any more (the birthday was removed) goes back to unplaced.
    let m = ref("The blue door", range: .year(1992, origin: .inferred, evidence: "when I was six"))
    let out = Resolver.resolve(input([m], [anchor(m, "when I was six", .age)], birth: nil))
    #expect(out.placements[m.id] == .unplaced)
}

@Test func relativeRangesAreClampedToTodayAndBirth() {
    let recent = ref("The move", range: .year(2024, origin: .stated, evidence: "in 2024"))
    let after = ref("New job"), before = ref("Before I was born, they say")
    let early = ref("Early", range: .year(1988, origin: .stated, evidence: "in 1988"))
    var inp = input([recent, after, before, early], [anchor(after, "after we moved", .after, target: "The move"), anchor(before, "before that", .before, target: "Early")])
    inp.today = d("2026-10-23")
    let out = Resolver.resolve(inp)
    #expect(out.placements[after.id]?.latest == d("2026-10-23"), "nothing is placed in the future")
    #expect(out.placements[before.id]?.earliest == d("1986-05-10"), "nothing is placed before the owner was born")
}

@Test func curiosityIsOnlyAboutMissingOrUnplacedTargets() {
    let grad = ref("Graduation", range: .year(2004, origin: .stated, evidence: "in 2004"))
    let job = ref("First job", range: .year(1998, origin: .stated, evidence: "in 1998"))
    // "after graduation" contradicts the stated 1998 and stays unresolved, but graduation itself is placed: nothing to ask.
    let out = Resolver.resolve(input([grad, job], [anchor(job, "in 1998", .absolute), anchor(job, "after graduation", .after, target: "Graduation")]))
    #expect(out.curiosity.isEmpty && out.floating.isEmpty)
}

@Test func ageAnchorFloatsWithoutBirthDate() {
    let m = ref("The blue door")
    let out = Resolver.resolve(input([m], [anchor(m, "when I was six", .age)], birth: nil))
    #expect(out.placements.isEmpty && out.floating.isEmpty && out.curiosity.isEmpty && out.resolvedAnchorIDs.isEmpty)
}

@Test func afterAPlacedMemoryWidensByTheSlack() {
    let target = ref("Graduation", range: .year(1998, origin: .stated, evidence: "in 1998"))
    let m = ref("First job")
    let out = Resolver.resolve(input([target, m], [anchor(m, "after I graduated", .after, target: "Graduation")]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("1998-01-01") && range?.latest == d("2003-12-31") && range?.origin == .inferred && range?.evidenceText == "after I graduated")
    #expect(out.placements[target.id] == nil, "an already placed memory is not re-placed")
}

@Test func beforeAMemoryPlacedInTheSameRunChains() {
    let target = ref("Graduation")
    let m = ref("Prom")
    let out = Resolver.resolve(input([target, m], [anchor(target, "in 2004", .absolute), anchor(m, "before graduation", .before, target: "Graduation")]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("1999-01-01") && range?.latest == d("2004-12-31"))
}

@Test func duringAndSameYearCopyTheTarget() {
    let target = ref("The move", range: .year(2011, origin: .stated, evidence: nil))
    let a = ref("Boxes"), b = ref("New school")
    let out = Resolver.resolve(input([target, a, b], [anchor(a, "during the move", .during, target: "the move"), anchor(b, "the same year we moved", .sameYearAs, target: "The move")]))
    #expect(out.placements[a.id]?.earliest == d("2011-01-01") && out.placements[a.id]?.latest == d("2011-12-31"))
    #expect(out.placements[b.id]?.earliest == d("2011-01-01") && out.placements[b.id]?.origin == .inferred)
}

@Test func relativeToAnUnplacedTargetMakesAFloatingTargetAndPayoff() {
    let a = ref("First job"), b = ref("The apartment")
    let out = Resolver.resolve(input([a, b], [anchor(a, "after graduation", .after, target: "graduation"), anchor(b, "right after graduation", .after, target: "graduation")]))
    #expect(out.placements.isEmpty)
    #expect(out.floating.count == 1 && out.floating[0].phrase == "graduation")
    #expect(out.curiosity.count == 1 && out.curiosity[0].kind == .unresolvedAnchor && out.curiosity[0].payoffCount == 2 && out.curiosity[0].targetPhrase == "graduation")
}

@Test func contradictoryAnchorsKeepTheStatedRange() {
    let m = ref("Mixed up")
    let out = Resolver.resolve(input([m], [anchor(m, "in 1998", .absolute), anchor(m, "when I was six", .age)]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("1998-01-01") && range?.latest == d("1998-12-31") && range?.origin == .stated)
    #expect(out.resolvedAnchorIDs.count == 1 && out.curiosity.isEmpty)
}

@Test func twoCompatibleAnchorsIntersect() {
    let m = ref("Narrow")
    let out = Resolver.resolve(input([m], [anchor(m, "the nineties", .absolute), anchor(m, "when I was six", .age)]))
    let range = out.placements[m.id]
    #expect(range?.earliest == d("1992-05-10") && range?.latest == d("1993-05-09"))
}

@Test func cyclicRelativeAnchorsTerminate() {
    let a = ref("A"), b = ref("B")
    let out = Resolver.resolve(input([a, b], [anchor(a, "before B", .before, target: "B"), anchor(b, "before A", .before, target: "A")]))
    #expect(out.placements.isEmpty)
    #expect(out.floating.isEmpty, "both targets exist as memories; nothing new floats")
    #expect(out.curiosity.count == 2)
}

@Test func confirmedRangesAreNeverPlaced() {
    let confirmed = TimeRange.year(2001, origin: .confirmed, evidence: "Before Mirror Lake")
    let m = ref("Carsick", range: confirmed)
    let out = Resolver.resolve(input([m], [anchor(m, "in 1998", .absolute)]))
    #expect(out.placements[m.id] == nil)
}

@Test func chapterTitleIsAValidTarget() {
    let boston = Chapter(id: .init(), title: "The Boston years", range: TimeRange.span(d("2011-01-01"), d("2014-12-31"), granularity: .year, origin: .derived, evidence: nil), order: 0)
    let m = ref("Two winters")
    let out = Resolver.resolve(input([m], [anchor(m, "during the Boston years", .during, target: "the Boston years")], chapters: [boston]))
    #expect(out.placements[m.id]?.earliest == d("2011-01-01") && out.placements[m.id]?.latest == d("2014-12-31"))
}

@Test func fullRunEqualsIncrementalRuns() {
    let grad = ref("Graduation"), job = ref("First job"), apt = ref("The apartment")
    let anchors = [anchor(grad, "in 2004", .absolute), anchor(job, "after graduation", .after, target: "Graduation"), anchor(apt, "after my first job", .after, target: "First job")]
    let full = Resolver.resolve(input([grad, job, apt], anchors))

    var memories: [MemoryRef] = []
    var placed: [MemoryID: TimeRange] = [:]
    for next in [grad, job, apt] {
        memories.append(next)
        let current = memories.map { m in placed[m.id].map { MemoryRef(id: m.id, title: m.title, range: $0, primarySpan: m.primarySpan) } ?? m }
        let step = Resolver.resolve(input(current, anchors.filter { a in current.contains { $0.id == a.memoryID } }))
        placed.merge(step.placements) { _, new in new }
    }
    #expect(placed == full.placements)
    #expect(full.placements[apt.id]?.latest == d("2014-12-31"))
}

@Test func aRelativeAnchorWhosePhraseIsASchoolYearFallsBackToAge() {
    // The extractor says "freshman year" is `during` "college at Duke". Until that chapter has a range,
    // the phrase itself still says how old the owner was.
    let dorm = ref("Moving into my dorm")
    let out = Resolver.resolve(input([dorm], [anchor(dorm, "freshman year", .during, target: "college at Duke")]))
    let range = out.placements[dorm.id]
    #expect(range?.earliest == d("2000-09-01") && range?.latest == d("2001-06-30") && range?.origin == .inferred, "\(String(describing: range))")
    #expect(out.floating.isEmpty, "the phrase settled the memory, so nothing is asked")
}
