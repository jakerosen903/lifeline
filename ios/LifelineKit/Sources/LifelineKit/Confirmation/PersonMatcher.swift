import Foundation

/// Orders people for a "Who's this?" card: the closest names first, everyone after, so a
/// known person is always reachable and a near-match is one tap away. Pure.
public enum PersonMatcher {
    public static func rank(_ people: [Person], aliases: [PersonID: [String]], for text: String) -> [Person] {
        let needle = PeopleRepository.normalize(text)
        func closeness(_ person: Person) -> Int {
            let names = [person.displayName] + (aliases[person.id] ?? [])
            return names.map { score(needle, PeopleRepository.normalize($0)) }.max() ?? 0
        }
        return people.enumerated()
            .sorted { a, b in
                let sa = closeness(a.element), sb = closeness(b.element)
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// 4 equal, 3 one starts with the other, 2 shared three-letter prefix, 1 shared first letter, else 0.
    static func score(_ a: String, _ b: String) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 4 }
        if a.hasPrefix(b) || b.hasPrefix(a) { return 3 }
        if a.count >= 3, b.count >= 3, a.prefix(3) == b.prefix(3) { return 2 }
        if a.first == b.first { return 1 }
        return 0
    }
}
