import Foundation

/// What an entity page says about time and order (M7). Pure.
public enum EntityPage {
    /// Said: "in 1998" or "from 1993 to 1998". A guess: "around 1998" or "between 1993 and 1998"
    /// (Principle 5: a guess never reads as fact). A hedge or a relation the person settled is
    /// not said (`TimeRange.readsAsSaid`). Nothing placed: "no dates yet".
    public static func spanText(_ range: TimeRange) -> String {
        guard range.isPlaced, let first = (range.likelyStart ?? range.earliest)?.year, let last = (range.likelyEnd ?? range.latest)?.year else {
            return "no dates yet"
        }
        let said = range.readsAsSaid
        if first == last { return said ? "in \(first)" : "around \(first)" }
        return said ? "from \(first) to \(last)" : "between \(first) and \(last)"
    }

    /// The person's own words, cleaned for reading, or nil when the cleanup leaves nothing
    /// ("um, uh"). Only these may be shown in quotation marks: a title is not something said.
    public static func ownWordsQuote(of memory: Memory, maxWords: Int? = nil) -> String? {
        let quote = ReadableQuote.text(memory.summaryQuote, maxWords: maxWords)
        return quote.isEmpty ? nil : quote
    }

    /// The text for a row that is not marked as a quote: the person's words, or the memory's
    /// title when there are none, so a row is never blank and VoiceOver never reads an empty label.
    public static func readableQuote(of memory: Memory, maxWords: Int? = nil) -> String {
        ownWordsQuote(of: memory, maxWords: maxWords) ?? memory.title
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

    /// What a page lists besides its strip: what the person said, and the moments in order (S2).
    public struct Sections: Sendable, Equatable {
        public var said: [Memory]
        public var moments: [Memory]
    }

    /// `said` holds the details and the mentions that are not moments, once each, oldest told
    /// first. `moments` holds the mentions that are moments (decision 2), in `ordered` order.
    /// A hidden memory and a floating stand-in (not told) are in neither.
    public static func sections(details: [Memory], mentions: [Memory]) -> Sections {
        func shown(_ memories: [Memory]) -> [Memory] { memories.filter { !$0.hiddenFromTimeline && !$0.isFloating } }
        let shownMentions = shown(mentions)
        var seen = Set<MemoryID>()
        let said = (shown(details) + shownMentions.filter { !$0.isMoment }).filter { seen.insert($0.id).inserted }
            .sorted { ($0.createdAt, $0.id.rawValue) < ($1.createdAt, $1.id.rawValue) }
        return Sections(said: said, moments: ordered(shownMentions.filter(\.isMoment), toldAt: [:]))
    }

    /// Never a guessed gender: the store holds none (decision 4).
    public static func saidHeading(_ type: EntityType, isOwner: Bool) -> String {
        if isOwner { return "What you've said about yourself" }
        return type == .person ? "What you've said about them" : "What you've said about it"
    }

    public static func momentsHeading(title: String, isOwner: Bool) -> String {
        isOwner ? "Your moments" : "Moments with \(title)"
    }

    public static func invitation(title: String, isOwner: Bool) -> String {
        "Stories you tell about \(isOwner ? "yourself" : title) will show here."
    }
}
