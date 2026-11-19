import Testing
@testable import LifelineKit

@Suite struct SaidNameTests {
    @Test func saidNameParts() {
        let said = SaidName(ref: "my mom, Marcel")
        #expect(said.name == "Marcel")
        #expect(said.relation == "my mom")
        #expect(said.raw == "my mom, Marcel")
    }

    @Test func saidNameFromMention() {
        let said = SaidName(ref: "Robin", mentionRelation: "my roommate")
        #expect(said.name == "Robin")
        #expect(said.relation == "my roommate")
    }

    @Test func saidRelationOnly() {
        let said = SaidName(ref: "my mom")
        #expect(said.name == nil)
        #expect(said.relation == "my mom")
    }

    @Test func aMentionRelationThatIsNotARelationPhraseIsIgnored() {
        #expect(SaidName(ref: "Robin", mentionRelation: "roommate").relation == nil)
    }

    @Test func keyFoldsCaseSpaceAndDiacritics() {
        #expect(SaidName.key("  José  Ñandú ") == "jose nandu")
        #expect(SaidName.key("") == "")
    }
}
