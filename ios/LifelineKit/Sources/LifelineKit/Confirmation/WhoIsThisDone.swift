import Foundation

/// What "Done" on the "Who is this?" sheet does for a kept link. Pure: the view model passes the
/// origins of the links in the chosen scope (the tapped link, or its whole group with the checkbox on).
public enum WhoIsThisDone: Sendable, Equatable {
    /// The choice is the same person and every link in the scope is already the owner's word (R29).
    case nothing
    /// The same person, and a link in the scope is still a guess: settle the scope.
    case settle
    /// Another person, "Someone new" or "Not a person".
    case move

    public static func decide(keepsPerson: Bool, scope: [LinkOrigin?]) -> WhoIsThisDone {
        guard keepsPerson else { return .move }
        return scope.contains { $0 == .assumed || $0 == .new } ? .settle : .nothing
    }
}
