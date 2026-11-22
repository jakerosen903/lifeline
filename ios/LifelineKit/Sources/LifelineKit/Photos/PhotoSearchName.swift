import Foundation

/// The text "Add a photo" gives to the system picker's search on a person's page (iOS 27 and later). Pure.
/// The text goes to the picker only: the app does not see what the search finds.
public enum PhotoSearchName {
    /// A linked contact the app can see gives its full name. Every other person gives the page's name: a contact
    /// that is not in the owner's contacts now may hold a stale name. The owner's page and a page that is not a
    /// person give nothing, and so does a name of spaces: the picker then opens on the library.
    public static func text(type: EntityType, isOwner: Bool, title: String, contact: PersonContactState?) -> String? {
        guard type == .person, !isOwner else { return nil }
        if case .linked(let contactName) = contact, let name = trimmed(contactName) { return name }
        return trimmed(title)
    }

    private static func trimmed(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
