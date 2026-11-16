import Foundation

/// How the People grid orders its tiles. Every sort breaks ties by name, ignoring case, then by id.
public enum PeopleSort: String, CaseIterable, Sendable {
    case mostTold, firstInStory, byName

    public var title: String {
        switch self {
        case .mostTold: "Most told"
        case .firstInStory: "First in your story"
        case .byName: "By name"
        }
    }

    public func sorted(_ people: [EntitySummary]) -> [EntitySummary] {
        func nameFirst(_ a: EntitySummary, _ b: EntitySummary) -> Bool {
            let order = a.entity.title.localizedCaseInsensitiveCompare(b.entity.title)
            // The id is the last tiebreak, so two people with one name never swap between reads.
            return order == .orderedSame ? a.id.rawValue < b.id.rawValue : order == .orderedAscending
        }
        return people.sorted { a, b in
            switch self {
            case .byName:
                return nameFirst(a, b)
            case .mostTold:
                return a.momentCount != b.momentCount ? a.momentCount > b.momentCount : nameFirst(a, b)
            case .firstInStory:
                // People with no dated moment come last.
                switch (a.firstDate, b.firstDate) {
                case let (x?, y?) where x != y: return x < y
                case (nil, .some): return false
                case (.some, nil): return true
                default: return nameFirst(a, b)
                }
            }
        }
    }
}

/// What a tile shows in place of a photo.
public enum Monogram {
    /// The first letter, upper-cased. With no letter in the title, its first character.
    public static func letter(for title: String) -> String {
        guard let first = title.first(where: \.isLetter) ?? title.first else { return "" }
        return String(first).uppercased()
    }

    /// 0, 1 or 2: the sum of the id's Unicode scalars, modulo 3. Never `hashValue`, which
    /// Swift seeds anew at every launch: a person must keep their tint.
    public static func tintIndex(for id: EntityID) -> Int {
        id.rawValue.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Palette.monogramTints.count
    }
}
