import Testing
@testable import LifelineKit

private let said = ["my", "mother", "kept", "bees", "in", "fresno", "i", "was", "7", "when", "we", "moved", "the", "garden", "had", "a", "pomegranate", "tree", "im", "ive"]

private func reply(_ kind: ReplyKind, _ text: String?, askedAboutApp: Bool = false) -> InterviewerReply {
    InterviewerReply(kind: kind, text: text, askedAboutApp: askedAboutApp, disclosure: .none, wantsToStop: false)
}

@Test func aShortReplyOfSaidWordsIsSpoken() {
    #expect(TurnChecks.validate(reply(.reflection, "Your mother kept bees."), sessionWords: said) == .speak(.reflection, "Your mother kept bees."))
    #expect(TurnChecks.validate(reply(.question, "What was the garden like?"), sessionWords: said) == .speak(.question, "What was the garden like?"))
}

@Test func over20WordsIsDropped() {
    let long = Array(repeating: "tree", count: 21).joined(separator: " ")
    #expect(TurnChecks.validate(reply(.reflection, long), sessionWords: said) == .dropped("too long"))
    let ok = Array(repeating: "tree", count: 20).joined(separator: " ")
    #expect(TurnChecks.validate(reply(.reflection, ok), sessionWords: said) == .speak(.reflection, ok))
}

@Test func aNameThePersonDidNotSayIsDropped() {
    #expect(TurnChecks.validate(reply(.question, "Did Maya keep bees too?"), sessionWords: said) == .dropped("not said: maya"))
}

@Test func aNumberThePersonDidNotSayIsDropped() {
    #expect(TurnChecks.validate(reply(.reflection, "You were 8 when you moved."), sessionWords: said) == .dropped("not said: 8"))
    #expect(TurnChecks.validate(reply(.reflection, "You were 7 when you moved."), sessionWords: said) == .speak(.reflection, "You were 7 when you moved."))
}

@Test func aSecondSentenceMayStartCapitalized() {
    #expect(TurnChecks.validate(reply(.reflection, "Bees in Fresno. Tell me more! What happened?"), sessionWords: said)
        == .speak(.reflection, "Bees in Fresno. Tell me more! What happened?"))
}

@Test func iAndItsFormsAreNotCounted() {
    #expect(TurnChecks.validate(reply(.reflection, "So I'm hearing the garden, and I'd like to know."), sessionWords: said)
        == .speak(.reflection, "So I'm hearing the garden, and I'd like to know."))
}

@Test func aSpelledNumberThePersonDidNotSayIsDropped() {
    #expect(TurnChecks.validate(reply(.reflection, "Your three sisters kept bees."), sessionWords: said) == .dropped("not said: three"))
}

@Test func aSpelledNumberPassesWhenThePersonSaidTheDigits() {
    let session = said + ["3", "sisters"]
    #expect(TurnChecks.validate(reply(.reflection, "Your three sisters kept bees."), sessionWords: session) == .speak(.reflection, "Your three sisters kept bees."))
    #expect(TurnChecks.validate(reply(.reflection, "Seven is a lucky tree."), sessionWords: said) == .speak(.reflection, "Seven is a lucky tree."))
}

@Test func digitsPassWhenThePersonSpelledTheNumber() {
    let session = said + ["three", "sisters"]
    #expect(TurnChecks.validate(reply(.reflection, "Your 3 sisters kept bees."), sessionWords: session) == .speak(.reflection, "Your 3 sisters kept bees."))
    #expect(TurnChecks.validate(reply(.reflection, "Your 4 sisters kept bees."), sessionWords: session) == .dropped("not said: 4"))
}

@Test func textWithNoneIsDropped() {
    #expect(TurnChecks.validate(reply(.none, "hello"), sessionWords: said) == .dropped("text with none"))
    #expect(TurnChecks.validate(reply(.none, nil), sessionWords: said) == .none)
    #expect(TurnChecks.validate(reply(.none, ""), sessionWords: said) == .none)
}

@Test func emptyTextOnASpokenKindIsDropped() {
    #expect(TurnChecks.validate(reply(.question, nil), sessionWords: said) == .dropped("empty"))
    #expect(TurnChecks.validate(reply(.reflection, ""), sessionWords: said) == .dropped("empty"))
}

@Test func askedAboutAppNeverSpeaksModelText() {
    #expect(TurnChecks.validate(reply(.question, "Anything at all Zed", askedAboutApp: true), sessionWords: said) == .aboutApp)
    #expect(TurnChecks.validate(reply(.none, nil, askedAboutApp: true), sessionWords: said) == .aboutApp)
}

@Test func aNameJoinedByPunctuationIsStillChecked() {
    #expect(TurnChecks.validate(reply(.reflection, "The garden\u{2014}Maya's place."), sessionWords: said) == .dropped("not said: mayas"))
    #expect(TurnChecks.validate(reply(.question, "garden,Maya?"), sessionWords: said) == .dropped("not said: maya"))
    #expect(TurnChecks.validate(reply(.reflection, "The ex-Navy tree."), sessionWords: said) == .dropped("not said: navy"))
    #expect(TurnChecks.validate(reply(.reflection, "mary-Ann kept bees."), sessionWords: said) == .dropped("not said: ann"))
}

@Test func anAbbreviationDoesNotEndASentence() {
    #expect(TurnChecks.validate(reply(.question, "Did Dr. Patel help?"), sessionWords: said + ["dr"]) == .dropped("not said: patel"))
    #expect(TurnChecks.validate(reply(.question, "Did J. Patel help?"), sessionWords: said + ["j"]) == .dropped("not said: patel"))
    #expect(TurnChecks.validate(reply(.reflection, "Bees. Garden."), sessionWords: said) == .speak(.reflection, "Bees. Garden."))
}

@Test func anAccentedNameThePersonDidNotSayIsDropped() {
    #expect(TurnChecks.validate(reply(.question, "bees with \u{00C9}lise?"), sessionWords: said) == .dropped("not said: \u{00E9}lise"))
}

@Test func dashesSplitWordsForTheCount() {
    let text = Array(repeating: "tree", count: 11).joined(separator: "\u{2014}") + " " + Array(repeating: "tree", count: 10).joined(separator: "-")
    #expect(TurnChecks.validate(reply(.reflection, text), sessionWords: said) == .dropped("too long"))
}
