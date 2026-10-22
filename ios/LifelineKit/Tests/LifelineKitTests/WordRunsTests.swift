import CoreMedia
import Foundation
import Speech
import Testing
@testable import LifelineKit

private func ms(_ v: Int) -> CMTime { CMTime(value: CMTimeValue(v), timescale: 1000) }

private func timed(_ s: inout AttributedString, _ word: String, _ start: Int, _ end: Int) {
    let r = s.range(of: word)!
    s[r][AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(start: ms(start), end: ms(end))
}

@Test func oneWordPerTimedRun() {
    var s = AttributedString("the blue door")
    timed(&s, "the", 0, 300); timed(&s, "blue", 300, 700); timed(&s, "door", 700, 1_100)
    #expect(WordRuns.words(from: s) == [w("the", 0, 300), w("blue", 300, 700), w("door", 700, 1_100)])
}

@Test func multiTokenRunIsSplitEvenly() {
    var s = AttributedString("a b")
    timed(&s, "a b", 0, 1_000)
    #expect(WordRuns.words(from: s) == [w("a", 0, 500), w("b", 500, 1_000)])
}

@Test func punctuationWithoutTimeJoinsPreviousWord() {
    var s = AttributedString("door.")
    timed(&s, "door", 700, 1_100)
    #expect(WordRuns.words(from: s) == [w("door.", 700, 1_100)])
}

@Test func leadingUntimedTextWaitsForTheFirstWord() {
    var s = AttributedString("— door")
    timed(&s, "door", 700, 1_100)
    #expect(WordRuns.words(from: s) == [w("door", 700, 1_100)])
}

@Test func whitespaceOnlyRunsAreIgnored() {
    var s = AttributedString("the  door")
    timed(&s, "the", 0, 300); timed(&s, "door", 400, 800)
    #expect(WordRuns.words(from: s).map(\.text) == ["the", "door"])
}

@Test func noTimedRunsGivesNoWords() {
    #expect(WordRuns.words(from: AttributedString("hello")).isEmpty)
}

@Test func msConversionRounds() {
    #expect(WordRuns.milliseconds(CMTime(value: 1, timescale: 3)) == 333)
    #expect(WordRuns.milliseconds(.invalid) == 0)
}
