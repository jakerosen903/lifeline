import Testing
@testable import LifelineKit

@Test func chipLines() {
    #expect(PersonChipLine.text(origin: .assumed, saidName: "Robin") == "Assumed \u{00B7} you said \u{201C}Robin\u{201D}")
    #expect(PersonChipLine.text(origin: .new, saidName: "Tomas") == "New")
    #expect(PersonChipLine.text(origin: .said, saidName: "Danielle") == nil)
    #expect(PersonChipLine.text(origin: .confirmed, saidName: "Robin") == nil)
    #expect(PersonChipLine.text(origin: nil, saidName: "Maya") == nil)          // an older link: no mark
    #expect(PersonChipLine.landingLine(guesses: 0) == nil)
    #expect(PersonChipLine.landingLine(guesses: 1) == "I made one guess about who you meant.")
    #expect(PersonChipLine.landingLine(guesses: 2) == "I made 2 guesses about who you meant.")
    #expect(PersonChipLine.accessibilityLabel(name: "Robin Okafor", origin: .assumed, saidName: "Robin")
            == "Robin Okafor, assumed, you said Robin. Change who this is.")
}

@Test func aChipWithoutAWordForTheSaidNameStillSaysAssumed() {
    // Ochre always comes with a word, even when the said name is missing or blank.
    #expect(PersonChipLine.text(origin: .assumed, saidName: nil) == "Assumed")
    #expect(PersonChipLine.text(origin: .assumed, saidName: "  ") == "Assumed")
    #expect(PersonChipLine.accessibilityLabel(name: "Robin Okafor", origin: .assumed, saidName: nil)
            == "Robin Okafor, assumed. Change who this is.")
}

@Test func anUnmarkedChipIsReadAsJustTheName() {
    #expect(PersonChipLine.accessibilityLabel(name: "Maya Lindqvist", origin: nil, saidName: "Maya") == "Maya Lindqvist. Change who this is.")
    #expect(PersonChipLine.accessibilityLabel(name: "Maya Lindqvist", origin: .said, saidName: "Maya") == "Maya Lindqvist. Change who this is.")
}

@Test func theMoveNoticeNamesThePersonOrSaysNotAPerson() {
    #expect(PersonChipLine.movedNotice(newName: "Robyn Hale") == "Changed to Robyn Hale.")
    #expect(PersonChipLine.movedNotice(newName: "") == "Not a person.")      // the receipt of "Not a person" has no name
    #expect(PersonChipLine.movedNotice(newName: "  ") == "Not a person.")
    #expect(PersonChipLine.staleUndo == "That changed since. Open the name to change it again.")
    #expect(PersonChipLine.failedUndo == "Could not undo that.")
}
