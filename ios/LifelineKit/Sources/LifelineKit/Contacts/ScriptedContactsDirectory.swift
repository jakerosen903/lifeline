import Foundation
import Synchronization

/// A directory the test or the UI-test mode scripts. It never touches the system.
public final class ScriptedContactsDirectory: ContactsDirectory {
    public struct ReadFailure: Error, Equatable { public init() {} }

    private struct State {
        var cards: [ContactCard]
        var pictures: [String: Data]
        var access: ContactsAccess
        var accessAfterRequest: ContactsAccess
        var failsOnRead = false
        var merged: [String: String] = [:]
        var allReads = 0
    }
    private let box: Mutex<State>

    public init(cards: [ContactCard] = [], pictures: [String: Data] = [:], access: ContactsAccess = .full,
                accessAfterRequest: ContactsAccess? = nil) {
        box = Mutex(State(cards: cards, pictures: pictures, access: access, accessAfterRequest: accessAfterRequest ?? access))
    }

    public var cards: [ContactCard] {
        get { box.withLock { $0.cards } }
        set { box.withLock { $0.cards = newValue } }
    }
    public var pictures: [String: Data] {
        get { box.withLock { $0.pictures } }
        set { box.withLock { $0.pictures = newValue } }
    }
    public var currentAccess: ContactsAccess {
        get { box.withLock { $0.access } }
        set { box.withLock { $0.access = newValue } }
    }
    /// What `requestAccess()` will answer, and then keep as the access.
    public var accessAfterRequest: ContactsAccess {
        get { box.withLock { $0.accessAfterRequest } }
        set { box.withLock { $0.accessAfterRequest = newValue } }
    }
    /// When true, `all()`, `cards(identifiers:)` and `picture(identifier:)` throw.
    public var failsOnRead: Bool {
        get { box.withLock { $0.failsOnRead } }
        set { box.withLock { $0.failsOnRead = newValue } }
    }

    /// A card the system merged into another: the old identifier → the identifier of the card that holds it now.
    /// `cards(identifiers:)` and `picture(identifier:)` answer an old identifier with that card, as the system does.
    public var merged: [String: String] {
        get { box.withLock { $0.merged } }
        set { box.withLock { $0.merged = newValue } }
    }
    /// How many times `all()` has been called.
    public var allReads: Int { box.withLock { $0.allReads } }

    public func access() -> ContactsAccess { currentAccess }

    public func requestAccess() async -> ContactsAccess {
        box.withLock {
            $0.access = $0.accessAfterRequest
            return $0.access
        }
    }

    public func all() async throws -> [ContactCard] {
        let snapshot = box.withLock { state in
            state.allReads += 1
            return state
        }
        if snapshot.failsOnRead { throw ReadFailure() }
        switch snapshot.access {
        case .full, .limited: return snapshot.cards
        case .notAsked, .denied: return []
        }
    }

    /// Under `notAsked` or `denied` the system answers nothing, so neither does this.
    public func cards(identifiers: [String]) async throws -> [ContactCard] {
        let snapshot = box.withLock { $0 }
        if snapshot.failsOnRead { throw ReadFailure() }
        guard snapshot.access.canRead else { return [] }
        var found: [ContactCard] = []
        for identifier in identifiers {
            let current = snapshot.merged[identifier] ?? identifier
            if let card = snapshot.cards.first(where: { $0.identifier == current }), !found.contains(card) { found.append(card) }
        }
        return found
    }

    public func picture(identifier: String) async throws -> Data? {
        let snapshot = box.withLock { $0 }
        if snapshot.failsOnRead { throw ReadFailure() }
        guard snapshot.access.canRead else { return nil }
        return snapshot.pictures[snapshot.merged[identifier] ?? identifier]
    }
}

private extension ContactsAccess {
    var canRead: Bool { self == .full || self == .limited }
}
