import Foundation
import Testing
@testable import LifelineKit

private let card = "Thank you for telling me that. You can stop here, or keep going. It is your choice. If you need to talk to someone now, call or text 988 (Suicide and Crisis Lifeline, US)."

@Test func disclosureIsVerbatim() throws {
    #expect(try FixedResponses.disclosure(locale: Locale(identifier: "en_US")) == card)
}

@Test func unknownLocaleFallsBackToUS() throws {
    #expect(try FixedResponses.disclosure(locale: Locale(identifier: "fr_FR")) == card)
}

@Test func crisisLineForUS() {
    let line = FixedResponses.crisisLine(locale: Locale(identifier: "en_US"))
    #expect(line.number == "988" && line.label.contains("Suicide and Crisis Lifeline"))
    #expect(FixedResponses.crisisLine(locale: Locale(identifier: "de_DE")) == line, "V1 ships the US line only")
}

@Test func presentSpokenEqualsTheCard() throws {
    #expect(try FixedResponses.spokenDisclosure(.present, locale: Locale(identifier: "en_US")) == card)
}

@Test func thePastTextHasNoCrisisNumber() throws {
    let past = try #require(try FixedResponses.spokenDisclosure(.past, locale: Locale(identifier: "en_US")))
    #expect(past == "Thank you for telling me that. You can stop here, or keep going. It is your choice.")
    #expect(!past.contains("988"))
}

@Test func theCardStartsWithThePastText() throws {
    let past = try #require(try FixedResponses.spokenDisclosure(.past))
    #expect(try FixedResponses.disclosure().hasPrefix(past))
}

@Test func noDisclosureSpeaksNothing() throws {
    #expect(try FixedResponses.spokenDisclosure(.none) == nil)
}
