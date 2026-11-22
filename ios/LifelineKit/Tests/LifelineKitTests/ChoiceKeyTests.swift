import Testing
@testable import LifelineKit

@Suite struct ChoiceKeyTests {
    @Test func withNoHandleTheKeyIsTheSaidName() {
        #expect(ChoiceKey.text(saidName: " My Roommate, Robin ", handle: nil) == SaidName.key("my roommate, robin"))
        #expect(ChoiceKey.text(saidName: "Robin", handle: "") == "robin", "an empty handle is no handle")
    }

    @Test func aHandleFollowsTheSaidNameAfterTheSeparator() {
        #expect(ChoiceKey.text(saidName: "Robyn ", handle: "p2") == "robyn\u{1F}p2")
    }

    @Test func twoHandlesOfOneNameHaveTwoKeys() {
        #expect(ChoiceKey.text(saidName: "Robyn", handle: "p1") != ChoiceKey.text(saidName: "Robyn", handle: "p2"))
        #expect(ChoiceKey.text(saidName: "Robyn", handle: "p1") != ChoiceKey.text(saidName: "Robyn", handle: nil))
    }
}
