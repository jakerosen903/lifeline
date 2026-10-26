import Testing
@testable import LifelineKit

struct QuietMatcherTests {
    @Test func eachPhraseIsACommand() {
        for phrase in ["let me talk", "shh", "quiet please", "stop talking", "no questions"] {
            #expect(QuietMatcher.command(in: phrase) == .quiet, "\(phrase)")
        }
        for phrase in ["keep going", "a bit more"] {
            #expect(QuietMatcher.command(in: phrase) == .keepGoing, "\(phrase)")
        }
        // Case, punctuation and a few words around the phrase do not matter.
        #expect(QuietMatcher.command(in: "Okay, let me talk.") == .quiet)
        #expect(QuietMatcher.command(in: "Please keep going") == .keepGoing)
    }

    @Test func anySpellingOfShhIsQuiet() {
        for heard in ["sh", "shh", "Shhhh!", "shh shh"] {
            #expect(QuietMatcher.command(in: heard) == .quiet, "\(heard)")
        }
        #expect(QuietMatcher.command(in: "she") == nil)
        #expect(QuietMatcher.command(in: "s") == nil)
    }

    @Test func weHadToStopAtTheBorderIsNot() {
        #expect(QuietMatcher.command(in: "we had to stop at the border") == nil)
        #expect(QuietMatcher.command(in: "stop at the border") == nil)
    }

    @Test func aCommandInsideASentenceIsIgnored() {
        #expect(QuietMatcher.command(in: "my father would never let me talk back") == nil)
        #expect(QuietMatcher.command(in: "we had no questions about it then") == nil)
        #expect(QuietMatcher.command(in: "she said keep going and we did") == nil)
    }

    @Test func aPhraseCountsOnlyAsConsecutiveWords() {
        #expect(QuietMatcher.command(in: "let me now talk") == nil)
        #expect(QuietMatcher.command(in: "talking stop") == nil)
        #expect(QuietMatcher.command(in: "") == nil)
    }
}
