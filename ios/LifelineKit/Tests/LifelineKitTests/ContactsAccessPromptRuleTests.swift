import Testing
@testable import LifelineKit

// PC-b Task 5: when the landing may show the one system prompt for contacts (spec, "Access").

@Test func theLandingAsksWhenNotAskedAndAKeptMomentNamesAPerson() {
    #expect(ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: 1))
    #expect(ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: 3))
}

@Test(arguments: [ContactsAccess.full, .limited, .denied])
func theLandingNeverAsksOnceTheSystemHasAnAnswer(access: ContactsAccess) {
    #expect(!ContactsPromptRule.shouldAsk(access: access, askedBefore: false, keptPeopleInSession: 2))
}

@Test func theLandingAsksOnlyOnce() {
    #expect(!ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: true, keptPeopleInSession: 2))
}

@Test func theLandingDoesNotAskBeforeAKeptMomentNamesAPerson() {
    #expect(!ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: 0))
    #expect(!ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: -1), "a bad count is no person")
}
