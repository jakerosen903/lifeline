import Foundation
import LifelineKit

/// The one system prompt for contacts (spec, "Access"), and what follows a yes on a recording's landing
/// (plan decision 7). The app asks once: "asked before" is kept in `UserDefaults`, set as the prompt shows,
/// so a kill while the prompt is up does not ask again. `-uiTesting` clears it at launch.
@MainActor
struct ContactsAccessPrompt {
    nonisolated static let askedKey = "contacts.accessPromptShown"

    let deps: Dependencies

    private var askedBefore: Bool { UserDefaults.standard.bool(forKey: Self.askedKey) }

    /// The landing's question: may it ask now? `keptPeopleInSession` is `PersonLinkRepository.keptPeopleCount(in:)`.
    func shouldAsk(keptPeopleInSession: Int) -> Bool {
        ContactsPromptRule.shouldAsk(access: deps.contacts.access(), askedBefore: askedBefore, keptPeopleInSession: keptPeopleInSession)
    }

    /// Shows the system prompt (the system shows it only while it has no answer) and, on full or limited access,
    /// reads the contacts into the cache. Returns the access the owner gave.
    func ask() async -> ContactsAccess {
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        let access = await deps.contacts.requestAccess()
        guard access == .full || access == .limited else { return access }
        await deps.contactsCache.refresh(from: deps.contacts)
        return access
    }

    /// On the landing of `session`: ask, and on a yes look at this recording's new people again and copy the picture
    /// of each person that look linked. Returns true when the landing should read its chips again. A failed look is
    /// logged, never shown: the guesses stay as they were and still read as guesses.
    func askOnLanding(session: SessionID) async -> Bool {
        let access = await ask()
        guard access == .full || access == .limited else { return false }
        let links = deps.contactLinks, contacts = deps.contactsCache.forGuess
        // Off the main actor: the look again writes, and each picture is a contact read and a photo store.
        await Task.detached(priority: .userInitiated) {
            do {
                let result = try await links.reguess(session: session, contacts: contacts)
                for person in result.linkedPeople { try? await links.copyPicture(for: person) }
                print("[contacts] after access: \(result.changedLinks) links to \(result.linkedPeople.count) people")
            } catch {
                print("[contacts] the look again after access failed: \(error)")
            }
        }.value
        return true
    }
}
