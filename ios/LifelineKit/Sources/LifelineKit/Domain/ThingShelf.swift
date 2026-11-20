/// The Things shelf: which group each thing sits in, and in what order. Pure: it stores nothing.
/// It uses the Timeline spine's own period rule (`SpineLayout.placingDate`, `LifePeriod.containing`),
/// so a thing never sits in a different period here than on the Timeline.
public enum ThingShelf {
    public struct Tile: Sendable, Equatable, Identifiable {
        public var summary: EntitySummary
        /// No dated moment in this tile's period is settled. False for a stated span and for an unplaced tile.
        public var placedByGuess: Bool
        public var id: EntityID { summary.id }
        public init(summary: EntitySummary, placedByGuess: Bool) {
            self.summary = summary; self.placedByGuess = placedByGuess
        }
    }

    public enum Heading: Sendable, Equatable {
        case period(LifePeriod), notPlaced
        /// `headingText` of the period, or "Not placed in time yet".
        public var text: String {
            switch self {
            case .period(let period): return period.headingText
            case .notPlaced: return "Not placed in time yet"
            }
        }
    }

    public struct Group: Sendable, Equatable {
        public var heading: Heading
        public var tiles: [Tile]
        public init(heading: Heading, tiles: [Tile]) { self.heading = heading; self.tiles = tiles }
    }

    public enum Layout: Sendable, Equatable { case flat([Tile]), grouped([Group]) }

    /// Spec "Grouping by period", "The flat grid" and "Order". `things` holds visible things only.
    /// A thing sits once, in the period of its earliest placing date. With no placed thing the shelf is flat.
    public static func layout(_ things: [EntitySummary], birthYear: Int?) -> Layout {
        var placed: [Placed] = []
        var unplaced: [Tile] = []
        for thing in things {
            if let item = place(thing, birthYear: birthYear) {
                placed.append(item)
            } else {
                unplaced.append(Tile(summary: thing, placedByGuess: false))
            }
        }
        unplaced.sort { titleOrder($0.summary, $1.summary) }
        if placed.isEmpty { return .flat(unplaced) }

        var groups: [Group] = []
        var starts: [LifePeriod: CivilDate] = [:]  // the earliest placing date in each period, for ordering the groups
        for period in Set(placed.map(\.period)) {
            let members = placed.filter { $0.period == period }
                .sorted { $0.date != $1.date ? $0.date < $1.date : titleOrder($0.tile.summary, $1.tile.summary) }
            starts[period] = members[0].date
            groups.append(Group(heading: .period(period), tiles: members.map(\.tile)))
        }
        groups.sort { lhs, rhs in
            guard case .period(let a) = lhs.heading, case .period(let b) = rhs.heading else { return false }
            return starts[a]! < starts[b]!
        }
        if !unplaced.isEmpty { groups.append(Group(heading: .notPlaced, tiles: unplaced)) }
        return .grouped(groups)
    }

    // MARK: - Helpers

    private struct Placed {
        let tile: Tile
        let period: LifePeriod
        let date: CivilDate
    }

    /// The thing's period and tile, or nil when nothing dates it. Dated moments place a thing; with none,
    /// its own stated span does. The earliest placing range decides the period.
    private static func place(_ thing: EntitySummary, birthYear: Int?) -> Placed? {
        var placing = thing.momentRanges.filter(\.isDated)
        if placing.isEmpty, thing.entity.range.isDated { placing = [thing.entity.range] }
        guard let deciding = placing.min(by: { SpineLayout.placingDate(of: $0)! < SpineLayout.placingDate(of: $1)! }),
              let date = SpineLayout.placingDate(of: deciding) else { return nil }
        let period = LifePeriod.containing(year: date.year, birthYear: birthYear)
        let inPeriod = placing.filter { LifePeriod.containing(year: SpineLayout.placingDate(of: $0)!.year, birthYear: birthYear) == period }
        let guess = !inPeriod.contains(where: \.isSettled)
        return Placed(tile: Tile(summary: thing, placedByGuess: guess), period: period, date: date)
    }

    /// By title ignoring case; the id breaks a tie so the order never depends on the input order.
    private static func titleOrder(_ a: EntitySummary, _ b: EntitySummary) -> Bool {
        let (x, y) = (a.entity.title.lowercased(), b.entity.title.lowercased())
        return x != y ? x < y : a.id.rawValue < b.id.rawValue
    }
}
