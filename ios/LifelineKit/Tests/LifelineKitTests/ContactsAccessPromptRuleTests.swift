import Testing
@testable import LifelineKit

// PC-b Task 5: when the landing may show the one system prompt for contacts (spec, "Access"; PB36).

@Test func theLandingAsksWhenNotAskedAndAKeptMomentNamesAPerson() {
    #expect(ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: 1, landingIsQuiet: true))
    #expect(ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: 3, landingIsQuiet: true))
}

@Test(arguments: [ContactsAccess.full, .limited, .denied])
func theLandingNeverAsksOnceTheSystemHasAnAnswer(access: ContactsAccess) {
    #expect(!ContactsPromptRule.shouldAsk(access: access, askedBefore: false, keptPeopleInSession: 2, landingIsQuiet: true))
}

@Test func theLandingAsksOnlyOnce() {
    #expect(!ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: true, keptPeopleInSession: 2, landingIsQuiet: true))
}

@Test func theLandingDoesNotAskBeforeAKeptMomentNamesAPerson() {
    #expect(!ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: 0, landingIsQuiet: true))
    #expect(!ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: -1, landingIsQuiet: true),
            "a bad count is no person")
}

// PB36: no system dialog after a heavy recording or a serious disclosure; the next quiet landing asks.
@Test func aHeavyLandingDoesNotAsk() {
    #expect(!ContactsPromptRule.shouldAsk(access: .notAsked, askedBefore: false, keptPeopleInSession: 2, landingIsQuiet: false))
}
