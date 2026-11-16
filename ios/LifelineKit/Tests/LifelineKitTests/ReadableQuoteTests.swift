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

// Fix round 1: the cleanup must never change the person's words.

@Test func onlyALetterIsCapitalised() {
    #expect(ReadableQuote.text("1999 was the year") == "1999 was the year")
    #expect(ReadableQuote.text("3rd of June") == "3rd of June")
    #expect(ReadableQuote.text("2 years later") == "2 years later")
    #expect(ReadableQuote.text("\"we left\" she said") == "\"We left\" she said")
    #expect(ReadableQuote.text("\u{201C}we left") == "\u{201C}We left")
    #expect(ReadableQuote.text("\u{1F3E0} we left") == "\u{1F3E0} we left")
}

@Test func aRepeatKeepsTheWordAsWritten() {
    #expect(ReadableQuote.text("it was 20% 20% off") == "It was 20% off")
    #expect(ReadableQuote.text("we used C++ C++ daily") == "We used C++ daily")
    #expect(ReadableQuote.text("it was big, big.") == "It was big.")
    #expect(ReadableQuote.text("it was big big?!") == "It was big?!")
    #expect(ReadableQuote.text("he said \"no no\"") == "He said \"no\"")
    #expect(ReadableQuote.text("I had had enough") == "I had had enough")
    #expect(ReadableQuote.text("so that that works") == "So that that works")
    #expect(ReadableQuote.text("I had had had enough") == "I had had had enough")
}

@Test func aFillerNeverTurnsAStatementIntoAQuestion() {
    #expect(ReadableQuote.text("it was hard, you know?") == "It was hard.")
    #expect(ReadableQuote.text("it was hard, you know!") == "It was hard.")
    #expect(ReadableQuote.text("it was hard, you know.") == "It was hard.")
    #expect(ReadableQuote.text("is it hard? um.") == "Is it hard?", "no doubled mark")
    #expect(ReadableQuote.text("it was hard. um...") == "It was hard.", "no doubled mark")
}

@Test func theVerbLikeSurvives() {
    #expect(ReadableQuote.text("I like, really like, dogs") == "I like, really like, dogs")
    #expect(ReadableQuote.text("it was, like, huge") == "It was, huge")
    #expect(ReadableQuote.text("it was like, huge") == "It was huge")
    #expect(ReadableQuote.text("we ran, like, a mile") == "We ran, a mile")
}

@Test func edgesOfTheCleanup() {
    #expect(ReadableQuote.text("Um, we left") == "We left")
    #expect(ReadableQuote.text("one two three", maxWords: 3) == "One two three")
    #expect(ReadableQuote.text("one two", maxWords: 0) == "One…", "a limit below one acts as one")
    #expect(ReadableQuote.text("we paid -5 or more", maxWords: 3) == "We paid -5…")
    #expect(ReadableQuote.text("we left, and then, so", maxWords: 3) == "We left, and…")
}
