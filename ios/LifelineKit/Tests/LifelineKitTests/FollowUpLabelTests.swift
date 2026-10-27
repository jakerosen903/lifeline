import Foundation
import Testing
@testable import LifelineKit

private func hint(_ kind: HintKind, _ phrase: String) -> Card {
    .hint(StoreFixtures.candidate(SegmentID(), kind: .hint, payload: "{}"), HintOut(kind: kind, phrase: phrase, memoryCandidateID: "m"))
}
private func entity(_ text: String, _ kind: MentionKind, title: String? = nil) -> Card {
    .entity(StoreFixtures.candidate(SegmentID(), kind: .entity, payload: "{}"),
            MentionOut(text: text, kind: kind, likelyAliasOfPersonID: nil, confidence: 0.8, title: title))
}
private func person(_ text: String) -> Card {
    .whoIsThis(.candidate(StoreFixtures.candidate(SegmentID(), kind: .person, payload: "{}")), text: text)
}

@Test func questionTextForEachFollowUp() {
    #expect(FollowUpLabel.question(hint(.domain, "family")) == "Family?")
    #expect(FollowUpLabel.question(hint(.story, "the steak dinner")) == "Story: the steak dinner?")
    #expect(FollowUpLabel.question(hint(.collection, "summers")) == "Collection: summers?")
    #expect(FollowUpLabel.question(hint(.chapter, "college")) == "Chapter: college?")
    #expect(FollowUpLabel.question(entity("the shed", .thing)) == "the shed: a thing?")
    #expect(FollowUpLabel.question(entity("the lake", .place)) == "the lake: a place?")
    #expect(FollowUpLabel.question(entity("being kind", .idea)) == "being kind: something you think?")
    #expect(FollowUpLabel.question(entity("being kind", .idea, title: "Kindness")) == "Kindness: something you think?")
    #expect(FollowUpLabel.question(person("Theo")) == "Theo: who's this?")
}

@Test func doneTextDropsQuestionAndSuffix() {
    #expect(FollowUpLabel.done(hint(.domain, "family")) == "✓ Family")
    #expect(FollowUpLabel.done(hint(.story, "the steak dinner")) == "✓ Story: the steak dinner")
    #expect(FollowUpLabel.done(entity("the shed", .thing)) == "✓ the shed")
    #expect(FollowUpLabel.done(entity("being kind", .idea, title: "Kindness")) == "✓ Kindness")
    #expect(FollowUpLabel.done(person("Theo")) == "✓ Theo")
}
