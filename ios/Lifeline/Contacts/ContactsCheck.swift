import Foundation
import LifelineKit

/// The check of linked contacts (spec, "A contact that changes"): at launch, after the first screen shows, and each
/// time the system says contacts changed. It reads the contacts into the cache, then runs `ContactLinkActions.check()`.
/// One check runs at a time; a request while one runs makes one more run after it, so a burst of notices is one
/// more check, not many. A failure is logged and never shown; it never stops launch, and the next request tries again.
actor ContactsCheck {
    /// Posted on the main thread after each check, so an open person's page reads its contact row again.
    static let finished = Notification.Name("ContactsCheck.finished")

    private let deps: Dependencies
    private var running = false
    private var again = false

    init(deps: Dependencies) { self.deps = deps }

    func request() async {
        guard !running else { again = true; return }
        running = true
        repeat {
            again = false
            await deps.contactsCache.refresh(from: deps.contacts)
            do {
                try await deps.contactLinks.check()
            } catch {
                // The error's type only: its text could carry a contact's name, which never goes to the log.
                print("[contacts] check failed: \(type(of: error))")
            }
        } while again
        running = false
        await MainActor.run { NotificationCenter.default.post(name: Self.finished, object: nil) }
    }
}
