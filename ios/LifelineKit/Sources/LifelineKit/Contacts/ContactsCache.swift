import Foundation
import Synchronization

/// The contacts' names, held in memory for name matching. Never saved, never sent anywhere.
public final class ContactsCache: Sendable {
    private let stored = Mutex<[ContactCard]>([])

    public init() {}

    public var cards: [ContactCard] { stored.withLock { $0 } }
    public var forGuess: [PersonGuess.Contact] { cards.map(\.forGuess) }

    public func replace(with cards: [ContactCard]) { stored.withLock { $0 = cards } }

    /// Without access the cache is empty. A thrown read keeps the old cards: a failed read says nothing about the contacts.
    public func refresh(from directory: any ContactsDirectory) async {
        switch directory.access() {
        case .notAsked, .denied:
            replace(with: [])
        case .full, .limited:
            guard let fresh = try? await directory.all() else { return }
            replace(with: fresh)
        }
    }
}
