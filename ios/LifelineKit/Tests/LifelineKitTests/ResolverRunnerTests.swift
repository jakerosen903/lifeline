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
                            placeText: nil, anchors: anchors, sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
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
