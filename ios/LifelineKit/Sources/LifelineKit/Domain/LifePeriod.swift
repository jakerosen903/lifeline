/// A stretch of life named by the person's age, or by its decade when the age is unknown.
/// The name states an age or a decade, never a life event. Pure.
public struct LifePeriod: Hashable, Sendable {
    public let name: String
    /// True when the name comes from the birth date: the waypoint then says "by your age".
    public let byAge: Bool

    private static let adultDecades = ["Twenties", "Thirties", "Forties", "Fifties", "Sixties", "Seventies", "Eighties", "Nineties"]

    /// The period `year` falls in. Age is `year - birthYear`: 0 to 12 is Childhood, 13 to 19 Teens, then by tens
    /// up to the Nineties. With no birth year, a year before birth (negative age) or an age of 100 or more, the
    /// period is the calendar decade ("The 1980s"), and `byAge` is false.
    public static func containing(year: Int, birthYear: Int?) -> LifePeriod {
        if let birthYear {
            let age = year - birthYear
            switch age {
            case 0...12: return LifePeriod(name: "Childhood", byAge: true)
            case 13...19: return LifePeriod(name: "Teens", byAge: true)
            case 20...99: return LifePeriod(name: adultDecades[age / 10 - 2], byAge: true)
            default: break
            }
        }
        // Floor division, so a year before 1 CE still lands in the decade below it.
        let decade = Int((Double(year) / 10).rounded(.down)) * 10
        return LifePeriod(name: "The \(decade)s", byAge: false)
    }

    /// " · by your age" for a period by age; empty for a decade. The Timeline's waypoint sets it after the bold name.
    public var headingSuffix: String { byAge ? " · by your age" : "" }
    /// "Teens · by your age" for a period by age; "The 1990s" for a decade. One text for the Timeline and the shelf.
    public var headingText: String { name + headingSuffix }
}
