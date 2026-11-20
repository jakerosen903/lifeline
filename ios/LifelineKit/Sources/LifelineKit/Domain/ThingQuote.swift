import Foundation

/// The one quote a tile without a photo shows (spec defaults 3, 4 and 5). Pure.
public enum ThingQuote {
    public static let maxWords = 20

    /// `details`: told, visible details of one thing, in any order. Sorted here by `createdAt`, then id.
    /// A detail whose first telling is in a heavy session is skipped. A detail with no telling is not skipped.
    /// The first cleaned quote that is not empty wins.
    public static func choose(details: [Memory], tellings: [MemoryID: Telling], heavySessions: Set<SessionID>) -> String? {
        let ordered = details.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.rawValue < $1.id.rawValue
        }
        for detail in ordered {
            if let telling = tellings[detail.id], heavySessions.contains(telling.sessionID) { continue }
            if let quote = EntityPage.ownWordsQuote(of: detail, maxWords: maxWords) { return quote }
        }
        return nil
    }
}
