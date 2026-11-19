import Foundation
import Testing
@testable import LifelineKit

private let segment = "the garden behind the house had a pomegranate tree and my mother picked them"
private let words = segment.split(separator: " ").map(String.init)

private func memory(quote: String = "had a pomegranate tree", span: WordSpan = WordSpan(startWord: 5, endWord: 8),
                    people: [String] = ["my mother"], place: String? = nil, anchors: [AnchorOut] = [],
                    title: String = "The pomegranate tree") -> MemoryOut {
    MemoryOut(ref: "m1", title: title, quote: quote, segmentSpan: span, peopleRefs: people, placeText: place, anchors: anchors,
              collectionHint: nil, chapterHint: nil, confidence: 0.9)
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

// MARK: - People with handles (v8)

private let robyns = "Robyn from work brought the cake and the other Robyn, my cousin, sang all night"
private let robynWords = robyns.split(separator: " ").map(String.init)

private func handled(_ ref: String, quote: String, span: WordSpan, handles: [String]) -> MemoryOut {
    var m = MemoryOut(ref: ref, kind: .event, title: "T", quote: quote, segmentSpan: span, peopleRefs: [], placeText: nil, anchors: [],
                      collectionHint: nil, chapterHint: nil, confidence: 0.9)
    m.personHandles = handles
    return m
}

private let cake = handled("m1", quote: "Robyn from work brought the cake", span: WordSpan(startWord: 0, endWord: 5), handles: ["p1"])
private let song = handled("m2", quote: "sang all night", span: WordSpan(startWord: 12, endWord: 14), handles: ["p2"])
private let work = PersonOut(handle: "p1", saidName: "Robyn", relationText: "from work", personID: nil)
private let cousin = PersonOut(handle: "p2", saidName: "Robyn", relationText: "my cousin", personID: nil)

private func peopleOutput(_ people: [PersonOut], _ memories: [MemoryOut]) -> ExtractorOutput {
    var out = ExtractorOutput(memories: memories, mentions: [], flags: .none)
    out.people = people
    return out
}

@Test func peopleWithSaidNamesInTheSegmentAreKept() {
    let v = OutputValidator.validate(peopleOutput([work, cousin], [cake, song]), segmentText: robyns, words: robynWords)
    #expect(v.people == [work, cousin])
    #expect(v.accepted == [.memory(cake), .memory(song)] && v.rejected.isEmpty)
}

@Test func aPersonWhoseSaidNameIsNotInTheSegmentIsDroppedWithItsMemory() {
    let invented = PersonOut(handle: "p2", saidName: "Robin", relationText: "my cousin", personID: nil)
    let v = OutputValidator.validate(peopleOutput([work, invented], [cake, song]), segmentText: robyns, words: robynWords)
    #expect(v.people == [work])
    #expect(v.accepted == [.memory(cake)])
    #expect(v.rejected.map(\.reason) == ["person_handles not in people: p2"])
}

@Test func aMemoryWithAnUnknownHandleIsRejected() {
    let v = OutputValidator.validate(peopleOutput([work], [cake, song]), segmentText: robyns, words: robynWords)
    #expect(v.accepted == [.memory(cake)])
    #expect(v.rejected.map(\.reason) == ["person_handles not in people: p2"])
}

@Test func aDuplicateHandleKeepsTheFirstPerson() {
    let again = PersonOut(handle: "p1", saidName: "my cousin", relationText: nil, personID: nil)
    let v = OutputValidator.validate(peopleOutput([work, again], [cake]), segmentText: robyns, words: robynWords)
    #expect(v.people == [work])
    #expect(v.accepted == [.memory(cake)])
}

@Test func aPersonWithABlankHandleIsDropped() {
    let blank = PersonOut(handle: " ", saidName: "Robyn", relationText: nil, personID: nil)
    let v = OutputValidator.validate(peopleOutput([blank, work], [cake]), segmentText: robyns, words: robynWords)
    #expect(v.people == [work], "a blank handle cannot be named by a memory")
}

// PC-d Task 4b (D17): a handle of the recording so far needs no `people` entry in a later segment.
private let late = "She was always late"
private let lateWords = ["She", "was", "always", "late"]
private let lateMemory = handled("m1", quote: "She was always late", span: WordSpan(startWord: 0, endWord: 3), handles: ["p1"])

@Test func aRecordingHandleWithNoPeopleEntryIsAccepted() {
    let v = OutputValidator.validate(peopleOutput([], [lateMemory]), segmentText: late, words: lateWords, recordingHandles: ["p1"])
    #expect(v.accepted == [.memory(lateMemory)] && v.rejected.isEmpty)
    #expect(v.people.isEmpty, "the recording's entry is not this output's person")
}

@Test func aHandleKnownNowhereIsStillRejected() {
    let v = OutputValidator.validate(peopleOutput([], [lateMemory]), segmentText: late, words: lateWords, recordingHandles: [])
    #expect(v.accepted.isEmpty)
    #expect(v.rejected.map(\.reason) == ["person_handles not in people: p1"])
}
