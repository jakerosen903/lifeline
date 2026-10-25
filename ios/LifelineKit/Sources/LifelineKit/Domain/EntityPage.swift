import Foundation

/// What an entity page says about time and order (M7). Pure.
public enum EntityPage {
    /// "from 1993 to 1998", "around 1998" (a guess), "in 1998" (said), or "no dates yet".
    public static func spanText(_ range: TimeRange) -> String {
        guard range.isPlaced, let first = (range.likelyStart ?? range.earliest)?.year, let last = (range.likelyEnd ?? range.latest)?.year else {
            return "no dates yet"
        }
        if first == last { return range.origin == .stated || range.origin == .confirmed ? "in \(first)" : "around \(first)" }
        return "from \(first) to \(last)"
    }

    /// An idea's page reads top to bottom (Goal 4): everything linked, details and moments, by
    /// its range when it has one and by when it was told otherwise; dated before undated at a tie.
    public static func ordered(_ memories: [Memory], toldAt: [MemoryID: Date]) -> [Memory] {
        func key(_ m: Memory) -> Date {
            if let start = m.range.likelyStart ?? m.range.earliest,
               let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: start.year, month: start.month, day: start.day).date {
                return date
            }
            return toldAt[m.id] ?? m.createdAt
        }
        return memories.sorted { a, b in
            let ka = key(a), kb = key(b)
            return ka != kb ? ka < kb : a.createdAt < b.createdAt
        }
    }
}
