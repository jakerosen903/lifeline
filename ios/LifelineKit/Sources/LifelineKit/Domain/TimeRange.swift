import Foundation

public enum Granularity: String, Codable, Sendable, CaseIterable {
    case day, month, season, year, decade, era
}

public enum RangeOrigin: String, Codable, Sendable, CaseIterable {
    case stated, inferred, derived, confirmed
}

/// When something happened, as honestly as the owner's words allow: a possible band
/// (`earliest`...`latest`), an optional likely band inside it, how fine the claim is, where it
/// came from, and the phrase that set it. All dates nil means unplaced.
public struct TimeRange: Codable, Sendable, Equatable {
    public enum Direction: Sendable { case earlier, later }

    public var earliest: CivilDate?
    public var latest: CivilDate?
    public var likelyStart: CivilDate?
    public var likelyEnd: CivilDate?
    public var granularity: Granularity?
    public var origin: RangeOrigin?
    public var evidenceText: String?

    public init(earliest: CivilDate?, latest: CivilDate?, likelyStart: CivilDate?, likelyEnd: CivilDate?,
                granularity: Granularity?, origin: RangeOrigin?, evidenceText: String?) {
        self.earliest = earliest; self.latest = latest; self.likelyStart = likelyStart; self.likelyEnd = likelyEnd
        self.granularity = granularity; self.origin = origin; self.evidenceText = evidenceText
    }

    public static let unplaced = TimeRange(earliest: nil, latest: nil, likelyStart: nil, likelyEnd: nil, granularity: nil, origin: nil, evidenceText: nil)

    public static func year(_ year: Int, origin: RangeOrigin, evidence: String?) -> TimeRange {
        TimeRange(earliest: .firstOfYear(year), latest: .lastOfYear(year), likelyStart: nil, likelyEnd: nil,
                  granularity: .year, origin: origin, evidenceText: evidence)
    }

    public static func span(_ from: CivilDate, _ to: CivilDate, granularity: Granularity, origin: RangeOrigin, evidence: String?) -> TimeRange {
        TimeRange(earliest: min(from, to), latest: max(from, to), likelyStart: nil, likelyEnd: nil,
                  granularity: granularity, origin: origin, evidenceText: evidence)
    }

    public var isPlaced: Bool { earliest != nil || latest != nil || likelyStart != nil || likelyEnd != nil }
    public var isConfirmed: Bool { origin == .confirmed }
    /// Stated by the person or confirmed by them: the resolver and the questions leave it alone.
    public var isSettled: Bool { origin == .confirmed || origin == .stated }

    // MARK: - Stated by the person (M4.1: "Tell me when")

    static func clampYear(_ year: Int) -> Int { min(max(year, AnchorPhrase.yearRange.lowerBound), AnchorPhrase.yearRange.upperBound) }

    /// "1998": the whole year, as said.
    public static func stated(year: Int) -> TimeRange {
        let y = clampYear(year)
        return .year(y, origin: .stated, evidence: "\(y)")
    }

    /// "around 1998": a year each side, most likely the year itself.
    public static func stated(around year: Int) -> TimeRange {
        let y = clampYear(year)
        return TimeRange(earliest: .firstOfYear(clampYear(y - 1)), latest: .lastOfYear(clampYear(y + 1)),
                         likelyStart: .firstOfYear(y), likelyEnd: .lastOfYear(y), granularity: .year, origin: .stated, evidenceText: "around \(y)")
    }

    /// "1996–1999": inclusive, in either order.
    public static func stated(between a: Int, and b: Int) -> TimeRange {
        let lo = clampYear(min(a, b)), hi = clampYear(max(a, b))
        return TimeRange.span(.firstOfYear(lo), .lastOfYear(hi), granularity: .year, origin: .stated, evidence: Self.yearSpan(lo, hi))
    }

    /// "about 8": the age band the resolver would give an age anchor, but as the person's word.
    public static func stated(age: AgeSpan, birth: CivilDate, config: ResolverConfig = .default, evidence: String) -> TimeRange {
        var range = Resolver.ageRange(age, birth: birth, config: config, evidence: evidence)
        range.origin = .stated
        return range
    }

    /// The overlap of the two possible bands, or nil when they do not touch. Keeps this range's
    /// granularity, origin and evidence; the likely band is kept only if it still fits.
    public func intersect(_ other: TimeRange) -> TimeRange? {
        guard let a0 = earliest, let a1 = latest, let b0 = other.earliest, let b1 = other.latest else { return nil }
        let lo = max(a0, b0), hi = min(a1, b1)
        guard lo <= hi else { return nil }
        var out = self
        out.earliest = lo
        out.latest = hi
        if let ls = likelyStart, let le = likelyEnd, !(ls >= lo && le <= hi) { out.likelyStart = nil; out.likelyEnd = nil }
        return out
    }

    /// Moves one edge of the possible band outward by whole years. Used for before/after.
    public func widened(by years: Int, toward direction: Direction) -> TimeRange {
        var out = self
        switch direction {
        case .later: out.latest = latest?.adding(years: years)
        case .earlier: out.earliest = earliest?.adding(years: -years)
        }
        return out
    }

    /// The canvases' wording. An inference always reads as a guess; a span derived from members
    /// (a chapter, a collection) reads plainly, as the canvases show "1986 – 2004 · Childhood".
    public var displayText: String {
        guard let earliest, let latest else { return "no date yet" }
        // A confirmed relation ("before Graduation (2004)") is what the owner actually settled;
        // the band's far edge is the builder's slack and is never shown as a fact.
        if origin == .confirmed, let evidenceText, Self.isRelationEvidence(evidenceText) { return evidenceText }
        // "around 1998", "about 8": what the person typed in, shown as said (M4.1).
        if origin == .stated, let evidenceText, Self.isAsSaidEvidence(evidenceText) { return evidenceText }
        let guess = origin == .inferred
        switch granularity ?? .year {
        case .day:
            return (guess ? "around " : "") + "\(earliest.day) \(Self.monthName(earliest.month)) \(earliest.year)"
        case .month:
            return (guess ? "around " : "") + "\(Self.monthName(earliest.month)) \(earliest.year)"
        case .season:
            return (guess ? "around " : "") + Self.seasonName(startMonth: earliest.month) + " \(earliest.year)"
        case .decade:
            return "sometime in the \(earliest.year / 10 * 10)s"
        case .era:
            return "sometime in \(evidenceText ?? "\(earliest.year)–\(latest.year)")"
        case .year:
            if let ls = likelyStart, let le = likelyEnd, (ls.year, le.year) != (earliest.year, latest.year) {
                return "probably " + Self.yearSpan(ls.year, le.year)
            }
            let span = Self.yearSpan(earliest.year, latest.year)
            // A guess that fits in two calendar years (an age band from a mid-year birthday) is
            // still "around"; wider than that it is honestly "sometime between".
            return guess ? (latest.year - earliest.year <= 1 ? "around \(span)" : "sometime between \(span)") : span
        }
    }

    static func isAsSaidEvidence(_ text: String) -> Bool {
        ["around ", "about "].contains { text.lowercased().hasPrefix($0) }
    }

    static func isRelationEvidence(_ text: String) -> Bool {
        ["before ", "after ", "not the same year as ", "during "].contains { text.lowercased().hasPrefix($0) }
    }

    static func yearSpan(_ a: Int, _ b: Int) -> String {
        if a == b { return "\(a)" }
        if a / 100 == b / 100 { return "\(a)–\(String(format: "%02d", b % 100))" }
        return "\(a)–\(b)"
    }

    static func monthName(_ m: Int) -> String {
        ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][max(0, min(11, m - 1))]
    }

    static func seasonName(startMonth: Int) -> String {
        switch startMonth {
        case 3...5: "spring"
        case 6...8: "summer"
        case 9...11: "fall"
        default: "winter"
        }
    }
}
