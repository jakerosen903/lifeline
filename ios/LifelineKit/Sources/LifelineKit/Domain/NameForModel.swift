import Foundation

/// The one way a person's name enters text bound for a model: the context packet, a curiosity
/// question, the interviewer's opening (PB10). Nothing from a contact goes to the model, so a person
/// whose name came from a contact goes by the oldest name the owner said for them. Pure.
public enum NameForModel {
    /// nil when the person's name came from a contact and the owner has said no name for them: the
    /// caller then leaves the person out, or drafts no text about them.
    public static func of(_ person: Person, aliasesOldestFirst aliases: [Alias]) -> String? {
        guard person.nameOrigin == .contact else { return person.displayName }
        return aliases.lazy.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
}
