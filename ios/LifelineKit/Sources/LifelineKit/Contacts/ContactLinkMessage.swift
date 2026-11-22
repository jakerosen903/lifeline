import Foundation

/// The one sentence a person's contact row puts in the page's message slot after an action that did not go through.
/// Pure. A held contact names the person who holds it; anything else is the caller's fixed sentence, never an error's
/// text, which could carry a contact's name.
public enum ContactLinkMessage {
    public static func sentence(for error: Error, fallback: String) -> String {
        if case ContactLinkActions.Error.heldByAnother(_, let name) = error { return "\(name) is already linked to this contact." }
        return fallback
    }
}
