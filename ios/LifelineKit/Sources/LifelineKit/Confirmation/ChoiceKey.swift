import Foundation

/// The text under which the owner's answer for one said name of a waiting card is stored
/// (`candidate_person_choice.said_name`, PC-d decision 8). Two handles of one said name are two
/// people, so each has its own answer.
enum ChoiceKey {
    /// U+001F (unit separator): no said name holds it, so the two parts never run together.
    static let separator = "\u{1F}"

    /// The normalized said name; with a handle, the said name, the separator U+001F and the handle (decision 8).
    /// An empty handle is no handle: a card from before v8 keys by said name alone, as it always did.
    static func text(saidName: String, handle: String?) -> String {
        let key = SaidName.key(saidName)
        guard let handle, !handle.isEmpty else { return key }
        return key + separator + handle
    }
}
