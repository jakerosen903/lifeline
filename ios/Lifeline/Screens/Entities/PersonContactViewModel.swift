import Foundation
import LifelineKit

/// The contact row on a person's page (PC3, PC4): what it shows, and link, unlink, the suggestion's two answers and
/// the way to give access. The row is nil on the owner's page and on any page that is not a person's.
@MainActor
@Observable
final class PersonContactViewModel {
    /// Nil: the page shows no row.
    private(set) var state: PersonContactState?
    /// The photo the app copied from the contact, for the caption on the first picture.
    private(set) var contactPhotoID: PhotoID?
    /// One fixed sentence after an action that did not go through: a held contact or a failed write. Never an error's text.
    private(set) var message: String?
    /// True while a link runs: the row's buttons wait.
    private(set) var isWorking = false
    /// The person's name, for "That is fine. {name} has a page and stories either way."
    private(set) var personName = ""
    /// Nil on a place, a thing or an idea: they have no person.
    let person: PersonID?
    let deps: Dependencies
    /// Called after a write, so the page reads again (the copied picture joins the photos).
    var onChanged: () -> Void = {}

    init(entity: Entity, deps: Dependencies) {
        person = entity.type == .person ? PersonID(rawValue: entity.id.rawValue) : nil
        self.deps = deps
    }

    var access: ContactsAccess { deps.contacts.access() }

    /// Reads the person, the access and the suggestion. Called by the page's refresh, never from `body`.
    func refresh() {
        guard let person else { state = nil; return }
        let found = try? deps.extractionStore.people.person(id: person)
        let access = self.access
        let canSee = access == .full || access == .limited
        // A failed suggestion read only hides the card; the row still shows.
        let suggestion = canSee && found?.contactIdentifier == nil
            ? (try? deps.contactLinks.suggestion(for: person, in: deps.contactsCache.cards)) ?? nil : nil
        state = PersonContactState.row(for: found, access: access, suggestion: suggestion)
        contactPhotoID = found?.contactPhotoID
        personName = found?.displayName ?? ""
    }

    /// The contacts other people hold, by identifier, with their names: the search says "In a story as {name}".
    func heldByOthers() -> [String: String] {
        let linked = (try? deps.extractionStore.people.linkedPersons()) ?? []
        return Dictionary(linked.filter { $0.id != person }.compactMap { other in other.contactIdentifier.map { ($0, other.displayName) } },
                          uniquingKeysWith: { first, _ in first })
    }

    /// "Link to a contact": with access not asked, the one system prompt first, through the landing's path, so the
    /// "asked" flag and the cache behave the same. True when the search can open; on a no the row reads again.
    func prepareSearch() async -> Bool {
        message = nil
        var access = self.access
        if access == .notAsked { access = await ContactsAccessPrompt(deps: deps).ask() }
        let canSee = access == .full || access == .limited
        if !canSee { refresh() }
        return canSee
    }

    /// A contact picked in the search, or "Yes, link them". The person keeps their name; the row shows the contact's.
    func link(_ card: ContactCard) async {
        guard let person, !isWorking else { return }
        isWorking = true
        message = nil
        let links = deps.contactLinks
        // Off the main actor: the link writes, then reads and stores the contact's picture.
        let failure: Swift.Error? = await Task.detached(priority: .userInitiated) {
            do { try await links.link(person, to: card); return nil } catch { return error }
        }.value
        isWorking = false
        if let failure {
            message = Self.sentence(for: failure, fallback: "Could not link this contact. Try again.")
            Self.log("link", failure)
            return
        }
        onChanged()
    }

    /// "Unlink": no question and no Undo; the owner can link again. Only the link fields go.
    func unlink() {
        guard let person else { return }
        message = nil
        do {
            try deps.contactLinks.unlink(person)
            onChanged()
        } catch {
            message = "Could not unlink this contact. Try again."
            Self.log("unlink", error)
        }
    }

    /// "No, someone else": the card goes, and this contact is not offered for this person again.
    func decline(_ card: ContactCard) {
        guard let person else { return }
        message = nil
        do {
            try deps.contactLinks.decline(card, for: person)
            onChanged()
        } catch {
            message = "Could not save that. Try again."
            Self.log("decline", error)
        }
    }

    /// "Allow contacts in Settings". Under "not asked" the Settings page has no Contacts switch yet, so the app shows
    /// the one system prompt instead (PB46); after it, the row reads again.
    func allowContacts() async {
        message = nil
        if access == .notAsked {
            _ = await ContactsAccessPrompt(deps: deps).ask()
            onChanged()
        } else {
            deps.openSettings()
        }
    }

    /// The held contact names the person who holds it; any other failure is one fixed sentence.
    private static func sentence(for error: Swift.Error, fallback: String) -> String {
        if case ContactLinkActions.Error.heldByAnother(_, let name) = error { return "\(name) is already linked to this contact." }
        return fallback
    }

    /// The error's type only: its text could carry a contact's name, which never goes to the log.
    private static func log(_ action: String, _ error: Swift.Error) {
        print("[contacts] \(action) on a person's page failed: \(type(of: error))")
    }
}
