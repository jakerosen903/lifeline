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
            case .contact(let card): "contact:\(card.identifier)"
            }
        }

        public init(target: PersonLinkActions.Target, title: String, line: String, isCurrent: Bool) {
            self.target = target; self.title = title; self.line = line; self.isCurrent = isCurrent
        }
    }

    public var saidName: String
    public var quote: String?
    /// The current choice first, then the other candidates in the order given, then the free contacts that fit.
    public var rows: [Row]
    /// The other persons on file, by name, behind "Someone else". Never the owner, a candidate or the current person.
    public var everyoneElse: [Row]
    /// The group without this link. 0 hides the checkbox.
    public var otherMoments: Int

    /// `contacts` are the contacts the app may show (`offered`). The ones that fit the said name by full name, given
    /// name or nickname (the names the guess matches by, rule 5) follow the people: a free contact as its own row,
    /// a contact a person holds as that person's row, so one contact never shows as two choices.
    public static func build(saidName: String, quote: String?, current: PersonID?, currentIsGuess: Bool,
                             candidates: [PersonID], people: [(Person, stories: Int)], contacts: [ContactCard],
                             otherMoments: Int) -> WhoIsThisOptions {
        let byID = Dictionary(people.map { ($0.0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func row(_ id: PersonID, isCurrent: Bool) -> Row? {
            // The owner is never a candidate, but a link the owner already holds still shows as the current choice.
            guard let entry = byID[id], isCurrent || !entry.0.isOwner else { return nil }
            let guess = isCurrent && currentIsGuess
            return Row(target: .person(id), title: entry.0.displayName, line: line(stories: entry.stories, isGuess: guess), isCurrent: isCurrent)
        }
        var shown: [PersonID] = []
        var rows: [Row] = []
        let fitting = fits(saidName, in: contacts)
        let holders = Dictionary(people.compactMap { entry in entry.0.contactIdentifier.map { ($0, entry.0.id) } },
                                 uniquingKeysWith: { first, _ in first })
        let order = (current.map { [$0] } ?? []) + candidates + fitting.compactMap { holders[$0.identifier] }
        for id in order where !shown.contains(id) {
            if let made = row(id, isCurrent: id == current) { rows.append(made); shown.append(id) }
        }
        rows += fitting.filter { holders[$0.identifier] == nil }.map { contactRow($0, heldBy: nil) }
        let rest = people.filter { !$0.0.isOwner && !shown.contains($0.0.id) }
            .sorted { $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending }
        return WhoIsThisOptions(saidName: saidName, quote: quote, rows: rows,
                                everyoneElse: rest.compactMap { row($0.0.id, isCurrent: false) }, otherMoments: otherMoments)
    }

    /// The contacts the sheet may show: none until the owner gave access (spec, "Access").
    public static func offered(_ cards: [ContactCard], access: ContactsAccess) -> [ContactCard] {
        switch access {
        case .full, .limited: cards
        case .notAsked, .denied: []
        }
    }

    /// The options with a contact the owner picked in the search, as a row after the others. `heldBy` is the name of
    /// the person who holds that contact: picking it is a move to them, and the line says so. A contact listed already
    /// is not added again.
    public func adding(_ card: ContactCard, heldBy: String?) -> WhoIsThisOptions {
        guard !rows.contains(where: { $0.target == .contact(card) }) else { return self }
        var out = self
        out.rows.append(Self.contactRow(card, heldBy: heldBy))
        return out
    }

    /// The options for a waiting card whose chip is a person Keep will make from `card`: that contact is the current
    /// choice, first and marked as the app's guess, and listed once (I-1). Draft copy, for the owner's sign-off.
    public func withCurrentContact(_ card: ContactCard) -> WhoIsThisOptions {
        var out = self
        out.rows.removeAll { $0.target == .contact(card) }
        out.rows.insert(Row(target: .contact(card), title: card.keptName, line: "In your contacts \u{00B7} my guess", isCurrent: true), at: 0)
        return out
    }

    /// The contacts whose full name, given name or nickname is the said name's name part, each once, by full name.
    /// A contact with no full name has nothing to name a person by (a move to it is refused), so it is left out.
    private static func fits(_ saidName: String, in contacts: [ContactCard]) -> [ContactCard] {
        let key = SaidName(ref: saidName).name.map(SaidName.key) ?? ""
        guard !key.isEmpty else { return [] }
        var out: [ContactCard] = []
        for card in contacts where !card.keptName.isEmpty && !out.contains(where: { $0.identifier == card.identifier })
            && ContactSuggestion.hasName(card, in: [key]) {
            out.append(card)
        }
        return out.sorted { SaidName.key($0.fullName) < SaidName.key($1.fullName) }
    }

    private static func contactRow(_ card: ContactCard, heldBy: String?) -> Row {
        Row(target: .contact(card), title: card.keptName,
            line: heldBy.map { "In a story as \($0)" } ?? "In your contacts \u{00B7} not in a story yet", isCurrent: false)
    }

    public static func groupLabel(_ n: Int) -> String {
        "Also change the \(n) other \(n == 1 ? "moment" : "moments") from this recording"
    }

    private static func line(stories: Int, isGuess: Bool) -> String {
        guard stories > 0 else { return "Not in a story yet" }
        return "In \(stories) of your stories" + (isGuess ? " \u{00B7} my guess" : "")
    }
}
