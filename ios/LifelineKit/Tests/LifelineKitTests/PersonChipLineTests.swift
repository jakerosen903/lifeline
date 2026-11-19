import Testing
@testable import LifelineKit

@Test func chipLines() {
    #expect(PersonChipLine.text(origin: .assumed, saidName: "Robin", fromContact: false, contacts: .none) == "Assumed \u{00B7} you said \u{201C}Robin\u{201D}")
    #expect(PersonChipLine.text(origin: .new, saidName: "Tomas", fromContact: false, contacts: .none) == "New")
    #expect(PersonChipLine.text(origin: .said, saidName: "Danielle", fromContact: false, contacts: .none) == nil)
    #expect(PersonChipLine.text(origin: .confirmed, saidName: "Robin", fromContact: false, contacts: .none) == nil)
    #expect(PersonChipLine.text(origin: nil, saidName: "Maya", fromContact: false, contacts: .none) == nil)          // an older link: no mark
    #expect(PersonChipLine.landingLine(guesses: 0) == nil)
    #expect(PersonChipLine.landingLine(guesses: 1) == "I made one guess about who you meant.")
    #expect(PersonChipLine.landingLine(guesses: 2) == "I made 2 guesses about who you meant.")
    #expect(PersonChipLine.accessibilityLabel(name: "Robin Okafor", origin: .assumed, saidName: "Robin")
            == "Robin Okafor, assumed, you said Robin. Change who this is.")
}

@Test func aChipWithoutAWordForTheSaidNameStillSaysAssumed() {
    // Ochre always comes with a word, even when the said name is missing or blank.
    #expect(PersonChipLine.text(origin: .assumed, saidName: nil, fromContact: false, contacts: .none) == "Assumed")
    #expect(PersonChipLine.text(origin: .assumed, saidName: "  ", fromContact: false, contacts: .none) == "Assumed")
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

// M-2 (fix wave): a refused change says what happened. Nothing changed for `notFound`, so it is not the stale sentence.
@Test func aRefusedChangeSaysWhy() {
    #expect(PersonChipLine.refusal(.stale) == "That changed since. Open the name to change it again.")
    #expect(PersonChipLine.refusal(.notFound) == "That person is not here any more.")
}

@Test func theConfirmButtonUsesTheFirstWordOfTheName() {
    #expect(PersonChipLine.confirmLabel(name: "Robyn Vale") == "Yes, this Robyn")
    #expect(PersonChipLine.confirmLabel(name: "Robyn") == "Yes, this Robyn")
    #expect(PersonChipLine.confirmLabel(name: "  Robyn   Vale ") == "Yes, this Robyn")
    #expect(PersonChipLine.confirmLabel(name: "") == "Yes, this person")
    #expect(PersonChipLine.confirmLabel(name: "   ") == "Yes, this person")
}

// M1 / R37: a name marked "Not a person" on a waiting card keeps a quiet chip, so the sheet opens again.
@Test func aNotAPersonChipReadsTheSaidName() {
    #expect(PersonChipLine.notAPersonLabel(saidName: "Tomas") == "Tomas, not a person. Change who this is.")
    #expect(PersonChipLine.notAPersonLabel(saidName: "  the fence  ") == "the fence, not a person. Change who this is.")
}

// PC-b Task 2: the lines for a person from the contacts and a new name the contacts were checked for.
@Test func chipLinesForContacts() {
    #expect(PersonChipLine.text(origin: .assumed, saidName: "Robyn", fromContact: true, contacts: .someMatch) == "Assumed \u{00B7} new, from your contacts")
    #expect(PersonChipLine.text(origin: .assumed, saidName: "Robyn", fromContact: true, contacts: .none) == "Assumed \u{00B7} new, from your contacts")
    #expect(PersonChipLine.text(origin: .new, saidName: "Tomas", fromContact: false, contacts: .noMatch) == "New \u{00B7} not in your contacts")
    #expect(PersonChipLine.text(origin: .new, saidName: "Robyn", fromContact: false, contacts: .someMatch) == "New \u{00B7} not linked yet")
    #expect(PersonChipLine.text(origin: .new, saidName: "Tomas", fromContact: false, contacts: .none) == "New", "without the contacts the line says nothing about them")
    // A link the owner made or settled has no line, whatever the person came from.
    #expect(PersonChipLine.text(origin: .confirmed, saidName: "Robyn", fromContact: true, contacts: .someMatch) == nil)
    #expect(PersonChipLine.text(origin: .said, saidName: "Robyn", fromContact: true, contacts: .someMatch) == nil)
}

@Test func aChipFromTheContactsReadsItsLineAloud() {
    #expect(PersonChipLine.accessibilityLabel(name: "Robyn Vale", origin: .assumed, saidName: "Robyn", fromContact: true)
            == "Robyn Vale, assumed, new, from your contacts. Change who this is.")
    #expect(PersonChipLine.accessibilityLabel(name: "Robyn Vale", origin: .confirmed, saidName: "Robyn", fromContact: true)
            == "Robyn Vale. Change who this is.")
}
