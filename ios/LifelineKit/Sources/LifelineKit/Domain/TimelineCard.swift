import Foundation

/// The card pinned to the top of the Timeline: a strip of the whole life, a frame over the years
/// on screen, and the chapters those years touch. Pure; it stores nothing. Only stated chapter
/// years reach the "During" line; a date overlap never tags a moment.
public struct TimelineCard: Sendable, Equatable {
    public struct During: Sendable, Equatable, Identifiable {
        public let id: ChapterID
        public let name: String
    }

    /// Marks sit at the start of each moment's range.
    public let strip: LifeStrip
    /// 0...1 along the strip; a year is one unit and the frame ends after its last year.
    /// Nil when no years are on screen.
    public let frame: ClosedRange<Double>?
    public let frameYears: ClosedRange<Int>?
    /// Longest chapter first; empty when no chapter overlaps the frame.
    public let during: [During]

    /// No dated moment: the screen shows no card.
    public var isEmpty: Bool { strip.marks.isEmpty }

    /// `onScreen` holds the years of the spine rows on screen, one range for each row.
    public init(moments: [TimeRange], chapters: [Chapter], onScreen: [ClosedRange<Int>], birthYear: Int?, currentYear: Int) {
        let strip = LifeStrip(moments: moments, stated: .unplaced, birthYear: birthYear, currentYear: currentYear, marks: .start)
        self.strip = strip

        guard let first = onScreen.map(\.lowerBound).min(), let last = onScreen.map(\.upperBound).max() else {
            frame = nil; frameYears = nil; during = []
            return
        }
        let years = first...last
        let width = Double(max(strip.endYear + 1 - strip.startYear, 1))
        func position(_ year: Int) -> Double { min(max(Double(year - strip.startYear) / width, 0), 1) }
        frame = position(years.lowerBound)...position(years.upperBound + 1)
        frameYears = years
        during = Self.chapters(overlapping: years, in: chapters, currentYear: currentYear)
    }

    /// "Maple Street · Summers at the lake": the first `count` names. Nil for none to show.
    public func duringText(showing count: Int) -> String? {
        guard count > 0, !during.isEmpty else { return nil }
        return during.prefix(count).map(\.name).joined(separator: " · ")
    }

    /// "+2": how many names `duringText(showing:)` leaves out. Nil when every name shows.
    public func overflow(showing count: Int) -> String? {
        let hidden = during.count - max(count, 0)
        return hidden > 0 ? "+\(hidden)" : nil
    }

    /// "Your life from 1998 to now. On screen: 1998 to 2003. During Maple Street and 2 more."
    public var spokenText: String {
        var sentences = ["Your life from \(strip.startYear) to now."]
        if let years = frameYears {
            sentences.append(years.lowerBound == years.upperBound
                ? "On screen: \(years.lowerBound)."
                : "On screen: \(years.lowerBound) to \(years.upperBound).")
        }
        let names = during.map(\.name)
        switch names.count {
        case 0: break
        case 1: sentences.append("During \(names[0]).")
        case 2: sentences.append("During \(names[0]) and \(names[1]).")
        default: sentences.append("During \(names[0]), \(names[1]) and \(names.count - 2) more.")
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - Chapters

    /// Named chapters with stated years that touch `frame`, longest first. A chapter with no
    /// stated end runs to now. Ties: earlier start, then name.
    private static func chapters(overlapping frame: ClosedRange<Int>, in chapters: [Chapter], currentYear: Int) -> [During] {
        struct Hit { let id: ChapterID; let name: String; let first: Int; let length: Int }
        let hits: [Hit] = chapters.compactMap { chapter in
            guard let name = chapter.name, let years = LifeMap.years(of: chapter) else { return nil }
            let last = max(years.last ?? currentYear, years.first)
            guard years.first <= frame.upperBound, last >= frame.lowerBound else { return nil }
            return Hit(id: chapter.id, name: name, first: years.first, length: last - years.first + 1)
        }
        return hits.sorted { a, b in
            if a.length != b.length { return a.length > b.length }
            if a.first != b.first { return a.first < b.first }
            return a.name < b.name
        }.map { During(id: $0.id, name: $0.name) }
    }
}
