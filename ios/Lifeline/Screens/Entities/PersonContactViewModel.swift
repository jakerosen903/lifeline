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
    /// The access read at the last refresh, for the button's wording; actions read it again.
    private(set) var access: ContactsAccess = .notAsked
    /// True while a link runs: the row's buttons wait.
    private(set) var isWorking = false
    /// The person's name, for "That is fine. {name} has a page and stories either way."
    private(set) var personName = ""
    /// Nil on a place, a thing or an idea: they have no person.
    let person: PersonID?
    let deps: Dependencies
    /// Called after a write, so the page reads again (the copied picture joins the photos).
    var onChanged: () -> Void = {}
    /// Puts one fixed sentence in the page's pinned message slot (PB50): a held contact or a failed write.
    var onMessage: (String) -> Void = { _ in }
    /// An action began: a message still showing goes.
    var onClearMessage: () -> Void = {}

    init(entity: Entity, deps: Dependencies) {
        person = entity.type == .person ? PersonID(rawValue: entity.id.rawValue) : nil
        self.deps = deps
    }

    /// Reads the person, the access and the suggestion. Called by the page's refresh, never from `body`.
    func refresh() {
        guard let person else { state = nil; return }
        // A failed read hides the row (`row(for: nil)`): a row built on a guess could offer a link the person already has.
        let found = try? deps.extractionStore.people.person(id: person)
        let access = deps.contacts.access()
        self.access = access
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
        onClearMessage()
        var access = deps.contacts.access()
        if access == .notAsked { access = await askAccess() }
        let canSee = access == .full || access == .limited
        if !canSee { refresh() }
        return canSee
    }

    /// A contact picked in the search, or "Yes, link them". The person keeps their name; the row shows the contact's.
    func link(_ card: ContactCard) async {
        guard let person, !isWorking else { return }
        isWorking = true
        onClearMessage()
        let links = deps.contactLinks
        // Off the main actor: the link writes, then reads and stores the contact's picture.
        let failure: Swift.Error? = await Task.detached(priority: .userInitiated) {
            do { try await links.link(person, to: card); return nil } catch { return error }
        }.value
        isWorking = false
        if let failure {
            onMessage(ContactLinkMessage.sentence(for: failure, fallback: "Could not link this contact. Try again."))
            Self.log("link", failure)
            return
        }
        onChanged()
    }

    /// "Unlink": no question and no Undo; the owner can link again. Only the link fields go.
    func unlink() {
        guard let person else { return }
        onClearMessage()
        do {
            try deps.contactLinks.unlink(person)
            onChanged()
        } catch {
            onMessage(ContactLinkMessage.sentence(for: error, fallback: "Could not unlink this contact. Try again."))
            Self.log("unlink", error)
        }
    }

    /// "No, someone else": the card goes, and this contact is not offered for this person again.
    func decline(_ card: ContactCard) {
        guard let person else { return }
        onClearMessage()
        do {
            try deps.contactLinks.decline(card, for: person)
            onChanged()
        } catch {
            onMessage(ContactLinkMessage.sentence(for: error, fallback: "Could not save that. Try again."))
            Self.log("decline", error)
        }
    }

    /// "Allow contacts in Settings" under denied opens Settings. "Allow contacts", for a person with a contact while
    /// access was never asked, shows the one system prompt (PB51): Settings has no Contacts switch yet. Then the page reads again.
    func allowContacts() async {
        onClearMessage()
        if deps.contacts.access() == .notAsked {
            _ = await askAccess()
            onChanged()
        } else {
            deps.openSettings()
        }
    }

    /// The one system prompt, through the landing's path (same flag and cache). On a yes, the app's contacts check runs
    /// now, as at launch, so a linked contact that no longer resolves is found at once.
    private func askAccess() async -> ContactsAccess {
        let access = await ContactsAccessPrompt(deps: deps).ask()
        if access == .full || access == .limited { NotificationCenter.default.post(name: ContactsCheck.requested, object: nil) }
        return access
    }

    /// The error's type only: its text could carry a contact's name, which never goes to the log.
    private static func log(_ action: String, _ error: Swift.Error) {
        print("[contacts] \(action) on a person's page failed: \(type(of: error))")
    }
}
