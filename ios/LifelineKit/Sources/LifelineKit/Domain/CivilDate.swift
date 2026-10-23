import Foundation

/// A calendar date with no time zone: what "March 1994" or "1998-06-01" means in a life story.
/// Stored as `YYYY-MM-DD` text. Arithmetic uses the proleptic Gregorian calendar.
public struct CivilDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= Self.daysIn(month: month, year: year) else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    /// Accepts only the strict `YYYY-MM-DD` form.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Today in the given calendar's time zone.
    public static func today(calendar: Calendar = .current, now: Date = .now) -> CivilDate {
        let p = calendar.dateComponents([.year, .month, .day], from: now)
        return CivilDate(year: p.year ?? 2000, month: p.month ?? 1, day: p.day ?? 1) ?? CivilDate(year: 2000, month: 1, day: 1)!
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    public static func firstOfYear(_ year: Int) -> CivilDate { CivilDate(year: year, month: 1, day: 1)! }
    public static func lastOfYear(_ year: Int) -> CivilDate { CivilDate(year: year, month: 12, day: 31)! }
    public static func first(ofMonth month: Int, year: Int) -> CivilDate { CivilDate(year: year, month: month, day: 1)! }
    public static func last(ofMonth month: Int, year: Int) -> CivilDate { CivilDate(year: year, month: month, day: daysIn(month: month, year: year))! }

    /// Same month and day in another year; 29 February becomes 28 February when needed.
    public func adding(years: Int) -> CivilDate {
        let y = year + years
        return CivilDate(year: y, month: month, day: min(day, Self.daysIn(month: month, year: y)))!
    }

    public func adding(days: Int) -> CivilDate {
        CivilDate(ordinal: ordinal + days)
    }

    public static func < (a: CivilDate, b: CivilDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // MARK: - Day arithmetic (days since 0000-03-01, a standard civil-from-days algorithm)

    private var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe
    }

    private init(ordinal z: Int) {
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        year = y; month = m; day = d
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        default: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let date = CivilDate(iso: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a YYYY-MM-DD date: \(text)"))
        }
        self = date
    }
}
