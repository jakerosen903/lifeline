import LifelineKit
import SwiftUI

/// The contact row on a person's page (PC3, PC4), and the suggestion card under it. Linked: the contact's name and
/// "Change" (another contact, or "Unlink"). Not linked: "Link to a contact". Missing: the contact cannot be found, or
/// the app cannot look. No access: the PC4 card with "Allow contacts in Settings". The texts of each part read as one
/// element; the buttons stay reachable on their own.
struct PersonContactRow: View {
    let viewModel: PersonContactViewModel
    /// The page's parent reads again after a change (the people grid shows the copied picture).
    let onChange: () -> Void
    @State private var searching = false
    /// Who holds each linked contact, read once when the search opens, not on each render.
    @State private var heldBy: [String: String] = [:]

    var body: some View {
        if let state = viewModel.state {
            VStack(alignment: .leading, spacing: 12) {
                row(state)
                if case .notLinked(let suggestion?) = state { suggestionCard(suggestion) }
            }
            .disabled(viewModel.isWorking)
            .sheet(isPresented: $searching) { search }
        }
    }

    @ViewBuilder private func row(_ state: PersonContactState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .linked(let name):
                texts(heading: "Linked to \(name) in your contacts", body: "The app reads the name and picture only.")
                changeMenu
            case .notLinked:
                texts(heading: "Not linked to a contact", body: "That is fine. \(viewModel.personName) has a page and stories either way.")
                linkButton
            case .missing(let name, canSeeContacts: true):
                texts(heading: "This contact is not in your contacts now", body: name)
                // Side by side when they fit; one above the other at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { linkButton; unlinkButton }
                    VStack(alignment: .leading, spacing: 8) { linkButton; unlinkButton }
                }
            case .missing(let name, canSeeContacts: false):
                // The contact's name, then the no-access heading and body as their own lines.
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(Self.noAccessHeading).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(Self.noAccessBody).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                settingsButton
            case .noAccess:
                texts(heading: Self.noAccessHeading, body: Self.noAccessBody)
                settingsButton
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        // A container: without it the identifier passes down and replaces the buttons' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entity.contact.row")
    }

    private static let noAccessHeading = "If the app cannot see your contacts"
    private static let noAccessBody = "People still work. Names are matched to the people in your stories only, and each guess is still marked."

    /// A heading and a line under it, read by VoiceOver as one sentence pair.
    private func texts(heading: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(body).font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// "{contact name} is in your contacts" / "Is this the same person?" with the two answers (PC4).
    private func suggestionCard(_ card: ContactCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            texts(heading: "\(card.keptName) is in your contacts", body: "Is this the same person?")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { suggestionAnswers(card) }
                VStack(alignment: .leading, spacing: 8) { suggestionAnswers(card) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entity.contact.suggestion")
    }

    @ViewBuilder private func suggestionAnswers(_ card: ContactCard) -> some View {
        Button { Task { await viewModel.link(card); onChange() } } label: { buttonLabel("Yes, link them") }
            .buttonStyle(.borderedProminent).tint(Theme.oliveOnFill)
            .accessibilityIdentifier("entity.contact.suggestion.yes")
        Button { viewModel.decline(card) } label: { buttonLabel("No, someone else") }
            .buttonStyle(.bordered).tint(Theme.oliveOnFill)
            .accessibilityIdentifier("entity.contact.suggestion.no")
    }

    private var linkButton: some View {
        Button { Task { await openSearch() } } label: { buttonLabel("Link to a contact") }
            .buttonStyle(.bordered).tint(Theme.oliveOnFill)
            .accessibilityIdentifier("entity.contact.link")
    }

    private var unlinkButton: some View {
        Button { viewModel.unlink(); onChange() } label: { buttonLabel("Unlink") }
            .buttonStyle(.bordered).tint(Theme.oliveOnFill)
            .accessibilityIdentifier("entity.contact.unlink")
    }

    private var settingsButton: some View {
        // Under denied it opens Settings; never asked, it shows the system prompt and says so (PB51).
        Button { Task { await viewModel.allowContacts() } } label: {
            buttonLabel(viewModel.access == .notAsked ? "Allow contacts" : "Allow contacts in Settings")
        }
            .buttonStyle(.bordered).tint(Theme.oliveOnFill)
            .accessibilityIdentifier("entity.contact.settings")
    }

    /// "Change": another contact, or "Unlink". Unlink asks nothing and offers no Undo: the owner can link again.
    private var changeMenu: some View {
        Menu {
            Button("Link to another contact", systemImage: "person.crop.circle") {
                Task { await openSearch() }
            }
            Button("Unlink", systemImage: "link") { viewModel.unlink(); onChange() }
                .accessibilityIdentifier("entity.contact.unlink")
        } label: {
            buttonLabel("Change")
        }
        .buttonStyle(.bordered).tint(Theme.oliveOnFill)
        .accessibilityIdentifier("entity.contact.change")
    }

    /// Asks first when access was never asked; opens the search only with access.
    private func openSearch() async {
        guard await viewModel.prepareSearch() else { return }
        heldBy = viewModel.heldByOthers()
        searching = true
    }

    /// The 44-point frame sits in the label, so it is the area a tap reaches. The text wraps at large sizes.
    private func buttonLabel(_ title: String) -> some View {
        Text(title)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    /// The search sheet: a pick links the person to that contact. A contact another person holds is refused by the
    /// link, and the row says who holds it.
    private var search: some View {
        NavigationStack {
            ScrollView {
                ContactSearchList(deps: viewModel.deps, heldBy: heldBy) { card in
                    searching = false
                    Task { await viewModel.link(card); onChange() }
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
            .linenBackground()
            .navigationTitle("Search your contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { searching = false } }
            }
        }
    }
}
