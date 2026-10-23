import Foundation
import Testing
@testable import LifelineKit

private let session = SessionID(rawValue: "s")
private func segment(_ i: Int) -> Segment {
    Segment(id: SegmentID(rawValue: "g\(i)"), sessionID: session, index: i, startMs: i * 10_000, endMs: i * 10_000 + 5_000, text: "segment \(i)", status: .extracted)
}
private func kept(_ title: String, quote: String, in seg: Segment, at start: Int) -> (Memory, MemorySpan) {
    var m = StoreFixtures.memory(from: CandidateID(), title: title)
    m.summaryQuote = quote
    return (m, MemorySpan(memoryID: m.id, segmentID: seg.id, startMs: start, endMs: start + 1_000, order: 0))
}
private func possible(_ title: String, quote: String, in seg: Segment) -> (Candidate, MemoryOut) {
    let out = MemoryOut(ref: "m", kind: .event, title: title, quote: quote, segmentSpan: WordSpan(startWord: 0, endWord: 1), peopleRefs: [], placeText: nil,
                        anchors: [], collectionHint: nil, chapterHint: nil, confidence: 0.8)
    return (StoreFixtures.candidate(seg.id, payload: (try? CandidatePayload.encode(out)) ?? "{}"), out)
}

@Test func landingRowsQuoteTheOwnerInSessionOrderCappedAtFive() {
    let segs = (0..<4).map(segment)
    let kept1 = kept("The blue door", quote: "the house had a blue door", in: segs[1], at: 12_000)
    let kept0 = kept("The garden", quote: "we had a pomegranate tree", in: segs[0], at: 3_000)
    let p2 = possible("Maya climbed it", quote: "my sister Maya climbed it", in: segs[2])
    let p3 = possible("Moving away", quote: "we moved away", in: segs[3])
    let p0b = possible("The swing", quote: "there was a swing", in: segs[0])
    let extra = possible("One more", quote: "one more thing", in: segs[3])
    let (rows, more) = Landing.rows(kept: [kept1, kept0], possible: [p2, p3, p0b, extra], segments: segs)
    #expect(rows.map(\.title) == ["The garden", "The swing", "The blue door", "Maya climbed it", "Moving away"], "session order: kept and possible mixed, capped at five")
    #expect(more == 1)
    #expect(rows[0].quote == "we had a pomegranate tree" && rows[0].isKept && rows[0].play == MsRange(start: 3_000, end: 4_000))
    #expect(rows[1].play == segs[0].range && !rows[1].isKept, "a possible memory plays its whole moment")
    #expect(Set(rows.map(\.id)).count == 5)
}

@Test func stillSortingCountsPendingSegments() {
    #expect(Landing.stillSorting(pendingSegments: 0) == nil)
    #expect(Landing.stillSorting(pendingSegments: 1) == "Still sorting: 1 more")
    #expect(Landing.stillSorting(pendingSegments: 3) == "Still sorting: 3 more")
}

@Test func closingLineNeutralWhenHeavy() {
    let item = CuriosityItem(id: .init(), kind: .droppedThread, text: "the summer in Fresno", payoffCount: 2, status: .open, sourceMemoryID: nil, targetMemoryID: nil)
    #expect(Landing.closingLine(topCuriosity: item, heavy: true) == "Thank you. That's enough for today.")
    #expect(Landing.closingLine(topCuriosity: item, heavy: false) == "Next time, if you like: You mentioned “the summer in Fresno”. Tell me about that.")
    #expect(Landing.closingLine(topCuriosity: nil, heavy: false) == "Thank you for today.")
}

@Test func firstSessionVariant() {
    #expect(Landing.isFirstSession(sessionCount: 1))
    #expect(!Landing.isFirstSession(sessionCount: 2))
    #expect(!Landing.isFirstSession(sessionCount: 0))
    #expect(Landing.headline(first: true, heavy: false) == "Your first story is saved. Hear it back.")
    #expect(Landing.headline(first: false, heavy: false) == "Your recording is saved.")
    #expect(Landing.headline(first: true, heavy: true) == "Your recording is saved.", "a heavy first session is not celebrated")
}

@Test func twoTellingsOfOneMemoryInOneSessionAreTwoRows() {
    let segs = (0..<2).map(segment)
    let (memory, first) = kept("The blue door", quote: "the house had a blue door", in: segs[0], at: 1_000)
    let second = MemorySpan(memoryID: memory.id, segmentID: segs[1].id, startMs: 11_000, endMs: 12_000, order: 1, titleText: "Grew up behind the door", candidateID: nil)
    let (rows, _) = Landing.rows(kept: [(memory, first), (memory, second)], possible: [], segments: segs)
    #expect(rows.count == 2 && Set(rows.map(\.id)).count == 2, "each telling is its own row with its own id")
    #expect(rows[1].title == "Grew up behind the door" && rows[1].play.start == 11_000, "a retelling shows the words it was kept under")
}
