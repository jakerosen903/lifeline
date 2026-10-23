import Foundation
import Testing
@testable import LifelineKit

/// "Same story" on a card, merging one memory into another, and undo (M4.1).
private struct Env {
    let store: ExtractionStore, actions: CandidateActions
    init() throws {
        store = ExtractionStore(try AppDatabase.inMemory())
        actions = CandidateActions(store: store)
    }

    /// One session, one segment, one pending memory card with the given extras.
    func card(_ text: String, title: String, people: [String] = [], place: String? = nil, anchors: [AnchorOut] = [],
              collection: String? = nil) throws -> (SessionID, Segment, Candidate) {
        let (session, segs) = try StoreFixtures.session(in: store.sessions, segments: [text])
        let words = text.split(separator: " ").count
        let out = MemoryOut(ref: "m1", kind: .event, title: title, quote: text, segmentSpan: WordSpan(startWord: 0, endWord: words - 1),
                            peopleRefs: people, placeText: place, anchors: anchors, collectionHint: collection, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(segs[0].id, payload: try CandidatePayload.encode(out))
        try store.candidates.insert(c)
        try store.sessions.setStatus(.extracted, for: segs[0].id)
        return (session, segs[0], c)
    }

    func kept(_ text: String, title: String, people: [String] = [], collection: String? = nil) throws -> (SessionID, Memory) {
        let (session, _, c) = try card(text, title: title, people: people)
        let memory = try actions.acceptMemory(c).memory
        if let collection { _ = try actions.addToCollection(memory.id, titled: collection) }
        return (session, memory)
    }
}

@Test func sameStoryAddsASpanAndNoMemory() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, segment, c) = try env.card("grew up in an orange house with Maya", title: "Grew up in an orange house", people: ["Maya"], place: "Florida")
    let before = try env.store.memories.allMemories().count
    #expect(throws: CandidateActions.Error.targetMissing) { try env.actions.mergeCandidate(c, into: MemoryID(rawValue: "nope")) }
    let result = try env.actions.mergeCandidate(c, into: target.id)
    let spans = try env.store.memories.spans(of: target.id)
    #expect(spans.count == 2 && spans[1].order == 1 && spans[1].segmentID == segment.id)
    #expect(spans[1].titleText == "Grew up in an orange house" && spans[1].candidateID == c.id)
    #expect(try env.store.memories.allMemories().count == before, "no new memory row")
    #expect(try env.store.candidates.fetch(c.id)?.status == .accepted)
    #expect(result.newMentions.map(\.text) == ["Maya"])
    #expect(try env.store.memories.places(of: target.id).map(\.nameText) == ["Florida"])
    #expect(result.receipt.target == target.id && result.receipt.candidateID == c.id && result.receipt.before.count == 1)
    #expect(throws: CandidateActions.Error.notPending) { try env.actions.mergeCandidate(c, into: target.id) }
}

@Test func sameStoryIntoAStandInMakesItReal() throws {
    let env = try Env()
    let (_, namer) = try env.kept("the summer before graduation we drove", title: "The drive")
    let namerSpan = try #require(try env.store.memories.spans(of: namer.id).first)
    let standIn = try env.store.memories.insertFloating(title: "graduation", segment: namerSpan.segmentID, startMs: namerSpan.startMs, endMs: namerSpan.endMs)
    #expect(standIn.isFloating)
    let (_, segment, c) = try env.card("graduation day was hot and loud", title: "Graduation day")
    _ = try env.actions.mergeCandidate(c, into: standIn.id)
    let real = try #require(try env.store.memories.fetch(standIn.id))
    #expect(!real.isFloating && real.createdFromCandidateID == c.id && real.title == "Graduation day" && real.summaryQuote == "graduation day was hot and loud")
    let spans = try env.store.memories.spans(of: standIn.id)
    #expect(spans.count == 1 && spans[0].order == 0 && spans[0].segmentID == segment.id && spans[0].candidateID == c.id)
}

@Test func sameStoryCarriesAnchorsAndRunsTheResolver() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    #expect(try env.store.memories.fetch(target.id)?.range.isPlaced == false)
    let (_, _, c) = try env.card("that was in 1998 in the orange house", title: "The orange house in 1998",
                                 anchors: [AnchorOut(phrase: "in 1998", relation: .absolute, targetText: nil, value: "1998")])
    _ = try env.actions.mergeCandidate(c, into: target.id)
    #expect(try env.store.memories.anchors(of: target.id).map(\.phrase) == ["in 1998"])
    let range = try #require(try env.store.memories.fetch(target.id)?.range)
    #expect(range.earliest?.year == 1998 && range.origin == .stated)
}

@Test func mergeMovesEverythingAndDeletesTheSource() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, source) = try env.kept("we drove to disney in the wagon with Maya", title: "The drive", people: ["Maya"], collection: "Trips")
    try env.store.memories.updateRange(source.id, .year(1998, origin: .stated, evidence: "in 1998"))
    let maya = try env.actions.linkNewPerson(named: "Maya", to: source.id)
    let receipt = try env.actions.merge(source.id, into: target.id)
    #expect(try env.store.memories.fetch(source.id) == nil)
    let spans = try env.store.memories.spans(of: target.id)
    #expect(spans.count == 2 && spans[1].order == 1 && spans[1].titleText == "The drive")
    #expect(try env.store.memories.people(of: target.id).map(\.id) == [maya.id])
    #expect(try env.store.chapters.collections(of: target.id).map(\.title) == ["Trips"])
    #expect(try env.store.memories.fetch(target.id)?.range.earliest?.year == 1998, "an unplaced target takes the source's range")
    #expect(receipt.before.count == 2 && receipt.candidateID == nil && receipt.targetTitle == "Orange house")
}

@Test func mergeKeepsTheTargetsCollectionsAndChapter() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house", collection: "Home")
    let chapter = try env.actions.createChapter(title: "Childhood", containing: target.id)
    let (_, source) = try env.kept("we drove to disney", title: "The drive", collection: "Trips")
    _ = try env.actions.createChapter(title: "Teens", containing: source.id)
    try env.store.memories.updateRange(target.id, .year(1990, origin: .stated, evidence: "1990"))
    try env.store.memories.updateRange(source.id, .year(1998, origin: .stated, evidence: "1998"))
    _ = try env.actions.merge(source.id, into: target.id)
    #expect(try env.store.chapters.collections(of: target.id).map(\.title) == ["Home"])
    let after = try #require(try env.store.memories.fetch(target.id))
    #expect(after.chapterID == chapter.id && after.range.earliest?.year == 1990, "a placed target keeps its own range")
}

@Test func mergingAMemoryIntoItselfThrows() throws {
    let env = try Env()
    let (_, a) = try env.kept("we lived in an orange house", title: "Orange house")
    #expect(throws: CandidateActions.Error.sameMemory) { try env.actions.merge(a.id, into: a.id) }
    #expect(throws: CandidateActions.Error.targetMissing) { try env.actions.merge(a.id, into: MemoryID(rawValue: "nope")) }
}

@Test func unmergeRestoresBothSides() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, source) = try env.kept("we drove to disney with Maya", title: "The drive", people: ["Maya"], collection: "Trips")
    let sourceSpans = try env.store.memories.spans(of: source.id)
    let receipt = try env.actions.merge(source.id, into: target.id)
    try env.actions.unmerge(receipt)
    let back = try #require(try env.store.memories.fetch(source.id))
    #expect(back.title == "The drive")
    #expect(try env.store.memories.spans(of: source.id) == sourceSpans)
    #expect(try env.store.chapters.collections(of: source.id).map(\.title) == ["Trips"])
    #expect(try env.store.memories.spans(of: target.id).count == 1)
    #expect(try env.store.chapters.collections(of: target.id).isEmpty)

    let (_, _, c) = try env.card("grew up in an orange house", title: "Grew up")
    let merged = try env.actions.mergeCandidate(c, into: target.id)
    try env.actions.unmerge(merged.receipt)
    #expect(try env.store.memories.spans(of: target.id).count == 1)
    #expect(try env.store.candidates.fetch(c.id)?.status == .pending, "the card waits again")
}

@Test func unmergeAfterAForeignChangeIsRefused() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, source) = try env.kept("we drove to disney", title: "The drive")
    let receipt = try env.actions.merge(source.id, into: target.id)
    let (_, _, c) = try env.card("grew up in an orange house", title: "Grew up")
    _ = try env.actions.mergeCandidate(c, into: target.id)
    #expect(throws: CandidateActions.Error.stale) { try env.actions.unmerge(receipt) }
    #expect(try env.store.memories.spans(of: target.id).count == 3, "nothing moved")
}

@Test func twoCardsMergeIntoOneMemoryInOrder() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, _, c1) = try env.card("grew up in an orange house", title: "Grew up")
    let (_, _, c2) = try env.card("the orange house had a canal", title: "The canal")
    _ = try env.actions.mergeCandidate(c1, into: target.id)
    _ = try env.actions.mergeCandidate(c2, into: target.id)
    let spans = try env.store.memories.spans(of: target.id)
    #expect(spans.map(\.order) == [0, 1, 2] && spans.map(\.candidateID) == [nil, c1.id, c2.id])
}

@Test func hintFollowsASameStoryCard() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, segment, c) = try env.card("every summer we went back to the orange house", title: "Back every summer", collection: "every summer")
    let hintOut = HintOut(kind: .collection, phrase: "every summer", memoryCandidateID: c.id.rawValue)
    let hint = StoreFixtures.candidate(segment.id, ordinal: 1, kind: .hint, payload: try CandidatePayload.encode(hintOut))
    try env.store.candidates.insert(hint)
    #expect(throws: CandidateActions.Error.memoryNotAccepted) { try env.actions.acceptHint(hint) }
    _ = try env.actions.mergeCandidate(c, into: target.id)
    guard case .collection(let collection) = try env.actions.acceptHint(hint) else { Issue.record("expected a collection"); return }
    #expect(try env.store.chapters.members(of: collection.id).map(\.id) == [target.id])
}

// MARK: - Review fixes

@Test func mergingIntoAStandInMakesItReal() throws {
    let env = try Env()
    let (_, namer) = try env.kept("the summer before graduation we drove", title: "The drive")
    let namerSpan = try #require(try env.store.memories.spans(of: namer.id).first)
    let standIn = try env.store.memories.insertFloating(title: "graduation", segment: namerSpan.segmentID, startMs: namerSpan.startMs, endMs: namerSpan.endMs)
    try env.store.memories.updateRange(standIn.id, .year(2004, origin: .stated, evidence: "in 2004"))
    let (_, source) = try env.kept("graduation day was hot and loud", title: "Graduation day", collection: "School")
    let sourceSpan = try #require(try env.store.memories.spans(of: source.id).first)
    let receipt = try env.actions.merge(source.id, into: standIn.id)
    let real = try #require(try env.store.memories.fetch(standIn.id))
    #expect(!real.isFloating && real.title == "Graduation day" && real.summaryQuote == source.summaryQuote && real.createdFromCandidateID == source.createdFromCandidateID)
    let spans = try env.store.memories.spans(of: standIn.id)
    #expect(spans.count == 1 && spans[0].order == 0 && spans[0].segmentID == sourceSpan.segmentID, "the borrowed span is gone; the real telling is first")
    #expect(real.range.earliest?.year == 2004, "the stand-in's own range stays")
    #expect(try env.store.chapters.collections(of: standIn.id).map(\.title) == ["School"])
    #expect(try env.store.memories.fetch(source.id) == nil)
    try env.actions.unmerge(receipt)
    #expect(try env.store.memories.fetch(standIn.id)?.isFloating == true && (try env.store.memories.fetch(source.id)) != nil)
}

@Test func mergingAStandInSourceThrowsAndPickerSkipsStandIns() throws {
    let env = try Env()
    let (_, namer) = try env.kept("the summer before graduation we drove", title: "The drive")
    let namerSpan = try #require(try env.store.memories.spans(of: namer.id).first)
    let standIn = try env.store.memories.insertFloating(title: "graduation", segment: namerSpan.segmentID, startMs: namerSpan.startMs, endMs: namerSpan.endMs)
    #expect(throws: CandidateActions.Error.standIn) { try env.actions.merge(standIn.id, into: namer.id) }
    let matcher = MemoryMatcher(store: env.store, embedder: nil)
    #expect(try matcher.picker(for: "graduation", excluding: [], includeHidden: true).map(\.memoryID) == [namer.id], "a stand-in is not something the person can pick")
}

@Test func unmergeAfterARenameIsRefused() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, source) = try env.kept("we drove to disney", title: "The drive")
    let receipt = try env.actions.merge(source.id, into: target.id)
    try env.actions.renameMemory(target.id, to: "The orange house on Royal Palm")
    #expect(throws: CandidateActions.Error.stale) { try env.actions.unmerge(receipt) }
    #expect(try env.store.memories.fetch(target.id)?.title == "The orange house on Royal Palm", "the rename stands")
    let (_, _, c) = try env.card("grew up in an orange house", title: "Grew up")
    let merged = try env.actions.mergeCandidate(c, into: target.id)
    try env.store.memories.updateRange(target.id, .stated(year: 1998))
    #expect(throws: CandidateActions.Error.stale) { try env.actions.unmerge(merged.receipt) }
}

@Test func mergeSpanIsOneTransaction() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, _, c) = try env.card("grew up in an orange house", title: "Grew up")
    // A span on a segment that does not exist fails the foreign key: nothing else may land either.
    let bad = MemorySpan(memoryID: target.id, segmentID: SegmentID(rawValue: "missing"), startMs: 0, endMs: 1, order: 1, titleText: "Grew up", candidateID: c.id)
    let person = try env.store.people.insertPerson(displayName: "Maya")
    #expect(throws: (any Error).self) {
        try env.store.memories.mergeSpan(bad, people: [MemoryPerson(memoryID: target.id, personID: person.id, roleText: nil)], places: [], anchors: [],
                                         promotingStandIn: nil, acceptingCandidate: c.id)
    }
    #expect(try env.store.candidates.fetch(c.id)?.status == .pending)
    #expect(try env.store.memories.people(of: target.id).isEmpty && (try env.store.memories.spans(of: target.id)).count == 1)
}

// MARK: - Second review (B1, T1, T2)

@Test func unmergeIsOneTransaction() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (_, source) = try env.kept("we drove to disney", title: "The drive")
    var receipt = try env.actions.merge(source.id, into: target.id)
    let merged = try #require(try env.store.memories.snapshot(of: target.id))
    // The source's snapshot names a collection that no longer exists: its restore fails the foreign key.
    receipt.before[1].collectionIDs = [CollectionID(rawValue: "gone")]
    #expect(throws: (any Error).self) { try env.actions.unmerge(receipt) }
    let after = try #require(try env.store.memories.snapshot(of: target.id))
    #expect(after.spans == merged.spans && after.memory == merged.memory, "the target did not move: nothing partial landed")
    #expect(try env.store.memories.fetch(source.id) == nil)
}

@Test func twoCardsFromOneSessionMergeAndItsDeleteLeavesOrderZero() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    let (session, segs) = try StoreFixtures.session(in: env.store.sessions, segments: ["grew up in an orange house", "the orange house had a canal"])
    var cards: [Candidate] = []
    for (i, seg) in segs.enumerated() {
        let out = MemoryOut(ref: "m\(i)", kind: .event, title: seg.text, quote: seg.text, segmentSpan: WordSpan(startWord: 0, endWord: 1), peopleRefs: [], placeText: nil,
                            anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.9)
        let c = StoreFixtures.candidate(seg.id, payload: try CandidatePayload.encode(out))
        try env.store.candidates.insert(c)
        cards.append(c)
    }
    for c in cards { _ = try env.actions.mergeCandidate(c, into: target.id) }
    #expect(try env.store.memories.spans(of: target.id).map(\.order) == [0, 1, 2])
    try env.store.sessions.deleteSession(session)
    let spans = try env.store.memories.spans(of: target.id)
    #expect(spans.count == 1 && spans[0].order == 0 && spans[0].titleText == nil, "only the first telling remains")
    #expect(try env.store.memories.fetch(target.id)?.createdFromCandidateID == target.createdFromCandidateID)
}

@Test func sameStoryNeverOverwritesAStatedTarget() throws {
    let env = try Env()
    let (_, target) = try env.kept("we lived in an orange house", title: "Orange house")
    try env.actions.setStatedRange(target.id, .stated(year: 1997))
    let (_, _, c) = try env.card("that was in 1998 in the orange house", title: "The orange house in 1998",
                                 anchors: [AnchorOut(phrase: "in 1998", relation: .absolute, targetText: nil, value: "1998")])
    _ = try env.actions.mergeCandidate(c, into: target.id)
    let range = try #require(try env.store.memories.fetch(target.id)?.range)
    #expect(range.earliest?.year == 1997 && range.displayText == "1997", "the person's own date stands over the card's anchor")
}
