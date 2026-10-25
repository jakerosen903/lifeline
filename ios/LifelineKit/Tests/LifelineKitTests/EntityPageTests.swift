import Foundation
import Testing
@testable import LifelineKit

private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }
private func range(_ a: Int, _ b: Int, _ origin: RangeOrigin) -> TimeRange {
    TimeRange(earliest: d("\(a)-01-01"), latest: d("\(b)-12-31"), likelyStart: nil, likelyEnd: nil, granularity: .year, origin: origin, evidenceText: nil)
}

@Test func spanTextSaysWhatIsKnown() {
    #expect(EntityPage.spanText(.unplaced) == "no dates yet")
    #expect(EntityPage.spanText(range(1993, 1998, .derived)) == "from 1993 to 1998")
    #expect(EntityPage.spanText(range(1998, 1998, .inferred)) == "around 1998")
    #expect(EntityPage.spanText(range(1998, 1998, .stated)) == "in 1998")
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
