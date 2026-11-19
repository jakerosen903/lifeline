import Foundation

extension PersonChipLine.ContactsSeen {
    /// What a "New" chip says about the contacts (PB1). `none` without access; `someMatch` when one or more contacts
    /// that no person holds fit the said name's name part by full name, given name or nickname (the names the guess
    /// matches by, rule 5); `noMatch` otherwise, a said name with no name part included. Pure.
    public static func of(saidName: String?, access: ContactsAccess, cards: [ContactCard], held: Set<String>) -> Self {
        switch access {
        case .notAsked, .denied: return .none
        case .full, .limited: break
        }
        guard let name = saidName.flatMap({ SaidName(ref: $0).name }) else { return .noMatch }
        let key = SaidName.key(name)
        guard !key.isEmpty else { return .noMatch }
        let fits = cards.contains { !held.contains($0.identifier) && ContactSuggestion.hasName($0, in: [key]) }
        return fits ? .someMatch : .noMatch
    }
}
