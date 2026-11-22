import Testing
@testable import LifelineKit

/// The text "Add a photo" gives to the system picker's search: a contact's name only while the contact is linked
/// and in view, the page's name for every other person, and nothing for the owner or a page that is not a person.

@Test(arguments: [
    (EntityType.person, false, "Robin", PersonContactState.linked(contactName: "Robin Okafor") as PersonContactState?, "Robin Okafor" as String?),
    (.person, false, "Robin", .missing(contactName: "Robin Okafor", canSeeContacts: true), "Robin"),
    (.person, false, "Robin", .missing(contactName: "Robin Okafor", canSeeContacts: false), "Robin"),
    (.person, false, "Robin", .notLinked(suggestion: nil), "Robin"),
    (.person, false, "Robin", .noAccess, "Robin"),
    (.person, false, "Robin", nil, "Robin"),
    (.person, true, "Jordan", nil, nil),
    (.place, false, "Alder Street", nil, nil),
    (.person, false, "   ", nil, nil),
    (.person, false, "Robin", .linked(contactName: "  "), "Robin"),
    (.person, false, " Sam O'Neil ", nil, "Sam O'Neil"),
])
func searchName(type: EntityType, isOwner: Bool, title: String, contact: PersonContactState?, expected: String?) {
    #expect(PhotoSearchName.text(type: type, isOwner: isOwner, title: title, contact: contact) == expected)
}
