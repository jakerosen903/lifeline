import Testing
@testable import LifelineKit

// PC-b Task 7: what a person's contact row shows (PC3, PC4). Names are invented.

private let vale = ContactCard(identifier: "c-vale", fullName: "Robyn Vale", givenName: "Robyn", familyName: "Vale", nickname: "", hasPicture: true)

private func person(contact: String? = nil, name: String? = nil, state: String? = nil, owner: Bool = false) -> Person {
    Person(id: PersonID(rawValue: "p-1"), displayName: "Robyn", notes: nil, isOwner: owner, birthDate: nil, birthDateOrigin: nil,
           contactIdentifier: contact, contactName: name, contactState: state)
}

private let linked = person(contact: "c-vale", name: "Robyn Vale", state: Person.contactLinked)
private let missing = person(contact: "c-vale", name: "Robyn Vale", state: Person.contactMissing)
private let unlinked = person()

@Test(arguments: [ContactsAccess.full, .limited])
func aLinkedPersonShowsTheContactsName(access: ContactsAccess) {
    #expect(PersonContactState.of(linked, access: access, suggestion: nil) == .linked(contactName: "Robyn Vale"))
    #expect(PersonContactState.of(linked, access: access, suggestion: vale) == .linked(contactName: "Robyn Vale"),
            "a person with a contact is offered nothing")
}

@Test(arguments: [ContactsAccess.full, .limited])
func aMissingContactCanBeLinkedAgainUnderAccess(access: ContactsAccess) {
    #expect(PersonContactState.of(missing, access: access, suggestion: nil) == .missing(contactName: "Robyn Vale", canSeeContacts: true))
}

@Test(arguments: [ContactsAccess.denied, .notAsked])
func withoutAccessALinkedPersonIsMissingAndTheAppCannotCheck(access: ContactsAccess) {
    #expect(PersonContactState.of(linked, access: access, suggestion: nil) == .missing(contactName: "Robyn Vale", canSeeContacts: false))
    #expect(PersonContactState.of(missing, access: access, suggestion: nil) == .missing(contactName: "Robyn Vale", canSeeContacts: false))
}

@Test func aContactWithNoStateReadsAsLinked() {
    // Every write sets the state with the identifier; a row with none is treated as the link it holds.
    #expect(PersonContactState.of(person(contact: "c-vale", name: "Robyn Vale"), access: .full, suggestion: nil) == .linked(contactName: "Robyn Vale"))
}

@Test func aContactWithNoKeptNameShowsThePersonsName() {
    #expect(PersonContactState.of(person(contact: "c-vale", state: Person.contactLinked), access: .full, suggestion: nil) == .linked(contactName: "Robyn"))
}

@Test func deniedWithNoContactIsTheNoAccessCard() {
    #expect(PersonContactState.of(unlinked, access: .denied, suggestion: vale) == .noAccess)
}

@Test(arguments: [ContactsAccess.full, .limited])
func noContactUnderAccessIsNotLinkedWithTheSuggestion(access: ContactsAccess) {
    #expect(PersonContactState.of(unlinked, access: access, suggestion: vale) == .notLinked(suggestion: vale))
    #expect(PersonContactState.of(unlinked, access: access, suggestion: nil) == .notLinked(suggestion: nil))
}

@Test func noContactNotAskedIsNotLinkedWithNoSuggestion() {
    #expect(PersonContactState.of(unlinked, access: .notAsked, suggestion: vale) == .notLinked(suggestion: nil))
}

@Test func theOwnerAPlaceAndAThingGetNoRow() {
    #expect(PersonContactState.row(for: person(owner: true), access: .full, suggestion: nil) == nil)
    #expect(PersonContactState.row(for: person(contact: "c-vale", name: "Robyn Vale", state: Person.contactLinked, owner: true),
                                   access: .full, suggestion: nil) == nil)
    #expect(PersonContactState.row(for: nil, access: .full, suggestion: nil) == nil, "a place or a thing has no person")
    #expect(PersonContactState.row(for: unlinked, access: .denied, suggestion: nil) == .noAccess)
}
