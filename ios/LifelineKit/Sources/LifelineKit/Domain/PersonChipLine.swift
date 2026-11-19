import Foundation

/// The words under a person chip and on the landing page. Pure text; the views choose the colour.
/// The copy is a draft until the owner writes the final copy.
public enum PersonChipLine {
    /// What the app saw of the contacts for a new name: `none` when it sees no contacts (no access, or
    /// not asked yet), `noMatch` when none fits the said name, `someMatch` when one or more fit.
    public enum ContactsSeen: Sendable { case none, noMatch, someMatch }

    /// nil for a link with no line (said, confirmed, older). `fromContact` is a person Keep made from a
    /// contact (`PersonLink.personFromContact`, `PreviewChip.fromContact`).
    public static func text(origin: LinkOrigin?, saidName: String?, fromContact: Bool, contacts: ContactsSeen) -> String? {
        switch origin {
        case .assumed:
            if fromContact { return "Assumed \u{00B7} new, from your contacts" }
            guard let said = clean(saidName) else { return "Assumed" }
            return "Assumed \u{00B7} you said \u{201C}\(said)\u{201D}"
        case .new:
            switch contacts {
            case .none: return "New"
            case .noMatch: return "New \u{00B7} not in your contacts"
            case .someMatch: return "New \u{00B7} not linked yet"
            }
        case .said, .confirmed, nil: return nil
        }
    }

    /// `fromContact` as in `text`: the chip's line, read aloud.
    public static func accessibilityLabel(name: String, origin: LinkOrigin?, saidName: String?, fromContact: Bool = false) -> String {
        guard origin == .assumed else { return "\(name). Change who this is." }
        if fromContact { return "\(name), assumed, new, from your contacts. Change who this is." }
        guard let said = clean(saidName) else { return "\(name), assumed. Change who this is." }
        return "\(name), assumed, you said \(said). Change who this is."
    }

    /// A waiting card's quiet chip for a name the owner marked "Not a person" (R37).
    public static func notAPersonLabel(saidName: String) -> String {
        "\(clean(saidName) ?? saidName), not a person. Change who this is."
    }

    /// The button on a guessed moment of a person's page: "Yes, this Robyn". The first word of the name;
    /// a one-word name is used whole, and an empty one reads "Yes, this person".
    public static func confirmLabel(name: String) -> String {
        let first = name.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return "Yes, this \(first ?? "person")"
    }

    /// The sub-line on the landing page. nil when there is no guess to report.
    public static func landingLine(guesses: Int) -> String? {
        switch guesses {
        case ..<1: nil
        case 1: "I made one guess about who you meant."
        default: "I made \(guesses) guesses about who you meant."
        }
    }

    /// The notice after a move, offered with Undo. A move to "Not a person" has no name.
    public static func movedNotice(newName: String) -> String {
        guard let name = clean(newName) else { return "Not a person." }
        return "Changed to \(name)."
    }

    /// The notice when Undo is refused because a row the move left changed since.
    public static let staleUndo = "That changed since. Open the name to change it again."

    /// The sheet's sentence when "Done" is refused: `stale` when a row changed since the sheet opened; `notFound` when
    /// the person or the contact the change needs is not there (PB42, PB40). Draft copy for `notFound`, for the owner's sign-off.
    public static func refusal(_ error: PersonLinkActions.Error) -> String {
        switch error {
        case .stale: staleUndo
        case .notFound: "That person is not here any more."
        }
    }

    /// The notice when Undo failed for any other reason. The error's own text never reaches the person.
    public static let failedUndo = "Could not undo that."

    private static func clean(_ said: String?) -> String? {
        let trimmed = said?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
