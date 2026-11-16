import Testing
@testable import LifelineKit

@Test func matchKeyIgnoresCaseAndEdgePunctuation() {
    #expect(MatchKey.of("Ohio.") == "ohio")
    #expect(MatchKey.of("  “The Road Trip”  ") == "the road trip")
    #expect(MatchKey.of("ohio") == MatchKey.of("OHIO!"))
}

@Test func matchKeyKeepsInnerPunctuationAndJoinsSpaces() {
    #expect(MatchKey.of("St. Louis") == "st. louis")
    #expect(MatchKey.of("the   road\ttrip") == "the road trip")
    #expect(MatchKey.of("Maya's house") == "maya's house")
}

@Test func matchKeyOfNothingIsEmpty() {
    #expect(MatchKey.of("") == "")
    #expect(MatchKey.of("  ...  ") == "", "only punctuation: an empty key, which matches nothing")
}

@Test func differentNamesHaveDifferentKeys() {
    #expect(MatchKey.of("The road trip") != MatchKey.of("The road trips"))
}
