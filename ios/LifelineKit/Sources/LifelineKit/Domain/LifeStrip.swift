import Foundation

/// The strip at the top of an entity page: where its moments fall between the person's birth
/// and now, and one sentence that says the same in words. Pure; it stores nothing.
/// A guess never reads as fact: a guessed mark is hollow, and a guessed date in the sentence
/// carries "around", "between" or "about".
public struct LifeStrip: Sendable, Equatable {
    public struct Mark: Sendable, Equatable {
        /// 0...1 along the axis.
        public var position: Double
        public var isGuess: Bool
        public init(position: Double, isGuess: Bool) { self.position = position; self.isGuess = isGuess }
    }

    public let startYear: Int
    /// The current year.
    public let endYear: Int
    /// Dated moments only, in input order.
    public let marks: [Mark]
    /// Positions on the axis; only when the person stated a span.
    public let statedSpan: ClosedRange<Double>?
    /// Nil when there are no moments.
    public let sentence: String?

    public var showsAxis: Bool { marks.count >= 2 }

    public init(moments: [TimeRange], stated: TimeRange = .unplaced, birthYear: Int?, currentYear: Int) {
        let dated = moments.compactMap(Dated.init)
        var start = min(birthYear ?? .max, dated.map(\.startYear).min() ?? .max)
        if start == .max { start = currentYear }
        // The axis covers whole years, inclusive of the current one. It is never empty.
        let width = Double(max(currentYear + 1 - start, 1))
        func position(_ year: Double) -> Double { min(max((year - Double(start)) / width, 0), 1) }

        self.startYear = start
        self.endYear = currentYear
        self.marks = dated.map { Mark(position: position($0.middle), isGuess: $0.isGuess) }
        if let from = (stated.earliest ?? stated.likelyStart)?.year, let to = (stated.latest ?? stated.likelyEnd)?.year {
            self.statedSpan = position(Double(from))...position(Double(to + 1))
        } else {
            self.statedSpan = nil
        }
        self.sentence = Self.sentence(count: moments.count, dated: dated)
    }

    // MARK: - Dated moments

    /// A moment that has a year: its band runs from its likely start (or earliest) to its likely end (or latest).
    private struct Dated {
        let startYear: Int
        let endYear: Int
        let isGuess: Bool
        let range: TimeRange

        init?(_ range: TimeRange) {
            guard let start = (range.likelyStart ?? range.earliest ?? range.latest)?.year,
                  let end = (range.likelyEnd ?? range.latest ?? range.earliest)?.year else { return nil }
            startYear = min(start, end)
            endYear = max(start, end)
            isGuess = !range.isSettled
            self.range = range
        }

        /// The centre of the band, in whole years: the year 1999 spans 1999.0 to 2000.0.
        var middle: Double { (Double(startYear) + Double(endYear) + 1) / 2 }
    }

    // MARK: - The sentence

    private static func sentence(count: Int, dated: [Dated]) -> String? {
        guard count > 0 else { return nil }
        let counted = count == 1 ? "In one moment" : "In \(count) moments"
        guard let phrase = phrase(for: dated) else { return counted }
        return "\(counted), \(phrase)"
    }

    private static func phrase(for dated: [Dated]) -> String? {
        guard let first = dated.first else { return nil }
        if dated.count == 1 { return EntityPage.spanText(first.range) }

        let from = dated.map(\.startYear).min()!, to = dated.map(\.endYear).max()!
        let anyGuess = dated.contains(where: \.isGuess)
        if dated.count >= 5, let window = tightestWindow(of: dated.map(\.startYear).sorted(), whole: to - from), window.lowerBound < window.upperBound {
            return anyGuess ? "most between about \(window.lowerBound) and \(window.upperBound)" : "most between \(window.lowerBound) and \(window.upperBound)"
        }
        let origin: RangeOrigin = anyGuess ? .inferred : .stated
        return EntityPage.spanText(.span(.firstOfYear(from), .lastOfYear(to), granularity: .year, origin: origin, evidence: nil))
    }

    /// The narrowest run of at least two thirds of the years, if it is at most half of the whole range wide.
    private static func tightestWindow(of sortedYears: [Int], whole: Int) -> ClosedRange<Int>? {
        let n = sortedYears.count
        let needed = (2 * n + 2) / 3   // ceil(2n / 3)
        var best: ClosedRange<Int>?
        for i in 0...(n - needed) {
            let window = sortedYears[i]...sortedYears[i + needed - 1]
            if best == nil || window.upperBound - window.lowerBound < best!.upperBound - best!.lowerBound { best = window }
        }
        guard let best, (best.upperBound - best.lowerBound) * 2 <= whole else { return nil }
        return best
    }
}
