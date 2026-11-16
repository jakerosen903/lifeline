import Testing
@testable import LifelineKit

// S2, Task 3: a quote cleaned for reading. Display only: stored text and audio never change.

@Test func fillerWordsAndRepeatsAreHidden() {
    #expect(ReadableQuote.text("we, we, -... spent a lot of time together, um, you know, a few summers") == "We spent a lot of time together, a few summers")
    #expect(ReadableQuote.text("um I was uh eight") == "I was eight")
    #expect(ReadableQuote.text("it was like, huge") == "It was huge")
    #expect(ReadableQuote.text("um, two years younger than me, you know") == "Two years younger than me")
    #expect(ReadableQuote.text("the the house had a blue door") == "The house had a blue door")
    #expect(ReadableQuote.text("and it rained, you know") == "And it rained")
}

@Test func wordsThatAreNotFillerStay() {
    #expect(ReadableQuote.text("I like dogs") == "I like dogs")
    #expect(ReadableQuote.text("it looked like a boat") == "It looked like a boat")
    #expect(ReadableQuote.text("you know what I mean") == "You know what I mean")
    #expect(ReadableQuote.text("I had had enough") == "I had had enough")
    #expect(ReadableQuote.text("") == "")
}

@Test func aLongQuoteEndsAtAWord() {
    #expect(ReadableQuote.text("one two three four five", maxWords: 3) == "One two three…")
    #expect(ReadableQuote.text("one two", maxWords: 3) == "One two")
}

@Test func moreCasesFromTheRules() {
    #expect(ReadableQuote.text("erm, well that that was fine") == "Well that that was fine")
    #expect(ReadableQuote.text("so, so, so we left") == "So we left")
    #expect(ReadableQuote.text("Um.") == "")
    #expect(ReadableQuote.text("  we   left  ") == "We left")
    #expect(ReadableQuote.text("it was, like, huge") == "It was, huge", "a comma before a filler stays; the filler takes its own comma")
    #expect(ReadableQuote.text("it rained, um.") == "It rained.", "the sentence's end mark moves to the word before")
    #expect(ReadableQuote.text("it was big big. Then we left") == "It was big. Then we left", "a repeat keeps the end mark of the sentence")
}
