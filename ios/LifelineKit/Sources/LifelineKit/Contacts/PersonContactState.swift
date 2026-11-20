import Foundation

/// What the contact row on a person's page shows (PC3, PC4). Pure.
public enum PersonContactState: Equatable, Sendable {
    /// "Linked to {contact name} in your contacts", with "Change".
    case linked(contactName: String)
    /// The person holds a contact the app cannot find now. With `canSeeContacts` false the app has no access, so it
    /// cannot check: the row names the contact and offers Settings. Nothing is unlinked either way.
    case missing(contactName: String, canSeeContacts: Bool)
    /// "Not linked to a contact", with "Link to a contact", and the PC4 card when one contact fits.
    case notLinked(suggestion: ContactCard?)
    /// Access denied, and the person has no contact: the PC4 card "If the app cannot see your contacts".
    case noAccess

    /// The row for `person`. A suggestion shows only under access: without it the app has no contacts to offer.
    public static func of(_ person: Person, access: ContactsAccess, suggestion: ContactCard?) -> PersonContactState {
        let canSee = access == .full || access == .limited
        guard person.contactIdentifier != nil else {
            if access == .denied { return .noAccess }
            return .notLinked(suggestion: canSee ? suggestion : nil)
        }
        // Every write keeps the contact's name; a row without one falls back to the person's own name.
        let name = person.contactName ?? person.displayName
        guard canSee else { return .missing(contactName: name, canSeeContacts: false) }
        // A row with no state holds an identifier all the same: it reads as linked until the check says otherwise.
        if person.contactState == Person.contactMissing { return .missing(contactName: name, canSeeContacts: true) }
        return .linked(contactName: name)
    }

    /// The row on an entity page, or nil when the page has none: the owner's own page, and a place or a thing
    /// (which has no person, so the caller passes nil).
    public static func row(for person: Person?, access: ContactsAccess, suggestion: ContactCard?) -> PersonContactState? {
        guard let person, !person.isOwner else { return nil }
        return of(person, access: access, suggestion: suggestion)
    }
}
