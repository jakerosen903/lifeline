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

    /// The canvases' wording. A guess always reads as a guess.
    public var displayText: String {
        guard let earliest, let latest else { return "no date yet" }
        let guess = origin == .inferred || origin == .derived
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
            return guess ? (earliest.year == latest.year ? "around \(span)" : "sometime between \(span)") : span
        }
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
