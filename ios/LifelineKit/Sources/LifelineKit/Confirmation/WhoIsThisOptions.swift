import Foundation

/// What the "Who is this?" sheet lists. Pure: the view model reads the store and passes it in.
/// "Someone new" and "Not a person" are fixed rows the view draws; they are not in `rows`.
/// The copy is a draft until the owner writes the final copy.
public struct WhoIsThisOptions: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public var target: PersonLinkActions.Target
        public var title: String
        public var line: String
        public var isCurrent: Bool
        public var id: String {
            switch target {
            case .person(let id): "person:\(id.rawValue)"
            case .someoneNew: "new"
            case .notAPerson: "none"
            }
        }

        public init(target: PersonLinkActions.Target, title: String, line: String, isCurrent: Bool) {
            self.target = target; self.title = title; self.line = line; self.isCurrent = isCurrent
        }
    }

    public var saidName: String
    public var quote: String?
    /// The current choice first, then the other candidates in the order given.
    public var rows: [Row]
    /// The other persons on file, by name, behind "Someone else". Never the owner, a candidate or the current person.
    public var everyoneElse: [Row]
    /// The group without this link. 0 hides the checkbox.
    public var otherMoments: Int

    public static func build(saidName: String, quote: String?, current: PersonID?, currentIsGuess: Bool,
                             candidates: [PersonID], people: [(Person, stories: Int)], otherMoments: Int) -> WhoIsThisOptions {
        let byID = Dictionary(people.map { ($0.0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func row(_ id: PersonID, isCurrent: Bool) -> Row? {
            // The owner is never a candidate, but a link the owner already holds still shows as the current choice.
            guard let entry = byID[id], isCurrent || !entry.0.isOwner else { return nil }
            let guess = isCurrent && currentIsGuess
            return Row(target: .person(id), title: entry.0.displayName, line: line(stories: entry.stories, isGuess: guess), isCurrent: isCurrent)
        }
        var shown: [PersonID] = []
        var rows: [Row] = []
        let order = (current.map { [$0] } ?? []) + candidates
        for id in order where !shown.contains(id) {
            if let made = row(id, isCurrent: id == current) { rows.append(made); shown.append(id) }
        }
        let rest = people.filter { !$0.0.isOwner && !shown.contains($0.0.id) }
            .sorted { $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending }
        return WhoIsThisOptions(saidName: saidName, quote: quote, rows: rows,
                                everyoneElse: rest.compactMap { row($0.0.id, isCurrent: false) }, otherMoments: otherMoments)
    }

    public static func groupLabel(_ n: Int) -> String {
        "Also change the \(n) other \(n == 1 ? "moment" : "moments") from this recording"
    }

    private static func line(stories: Int, isGuess: Bool) -> String {
        guard stories > 0 else { return "Not in a story yet" }
        return "In \(stories) of your stories" + (isGuess ? " \u{00B7} my guess" : "")
    }
}
