import Foundation

/// One memory linked to an entity, with when it happened (the life strip's raw material).
public struct LinkedTime: Sendable, Equatable {
    public var memoryID: MemoryID
    public var range: TimeRange
    /// A told moment the entity is named in: an event or other, not hidden, with a candidate,
    /// linked by `mention`. Everything else linked (a detail, a fact) only widens the span.
    public var isMoment: Bool

    public init(memoryID: MemoryID, range: TimeRange, isMoment: Bool) {
        self.memoryID = memoryID; self.range = range; self.isMoment = isMoment
    }
}

/// Another entity that appears in moments beside this one.
public struct CoOccurrence: Sendable, Equatable {
    public var entity: Entity
    public var sharedMoments: Int

    public init(entity: Entity, sharedMoments: Int) {
        self.entity = entity; self.sharedMoments = sharedMoments
    }
}

/// What a tile or a page header needs about an entity, read in a fixed number of queries.
public struct EntitySummary: Sendable, Equatable, Identifiable {
    public var entity: Entity
    public var ownWords: String?
    /// One range per moment, unplaced ones included, oldest told first.
    public var momentRanges: [TimeRange]
    /// The stated span, else the derived one.
    public var span: TimeRange

    public init(entity: Entity, ownWords: String?, momentRanges: [TimeRange], span: TimeRange) {
        self.entity = entity; self.ownWords = ownWords; self.momentRanges = momentRanges; self.span = span
    }

    public var id: EntityID { entity.id }
    public var momentCount: Int { momentRanges.count }

    /// The earliest `likelyStart ?? earliest` over the placed moments.
    public var firstDate: CivilDate? {
        momentRanges.filter(\.isPlaced).compactMap { $0.likelyStart ?? $0.earliest }.min()
    }
}

/// The words the person used for someone ("my sister"), chosen from what the store holds.
public enum OwnWords {
    private static let barePronouns: Set<String> = ["he", "she", "they", "him", "her", "them", "i", "me", "we", "us", "it"]

    /// A relation alias ("my ...", "our ...") first. Else the role text said most often, never
    /// the name itself or a bare pronoun. Else nil: the tile keeps an empty line.
    public static func choose(title: String, aliases: [String], roleTexts: [String]) -> String? {
        let trimmed = aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let relation = PeopleRepository.relationLabel(texts: trimmed) { return relation }
        let name = PeopleRepository.normalize(title)
        var counts: [String: (count: Int, text: String)] = [:]
        for raw in roleTexts {
            let key = PeopleRepository.normalize(raw)
            guard !key.isEmpty, key != name, !barePronouns.contains(key) else { continue }
            let seen = counts[key]
            counts[key] = ((seen?.count ?? 0) + 1, seen?.text ?? raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Equal counts go to the alphabetically first, so the choice never varies.
        return counts.min { ($1.value.count, $0.key) < ($0.value.count, $1.key) }?.value.text
    }
}
