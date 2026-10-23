import Foundation
import Testing
@testable import LifelineKit

private let segment = "the garden behind the house had a pomegranate tree and my mother picked them"
private let words = segment.split(separator: " ").map(String.init)

private func memory(quote: String = "had a pomegranate tree", span: WordSpan = WordSpan(startWord: 5, endWord: 8),
                    people: [String] = ["my mother"], place: String? = nil, anchors: [AnchorOut] = [],
                    title: String = "The pomegranate tree") -> MemoryOut {
    MemoryOut(ref: "m1", title: title, quote: quote, segmentSpan: span, peopleRefs: people, placeText: place, anchors: anchors,
              sameAsMemoryID: nil, collectionHint: nil, chapterHint: nil, confidence: 0.9)
}

private func output(_ memories: [MemoryOut] = [], mentions: [MentionOut] = [], flags: Flags = .none) -> ExtractorOutput {
    ExtractorOutput(memories: memories, mentions: mentions, flags: flags)
}

@Test func validMemoryIsAccepted() {
    let v = OutputValidator.validate(output([memory()]), segmentText: segment, words: words)
    #expect(v.accepted.count == 1 && v.rejected.isEmpty)
}

@Test func quoteNotInSegmentIsRejected() {
    let v = OutputValidator.validate(output([memory(quote: "we drove to Yosemite")]), segmentText: segment, words: words)
    #expect(v.accepted.isEmpty && v.rejected.count == 1)
    #expect(v.rejected[0].reason.contains("quote"))
}

@Test func peopleRefNotInSegmentIsRejected() {
    let v = OutputValidator.validate(output([memory(people: ["Dad"])]), segmentText: segment, words: words)
    #expect(v.rejected.first?.reason.contains("people_refs") == true)
}

@Test func quoteMatchesAcrossWhitespaceAndCase() {
    let v = OutputValidator.validate(output([memory(quote: "The  garden\nbehind")]), segmentText: segment, words: words)
    #expect(v.accepted.count == 1)
}

@Test func spanOutsideWordsIsRejected() {
    let v = OutputValidator.validate(output([memory(span: WordSpan(startWord: 3, endWord: words.count))]), segmentText: segment, words: words)
    #expect(v.rejected.first?.reason.contains("segment_span") == true)
    let backwards = OutputValidator.validate(output([memory(span: WordSpan(startWord: 5, endWord: 2))]), segmentText: segment, words: words)
    #expect(backwards.rejected.count == 1)
}

@Test func titleOverEightWordsIsRejected() {
    let v = OutputValidator.validate(output([memory(title: "one two three four five six seven eight nine")]), segmentText: segment, words: words)
    #expect(v.rejected.first?.reason.contains("title") == true)
}

@Test func placeAndAnchorPhrasesMustBeInTheSegment() {
    let badPlace = OutputValidator.validate(output([memory(place: "Fresno")]), segmentText: segment, words: words)
    #expect(badPlace.rejected.first?.reason.contains("place_text") == true)
    let badAnchor = OutputValidator.validate(output([memory(anchors: [AnchorOut(phrase: "in 1998", relation: .absolute, targetText: nil, value: nil)])]),
                                             segmentText: segment, words: words)
    #expect(badAnchor.rejected.first?.reason.contains("anchors") == true)
}

@Test func mentionTextMustBeInTheSegment() {
    let good = MentionOut(text: "my mother", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)
    let bad = MentionOut(text: "Sam", kind: .person, likelyAliasOfPersonID: nil, confidence: 0.8)
    let v = OutputValidator.validate(output(mentions: [good, bad]), segmentText: segment, words: words)
    #expect(v.accepted.count == 1 && v.rejected.count == 1)
}

@Test func flagsPassThroughUnchanged() {
    let flags = Flags(seriousDisclosure: true, wantsToStop: false, wantsToChangeSubject: true)
    let v = OutputValidator.validate(output(flags: flags), segmentText: segment, words: words)
    #expect(v.flags == flags)
}

@Test func shortNameInsideAWordIsRejected() {
    let text = "we always planned to visit and I used the old road"
    let w = text.split(separator: " ").map(String.init)
    for name in ["Al", "Ann", "Ed"] {
        let v = OutputValidator.validate(output(mentions: [MentionOut(text: name, kind: .person, likelyAliasOfPersonID: nil, confidence: 0.9)]), segmentText: text, words: w)
        #expect(v.accepted.isEmpty, "\(name) is not in the text as a word")
    }
    let real = OutputValidator.validate(output(mentions: [MentionOut(text: "old road", kind: .place, likelyAliasOfPersonID: nil, confidence: 0.9)]), segmentText: text, words: w)
    #expect(real.accepted.count == 1)
}

@Test func curlyApostropheMatchesStraightAndEdgePunctuationIsIgnored() {
    let text = "my mom’s kitchen, the one on Olive Avenue."
    let w = text.split(separator: " ").map(String.init)
    let v = OutputValidator.validate(output([memory(quote: "my mom's kitchen", span: WordSpan(startWord: 0, endWord: 2), people: ["mom's"], place: "Olive Avenue")]), segmentText: text, words: w)
    #expect(v.accepted.count == 1, "\(v.rejected.map(\.reason))")
}
