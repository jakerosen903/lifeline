import Foundation

/// How old the owner says they were. Years are inclusive ages; a grade is a school year.
public enum AgeSpan: Equatable, Sendable {
    case years(from: Int, to: Int)
    case grade(Int)
    case approximate(center: Int, slack: Int)
}

/// Turns the owner's time phrases into ranges or ages. Pure string work with small tables; a
/// phrase it does not understand returns nil and stays unresolved rather than guessed.
public enum AnchorPhrase {
    public static let yearRange = 1900...2099

    // MARK: - Absolute

    public static func parseAbsolute(_ phrase: String, value: String?) -> TimeRange? {
        let words = tokens(phrase)
        // "around", "maybe", "or so", "may have been": the owner was guessing, so it is a guess.
        let origin: RangeOrigin = isApproximate(words) ? .inferred : .stated
        if let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
            if let day = CivilDate(iso: value) {
                return TimeRange.span(day, day, granularity: .day, origin: origin, evidence: phrase)
            }
            if let y = Int(value), yearRange.contains(y) {
                return .year(y, origin: origin, evidence: phrase)
            }
        }
        guard !words.isEmpty else { return nil }
        let years = findYears(in: words)
        if years.count >= 2, words.contains("or") {
            return TimeRange.span(.firstOfYear(years.min()!), .lastOfYear(years.max()!), granularity: .year, origin: .inferred, evidence: phrase)
        }
        let year = years.first
        if let season = words.lazy.compactMap({ seasons[$0] }).first, let year {
            let (startMonth, endMonth, wraps) = season
            let start = CivilDate.first(ofMonth: startMonth, year: year)
            let end = CivilDate.last(ofMonth: endMonth, year: wraps ? year + 1 : year)
            return TimeRange.span(start, end, granularity: .season, origin: origin, evidence: phrase)
        }
        if let month = findMonth(in: words), let year {
            return TimeRange.span(.first(ofMonth: month, year: year), .last(ofMonth: month, year: year), granularity: .month, origin: origin, evidence: phrase)
        }
        if let decade = findDecade(in: words) {
            return TimeRange.span(.firstOfYear(decade), .lastOfYear(decade + 9), granularity: .decade, origin: origin, evidence: phrase)
        }
        if let year { return .year(year, origin: origin, evidence: phrase) }
        return nil
    }

    static func isApproximate(_ words: [String]) -> Bool {
        let text = words.joined(separator: " ")
        if words.contains(where: { ["around", "about", "roughly", "maybe", "approximately", "probably", "perhaps"].contains($0) }) { return true }
        return text.contains(" or so") || text.hasSuffix("ish") || text.contains("may have been") || text.contains("might have been")
            || text.contains("i think") || text.contains("something like")
    }

    /// "may" is a month only next to a year or a day number; otherwise it is the verb.
    static func findMonth(in words: [String]) -> Int? {
        for (i, w) in words.enumerated() {
            guard let month = months[w] else { continue }
            if w != "may" { return month }
            let neighbours = [i > 0 ? words[i - 1] : "", i + 1 < words.count ? words[i + 1] : ""]
            if neighbours.contains(where: { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "'"))) != nil }) { return month }
        }
        return nil
    }

    // MARK: - Age

    public static func parseAge(_ phrase: String, value: String?) -> AgeSpan? {
        let words = tokens(phrase)
        guard !words.isEmpty else { return nil }
        let text = words.joined(separator: " ")

        // "six months old" is not an age in years.
        if text.contains("months old") || text.contains("weeks old") || text.contains("days old") { return nil }
        if words.contains("kindergarten") { return .grade(0) }
        if let i = words.firstIndex(of: "grade") {
            if i > 0, let n = ordinal(words[i - 1]), (1...12).contains(n) { return .grade(n) }
            if i + 1 < words.count, let n = Int(words[i + 1]), (1...12).contains(n) { return .grade(n) }
        }
        let inCollege = text.contains("college") || text.contains("university")
        for (word, grade) in schoolYears where words.contains(word) {
            // Freshman through senior: a grade in high school, a year of life in college.
            return inCollege ? .years(from: grade + 9, to: grade + 9) : .grade(grade)
        }
        if text.contains("middle school") { return .years(from: 11, to: 14) }
        if text.contains("high school") { return .years(from: 14, to: 18) }
        if inCollege { return .years(from: 18, to: 22) }

        if let i = words.firstIndex(of: "birthday"), i > 0, let n = ordinal(words[i - 1]), (0...99).contains(n) { return .years(from: n, to: n) }

        let numbers = cardinalRuns(in: words)
        if let first = numbers.first {
            // "eleven or twelve" is exactly those two ages, not a band around the first.
            if numbers.count >= 2, words.contains("or") { return .years(from: min(first, numbers[1]), to: max(first, numbers[1])) }
            if isApproximate(words) { return .approximate(center: first, slack: 1) }
            return .years(from: first, to: first)
        }
        if let value, let n = Int(value.trimmingCharacters(in: .whitespaces)), (0...99).contains(n) { return .years(from: n, to: n) }
        return nil
    }

    // MARK: - Pieces

    /// Lowercased words, apostrophes unified, outer punctuation removed (a leading ' is kept for "'98").
    static func tokens(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { String($0).trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'-"))) }
            .map { $0.hasSuffix("'") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty }
    }

    /// Every year said: four digits, or two digits marked by an apostrophe or after a season or "of".
    static func findYears(in words: [String]) -> [Int] {
        var out: [Int] = []
        for (i, w) in words.enumerated() {
            if w.count == 4, let y = Int(w), yearRange.contains(y) { out.append(y) }
            else if w.hasPrefix("'"), let two = Int(w.dropFirst()), (0...99).contains(two) { out.append(expand(two)) }
            else if w.count == 2, let two = Int(w), i > 0, seasons[words[i - 1]] != nil || words[i - 1] == "of" { out.append(expand(two)) }
        }
        return out
    }

    private static func expand(_ two: Int) -> Int { two < 30 ? 2000 + two : 1900 + two }

    static func findDecade(in words: [String]) -> Int? {
        for w in words {
            if let d = decadeWords[w] { return d }
            if w.hasSuffix("s"), let n = Int(w.dropLast()) {
                if n >= 1900, n % 10 == 0, yearRange.contains(n) { return n }
                if (0...99).contains(n), n % 10 == 0 { return expand(n) / 10 * 10 }
            }
            if w.hasPrefix("'"), w.hasSuffix("s"), let n = Int(w.dropFirst().dropLast()), n % 10 == 0 { return expand(n) }
        }
        return nil
    }

    /// Every run of number words ("twenty five", "twenty-one", "6") as one integer, in order.
    /// Hundreds and thousands are not ages; a phrase with them yields nothing.
    static func cardinalRuns(in words: [String]) -> [Int] {
        if words.contains(where: { $0 == "hundred" || $0 == "thousand" }) { return [] }
        var out: [Int] = []
        var current: Int? = nil
        func flush() { if let c = current, (0...99).contains(c) { out.append(c) }; current = nil }
        for raw in words {
            let w = raw.replacingOccurrences(of: "-ish", with: "").replacingOccurrences(of: "ish", with: "")
            if let n = Int(w) { flush(); current = n; flush(); continue }
            let parts = w.split(separator: "-").map(String.init)
            var matched = false
            for part in parts {
                if let n = cardinals[part] {
                    matched = true
                    if n >= 20, n % 10 == 0, current == nil { current = n }
                    else if let c = current, c >= 20, c % 10 == 0, n < 10 { current = c + n; flush() }
                    else { flush(); current = n; if n < 20 { flush() } }
                }
            }
            if !matched, w != "and" { flush() }
        }
        flush()
        return out
    }

    static func ordinal(_ word: String) -> Int? {
        if let n = ordinals[word] { return n }
        let digits = word.prefix { $0.isNumber }
        if !digits.isEmpty, ["st", "nd", "rd", "th"].contains(String(word.dropFirst(digits.count))) { return Int(digits) }
        return nil
    }

    static let seasons: [String: (Int, Int, Bool)] = [
        "spring": (3, 5, false), "summer": (6, 8, false), "fall": (9, 11, false), "autumn": (9, 11, false), "winter": (12, 2, true),
    ]
    static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6,
        "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9, "october": 10, "oct": 10,
        "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]
    static let decadeWords: [String: Int] = [
        "twenties": 1920, "thirties": 1930, "forties": 1940, "fifties": 1950, "sixties": 1960, "seventies": 1970,
        "eighties": 1980, "nineties": 1990, "aughts": 2000, "noughties": 2000,
    ]
    static let schoolYears: [(String, Int)] = [("freshman", 9), ("sophomore", 10), ("junior", 11), ("senior", 12)]
    static let cardinals: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
        "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17,
        "eighteenth": 18, "nineteenth": 19, "twentieth": 20, "twenty-first": 21, "thirtieth": 30,
    ]
}
