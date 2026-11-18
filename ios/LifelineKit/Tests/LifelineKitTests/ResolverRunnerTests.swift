import Foundation
import Testing
@testable import LifelineKit

private struct Env {
    let store: ExtractionStore, actions: CandidateActions, runner: ResolverRunner, session: SessionID, segment: Segment, words: [Word]
    init(text: String = "we moved the summer after graduation and I was six when the blue door was painted") throws {
        let db = try AppDatabase.inMemory()
        store = ExtractionStore(db)
        actions = CandidateActions(store: store)
        runner = ResolverRunner(store: store)
        (session, _) = try StoreFixtures.session(in: store.sessions, segments: [text])
        segment = try store.sessions.segments(in: session)[0]
        words = try store.sessions.words(in: segment.id)
    }
    func birthday(_ iso: String) throws {
        let date = CivilDate(iso: iso)!
        var parts = DateComponents(); parts.year = date.year; parts.month = date.month; parts.day = date.day; parts.hour = 12
        try store.profile.save(Profile(displayName: "Jake", birthDate: Calendar.current.date(from: parts), birthPlaceText: nil, freeText: nil, updatedAt: .now))
    }
    @discardableResult
    func accept(_ title: String, anchors: [AnchorOut], ordinal: Int) throws -> Memory {
        let out = MemoryOut(ref: "m", kind: .event, title: title, quote: "the blue door", segmentSpan: WordSpan(startWord: 0, endWord: 2), peopleRefs: [],
                            placeText: nil, anchors: anchors, collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segment.id, ordinal: ordinal, kind: .memory, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        return try actions.acceptMemory(c).memory
    }
}

@Test func acceptingAMemoryWithAnAgeAnchorPlacesItWhenTheBirthdayIsKnown() throws {
    let env = try Env()
    try env.birthday("1986-05-10")
    let memory = try env.accept("The blue door", anchors: [AnchorOut(phrase: "I was six", relation: .age, targetText: nil, value: nil)], ordinal: 0)
    let stored = try #require(try env.store.memories.fetch(memory.id))
    #expect(stored.range.earliest?.iso == "1992-05-10" && stored.range.origin == .inferred)
    #expect(try env.store.memories.anchors(of: memory.id).allSatisfy(\.resolved))
}

@Test func addingABirthDateRunsTheResolverAndPlacesAgeMemories() throws {
    let env = try Env()
    let memory = try env.accept("The blue door", anchors: [AnchorOut(phrase: "I was six", relation: .age, targetText: nil, value: nil)], ordinal: 0)
    #expect(try env.store.memories.fetch(memory.id)?.range == .unplaced)
    try env.birthday("1986-05-10")
    let report = try env.runner.run()
    #expect(report.placed == 1)
    #expect(try env.store.memories.fetch(memory.id)?.range.earliest?.iso == "1992-05-10")
}

@Test func secondRunWritesNothing() throws {
    let env = try Env()
    try env.birthday("1986-05-10")
    try env.accept("The blue door", anchors: [AnchorOut(phrase: "I was six", relation: .age, targetText: nil, value: nil)], ordinal: 0)
    let again = try env.runner.run()
    #expect(again.placed == 0 && again.floatingCreated == 0 && again.changes.isEmpty)
}

@Test func floatingTargetBecomesAMemoryOnce() throws {
    let env = try Env()
    try env.accept("The move", anchors: [AnchorOut(phrase: "the summer after graduation", relation: .after, targetText: "graduation", value: nil)], ordinal: 0)
    try env.accept("First job", anchors: [AnchorOut(phrase: "after graduation", relation: .after, targetText: "graduation", value: nil)], ordinal: 1)
    let floating = try env.store.memories.allMemories().filter(\.isFloating)
    #expect(floating.count == 1 && floating[0].title == "graduation")
    let open = try env.store.curiosity.open()
    #expect(open.count == 1 && open[0].text == "graduation" && open[0].payoffCount == 2 && open[0].targetMemoryID == floating[0].id)
    let anchors = try env.store.memories.allAnchors().filter { $0.targetText == "graduation" }
    #expect(anchors.allSatisfy { $0.targetKind == .memory && $0.targetID == floating[0].id.rawValue })
    // Tell the graduation story: the floating memory gets a range, the two place, the question closes.
    try env.store.memories.updateRange(floating[0].id, .year(2004, origin: .stated, evidence: "in 2004"))
    let report = try env.runner.run()
    #expect(report.placed == 2 && report.curiosityOpen == 0)
    #expect(try env.store.memories.fetch(try #require(try env.store.memories.allMemories().first { $0.title == "First job" }?.id))?.range.latest?.iso == "2009-12-31")
}

@Test func confirmedRangeIsLeftAlone() throws {
    let env = try Env()
    try env.birthday("1986-05-10")
    let memory = try env.accept("The blue door", anchors: [AnchorOut(phrase: "I was six", relation: .age, targetText: nil, value: nil)], ordinal: 0)
    let confirmed = TimeRange.year(2001, origin: .confirmed, evidence: "Before Mirror Lake")
    try env.store.memories.updateRange(memory.id, confirmed)
    _ = try env.runner.run()
    #expect(try env.store.memories.fetch(memory.id)?.range == confirmed)
}

@Test func repeatedRunsAfterARelativePlacementChangeNothing() throws {
    let env = try Env(text: "we moved after graduation and graduation was in 2004 and one more thing")
    let move = try env.accept("The move", anchors: [AnchorOut(phrase: "after graduation", relation: .after, targetText: "graduation", value: nil)], ordinal: 0)
    try env.accept("Graduation", anchors: [AnchorOut(phrase: "in 2004", relation: .absolute, targetText: nil, value: nil)], ordinal: 1)
    let placed = try env.store.memories.fetch(move.id)?.range
    #expect(placed?.latest?.iso == "2009-12-31")
    try env.accept("One more thing", anchors: [], ordinal: 2)
    for _ in 0..<3 { _ = try env.runner.run() }
    #expect(try env.store.memories.fetch(move.id)?.range == placed, "a range never widens on a re-run")
}

@Test func removingTheBirthdayUnplacesAgeMemories() throws {
    let env = try Env()
    try env.birthday("1986-05-10")
    let memory = try env.accept("The blue door", anchors: [AnchorOut(phrase: "I was six", relation: .age, targetText: nil, value: nil)], ordinal: 0)
    #expect(try env.store.memories.fetch(memory.id)?.range.isPlaced == true)
    try env.store.profile.save(Profile(displayName: "Jake", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    _ = try env.runner.run()
    #expect(try env.store.memories.fetch(memory.id)?.range == .unplaced, "a guess that lost its basis is withdrawn")
}

@Test func confirmingAMemoryKeepsItsAnchorsResolvedAndAsksNothing() throws {
    let env = try Env(text: "after graduation I started work and graduation was in 2004")
    let job = try env.accept("First job", anchors: [AnchorOut(phrase: "after graduation", relation: .after, targetText: "graduation", value: nil)], ordinal: 0)
    try env.accept("Graduation", anchors: [AnchorOut(phrase: "in 2004", relation: .absolute, targetText: nil, value: nil)], ordinal: 1)
    #expect(try env.store.memories.anchors(of: job.id).allSatisfy(\.resolved))
    try env.store.memories.updateRange(job.id, .year(2005, origin: .confirmed, evidence: "after Graduation (2004)"))
    _ = try env.runner.run()
    #expect(try env.store.memories.anchors(of: job.id).allSatisfy(\.resolved), "confirming does not un-resolve")
    #expect(try env.store.curiosity.open().isEmpty, "no question about a story already told")
}

@Test func aChapterRangeDoesNotFollowItsMembers() throws {
    let env = try Env()
    let memory = try env.accept("The blue door", anchors: [AnchorOut(phrase: "I was six", relation: .age, targetText: nil, value: nil)], ordinal: 0)
    let chapter = try env.actions.createChapter(title: "Childhood", containing: memory.id)
    #expect(try env.store.chapters.chapter(id: chapter.id)?.range == .unplaced)
    try env.birthday("1986-05-10")
    _ = try env.runner.run()
    #expect(try env.store.memories.fetch(memory.id)?.range.earliest?.iso == "1992-05-10", "the member is placed")
    #expect(try env.store.chapters.chapter(id: chapter.id)?.range == .unplaced, "the chapter does not follow its member: its range holds stated years only")
}

@Test func floatingTargetIsReplacedWhenTheRealMemoryArrives() throws {
    let env = try Env(text: "we moved after graduation and graduation was in 2004")
    let move = try env.accept("The move", anchors: [AnchorOut(phrase: "after graduation", relation: .after, targetText: "graduation", value: nil)], ordinal: 0)
    #expect(try env.store.memories.allMemories().filter(\.isFloating).count == 1)
    let graduation = try env.accept("Graduation", anchors: [AnchorOut(phrase: "in 2004", relation: .absolute, targetText: nil, value: nil)], ordinal: 1)
    #expect(try env.store.memories.allMemories().filter(\.isFloating).isEmpty, "the placeholder gives way to the real memory")
    let anchor = try #require(try env.store.memories.anchors(of: move.id).first)
    #expect(anchor.targetID == graduation.id.rawValue && anchor.resolved)
    #expect(try env.store.memories.fetch(move.id)?.range.earliest?.iso == "2004-01-01")
    #expect(try env.store.memories.fetch(move.id)?.range.latest?.iso == "2009-12-31")
    #expect(try env.store.curiosity.open().isEmpty)
}

@Test func statedRangeKeepsItsAnchorFlagsAcrossRuns() throws {
    let env = try Env()
    try env.birthday("1986-05-10")
    let memory = try env.accept("The blue door", anchors: [AnchorOut(phrase: "I was six", relation: .age, targetText: nil, value: nil)], ordinal: 0)
    #expect(try env.store.memories.anchors(of: memory.id).first?.resolved == true)
    let actions = CandidateActions(store: env.store)
    try actions.setStatedRange(memory.id, .stated(year: 1998))
    _ = try env.runner.run()
    #expect(try env.store.memories.fetch(memory.id)?.range == .stated(year: 1998))
    #expect(try env.store.memories.anchors(of: memory.id).first?.resolved == true, "a stated memory keeps its anchor flags, like a confirmed one")
}

// A chapter anchors a "during" phrase by its stated years, else by the span of its moments.
// The span is read for the run and never stored on the chapter.

private func duringBoston(_ env: Env, members: [(String, Int)]) throws -> (chapter: Chapter, later: Memory) {
    let chapter = try env.store.chapters.insertChapter(title: "The Boston years")
    for (i, member) in members.enumerated() {
        let memory = try env.accept(member.0, anchors: [], ordinal: i)
        try env.store.memories.updateRange(memory.id, .year(member.1, origin: .stated, evidence: "in \(member.1)"))
        try env.store.chapters.assign(memory: memory.id, toChapter: chapter.id)
    }
    let later = try env.accept("The snow day", anchors: [AnchorOut(phrase: "during the Boston years", relation: .during, targetText: "The Boston years", value: nil)], ordinal: members.count)
    return (chapter, later)
}

@Test func aChapterWithNoStatedYearsAnchorsFromItsMembers() throws {
    let env = try Env()
    let (chapter, later) = try duringBoston(env, members: [("The first flat", 2008), ("The last flat", 2012)])
    try env.runner.run()
    let range = try #require(try env.store.memories.fetch(later.id)?.range)
    #expect(range.isPlaced && range.earliest!.iso >= "2008-01-01" && range.latest!.iso <= "2012-12-31")
    #expect(try env.store.chapters.chapter(id: chapter.id)?.range == .unplaced, "the member span is never stored on the chapter")
}

@Test func aChapterWithStatedYearsAnchorsFromThem() throws {
    let env = try Env()
    let (chapter, later) = try duringBoston(env, members: [("The first flat", 2008), ("The last flat", 2012)])
    try env.store.chapters.setRange(chapter.id, TimeRange(earliest: CivilDate(iso: "1995-01-01"), latest: CivilDate(iso: "1996-12-31"), likelyStart: nil, likelyEnd: nil,
                                                         granularity: .year, origin: .stated, evidenceText: "1995 to 1996"))
    try env.runner.run()
    let range = try #require(try env.store.memories.fetch(later.id)?.range)
    #expect(range.isPlaced && range.earliest!.iso >= "1995-01-01" && range.latest!.iso <= "1996-12-31")
}

@Test func aFactMemberDoesNotCountInTheAnchorRange() throws {
    let env = try Env()
    let (chapter, later) = try duringBoston(env, members: [("The first flat", 2008), ("The last flat", 2012), ("Born in Ohio", 1970)])
    let fact = try #require(try env.store.memories.allMemories().first { $0.title == "Born in Ohio" })
    try env.store.memories.setKind(fact.id, .fact)
    #expect(try env.store.memories.moments(inChapter: chapter.id).count == 2, "the fact is a member but not a moment")
    try env.runner.run()
    let range = try #require(try env.store.memories.fetch(later.id)?.range)
    #expect(range.isPlaced && range.earliest!.iso >= "2008-01-01", "the 1970 fact does not widen the span")
}

// MARK: - A date from a photo (photo story)

private let photoDay = CivilDate(iso: "2019-07-14")!

@Test func aPhotoOriginSurvivesTheDatabase() throws {
    let env = try Env()
    let memory = try env.accept("The blue door", anchors: [], ordinal: 0)
    try env.store.memories.updateRange(memory.id, .fromPhoto(photoDay))
    let stored = try #require(try env.store.memories.fetch(memory.id))
    #expect(stored.range.origin == .photo)
    #expect(stored.range == .fromPhoto(photoDay))
}

@Test func theResolverLeavesAPhotoDateAlone() throws {
    let env = try Env(text: "the blue door was painted in 1998 and one more thing")
    let memory = try env.accept("The blue door", anchors: [AnchorOut(phrase: "in 1998", relation: .absolute, targetText: nil, value: nil)], ordinal: 0)
    #expect(try env.store.memories.fetch(memory.id)?.range.earliest?.year == 1998, "the anchor would place it in 1998")
    let reader = PhotoStoryReader(store: env.store)
    // The card reads the store, so its offer carries the range the resolver set, not the one `accept` returned.
    let onCard = try #require(try env.store.memories.fetch(memory.id))
    try reader.useDate(PhotoStoryCard.DateOffer(memory: onCard, date: photoDay))
    #expect(try env.store.memories.fetch(memory.id)?.range == .fromPhoto(photoDay))
    try env.accept("One more thing", anchors: [], ordinal: 1)
    _ = try env.runner.run()
    #expect(try env.store.memories.fetch(memory.id)?.range == .fromPhoto(photoDay), "more sorting does not move a tapped date")
}

@Test func noWhenQuestionTargetsAMemoryDatedFromAPhoto() throws {
    let env = try Env(text: "after graduation I started work and graduation was in 2004")
    let job = try env.accept("First job", anchors: [AnchorOut(phrase: "after graduation", relation: .after, targetText: "graduation", value: nil)], ordinal: 0)
    try env.accept("Graduation", anchors: [AnchorOut(phrase: "in 2004", relation: .absolute, targetText: nil, value: nil)], ordinal: 1)
    try env.store.memories.updateRange(job.id, .fromPhoto(CivilDate(iso: "2005-03-02")!))
    _ = try env.runner.run()
    #expect(try env.store.memories.anchors(of: job.id).allSatisfy(\.resolved), "a photo date does not un-resolve")
    #expect(try env.store.curiosity.open().isEmpty, "no question about a memory dated from a photo")
}
