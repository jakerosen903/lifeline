import Foundation
import Testing
@testable import LifelineKit

// Final review of S3, item 4: Timeline after About. The summary's "things about your life" and the tag menu. Invented words only.

private func memory(_ title: String, kind: MemoryKind, hidden: Bool = false, floating: Bool = false) -> Memory {
    Memory(id: .init(), title: title, summaryQuote: title, visibility: .timeline, chapterID: nil,
           createdFromCandidateID: floating ? nil : CandidateID(), createdAt: .now, hiddenFromTimeline: hidden, kind: kind)
}

@Test func thingsAboutYourLifeCountsOnlyVisibleToldFactsFeelingsAndGoals() {
    let all = [memory("A fact", kind: .fact), memory("A feeling", kind: .feeling), memory("A goal", kind: .goal),
               memory("Hidden fact", kind: .fact, hidden: true), memory("Stand-in", kind: .goal, floating: true),
               memory("A moment", kind: .event)]
    #expect(TimelineSummary.thingsAboutYourLife(all) == 3, "hidden and floating ones are not counted; a moment is not a thing")
}

@Test func theSummaryLeavesOutThingsWhileATagFilterIsOn() {
    #expect(TimelineSummary.text(memories: 2, firstYear: 1999, things: 3, tagFiltered: false)
            == "2 memories · 1999 → now · and 3 things about your life")
    #expect(TimelineSummary.text(memories: 0, firstYear: nil, things: 2, tagFiltered: true) == "0 memories")
    #expect(TimelineSummary.text(memories: 1, firstYear: 2001, things: 1, tagFiltered: false)
            == "1 memory · 2001 → now · and 1 thing about your life")
    #expect(TimelineSummary.text(memories: 1, firstYear: nil, things: 0, tagFiltered: false) == "1 memory")
}

@Test func theTagMenuOffersOnlyTagsAMomentCarries() {
    let moment = memory("The lake", kind: .event), fact = memory("Oldest", kind: .fact), other = memory("Swim", kind: .event)
    let tags: [String: [String]] = [moment.id.rawValue: ["Summer", "family"], fact.id.rawValue: ["Family", "School"], "entity-1": ["home"]]
    #expect(TimelineSummary.menuTags(tags, moments: [moment, other]) == ["family", "Summer"],
            "a tag only a fact or an entity carries is not offered; once each, ignoring case, sorted ignoring case")
    #expect(TimelineSummary.menuTags(tags, moments: []).isEmpty)
}

@Test func aTagFilterTurnsOffWhenNoMomentCarriesItsTag() {
    #expect(TimelineSummary.filter("Summer", offered: ["family", "Summer"]) == "Summer")
    #expect(TimelineSummary.filter("summer", offered: ["Summer"]) == "summer", "case does not matter")
    #expect(TimelineSummary.filter("Summer", offered: ["family"]) == nil, "the last moment with the tag is gone")
    #expect(TimelineSummary.filter("Summer", offered: []) == nil, "no tag is offered, so no menu shows to clear it")
    #expect(TimelineSummary.filter(nil, offered: []) == nil)
}
