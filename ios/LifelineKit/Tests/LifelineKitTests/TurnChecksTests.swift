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

@Test func spelledNumbersAreNotCounted() {
    #expect(TurnChecks.validate(reply(.reflection, "Seven is a lucky tree."), sessionWords: said) == .speak(.reflection, "Seven is a lucky tree."))
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
