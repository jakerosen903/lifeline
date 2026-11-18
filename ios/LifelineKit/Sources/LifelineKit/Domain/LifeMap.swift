/// Every chapter as a bar on one year axis. Pure: it stores nothing. A chapter with stated years
/// gets a row; one without gets an entry in `unplaced`. A member's date never places a chapter.
public struct LifeMap: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let id: ChapterID
        public let title: String
        /// 0...1 along the axis.
        public let start: Double
        /// 0...1; 1 when the chapter has no stated end, or ends after the axis.
        public let end: Double
        public let yearsText: String
        public let momentCount: Int
        /// The chapter has no stated end; one that ends after now still has an end.
        public let isOpenEnded: Bool
    }

    public struct Band: Sendable, Equatable {
        public let name: String
        public let start: Double
        public let end: Double
    }

    public struct Unplaced: Sendable, Equatable, Identifiable {
        public let id: ChapterID
        public let title: String
        public let momentCount: Int
    }

    public static let untitled = "No name yet"

    public let startYear: Int
    public let endYear: Int
    public let rows: [Row]
    public let periods: [Band]
    public let unplaced: [Unplaced]
    /// Every fifth year inside the axis, for the labels.
    public let axisYears: [Int]

    public var isEmpty: Bool { rows.isEmpty && unplaced.isEmpty }

    /// The axis starts at the earliest of the birth year and every stated first year, and ends at
    /// `currentYear`. A year is one unit wide, so the axis has `endYear - startYear + 1` units.
    public init(chapters: [Chapter], momentCounts: [ChapterID: Int], birthYear: Int?, currentYear: Int) {
        let placed = chapters.compactMap { chapter in Self.years(of: chapter).map { (chapter, $0) } }
        let start = (placed.map { $0.1.first } + [birthYear].compactMap { $0 }).min() ?? currentYear
        // A chapter dated after now still has a year on the axis: the end never falls before the start.
        let end = max(currentYear, start)
        let units = Double(end - start + 1)
        func position(_ year: Int) -> Double { min(max(Double(year - start) / units, 0), 1) }

        startYear = start
        endYear = end
        rows = placed.enumerated().sorted { a, b in
            let (x, y) = (a.element.1, b.element.1)
            if x.first != y.first { return x.first < y.first }
            let (xl, yl) = (x.last ?? Int.max, y.last ?? Int.max)
            if xl != yl { return xl > yl }
            return a.offset < b.offset
        }.map { _, pair in
            let (chapter, years) = pair
            return Row(id: chapter.id, title: chapter.name ?? Self.untitled,
                       start: position(years.first),
                       end: years.last.map { position($0 + 1) } ?? 1,
                       yearsText: chapter.range.displayText,
                       momentCount: momentCounts[chapter.id] ?? 0,
                       isOpenEnded: years.last == nil)
        }
        unplaced = chapters.filter { Self.years(of: $0) == nil }.map {
            Unplaced(id: $0.id, title: $0.name ?? Self.untitled, momentCount: momentCounts[$0.id] ?? 0)
        }
        axisYears = (start...end).filter { $0 % 5 == 0 }
        periods = Self.bands(from: start, to: end, birthYear: birthYear)
    }

    /// "Maple Street, 1998–2001, 3 moments". No count text for zero.
    public func summary(of row: Row) -> String {
        var parts = [row.title, row.yearsText]
        if row.momentCount == 1 { parts.append("1 moment") }
        else if row.momentCount > 1 { parts.append("\(row.momentCount) moments") }
        return parts.joined(separator: ", ")
    }

    /// The first and last stated year; `last` is nil when no end is stated. Nil without stated years.
    private static func years(of chapter: Chapter) -> (first: Int, last: Int?)? {
        guard let range = chapter.statedYears else { return nil }
        guard let first = (range.earliest ?? range.likelyStart ?? range.latest)?.year else { return nil }
        let last = (range.latest ?? range.likelyEnd)?.year
        return (first, last.map { max($0, first) })
    }

    /// Walks the axis years and joins neighbours that fall in the same period.
    private static func bands(from start: Int, to end: Int, birthYear: Int?) -> [Band] {
        let units = Double(end - start + 1)
        var bands: [Band] = []
        var runStart = start
        var runName = LifePeriod.containing(year: start, birthYear: birthYear).name
        func close(through lastYear: Int) {
            bands.append(Band(name: runName, start: Double(runStart - start) / units, end: Double(lastYear + 1 - start) / units))
        }
        if start < end {
            for year in (start + 1)...end {
                let name = LifePeriod.containing(year: year, birthYear: birthYear).name
                if name != runName {
                    close(through: year - 1)
                    runStart = year
                    runName = name
                }
            }
        }
        close(through: end)
        return bands
    }
}
