import ContactsUI
import LifelineKit
import SwiftUI

/// "Search your contacts" (spec, "Access"): a field, the contacts whose names start with what the owner types, and,
/// under limited access, Apple's `ContactAccessButton` so one tap shares one more contact. It calls back with the
/// picked contact; it moves nothing itself. The only file that imports `ContactsUI`. Used by the "Who is this?" sheet
/// and a person's page.
struct ContactSearchList: View {
    let deps: Dependencies
    /// The name of the person who holds each linked contact, by identifier: picking one is a move to that person.
    let heldBy: [String: String]
    let onPick: (ContactCard) -> Void
    @State private var text = ""
    @State private var cards: [ContactCard] = []
    @FocusState private var fieldFocused: Bool

    /// A contact with no full name has nothing to name a person by, so it is not offered.
    private var results: [ContactCard] { ContactSearch.results(text, in: cards).filter { !$0.keptName.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $text)
                .font(.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
                .accessibilityLabel("Search your contacts")
                .accessibilityIdentifier("contacts.search")
            ForEach(results) { resultRow($0) }
            if deps.contacts.access() == .limited { accessButton }
        }
        .onAppear {
            cards = deps.contactsCache.cards
            fieldFocused = true
        }
    }

    private func resultRow(_ card: ContactCard) -> some View {
        let holder = heldBy[card.identifier]
        let line = holder.map { "In a story as \($0)" }
        return Button { onPick(card) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.keptName).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                if let line { Text(line).font(.footnote).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.leading) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.map { "\(card.keptName). \($0)" } ?? card.keptName)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("contacts.result")
    }

    /// The real button and its stand-in, chosen in this one place. XCUITest cannot drive the system's button, so the
    /// scripted app shows a plain button with the same identifier that does nothing: a UI test can see it is offered.
    @ViewBuilder private var accessButton: some View {
        if deps.contactAccessButtonStandIn {
            Button("Share another contact") {}
                .frame(minHeight: 44)
                .accessibilityIdentifier("contacts.accessButton")
        } else {
            ContactAccessButton(queryString: text) { identifiers in
                Task { @MainActor in await shared(identifiers) }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("contacts.accessButton")
        }
    }

    /// The owner shared a contact through the system's button: read the contacts again, then return that contact as
    /// picked. A contact the read does not show (the system changed its mind, or the read failed) picks nothing.
    private func shared(_ identifiers: [String]) async {
        await deps.contactsCache.refresh(from: deps.contacts)
        cards = deps.contactsCache.cards
        guard let first = identifiers.first, let card = cards.first(where: { $0.identifier == first }), !card.keptName.isEmpty else { return }
        onPick(card)
    }
}
