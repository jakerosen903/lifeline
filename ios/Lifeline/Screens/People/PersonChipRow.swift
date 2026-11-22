import LifelineKit
import SwiftUI

/// "With" and one person chip on each line, on a card, the landing and the memory page. A chip is as wide as
/// its row, so at the largest text sizes nothing truncates: the chips stack and their lines wrap. A tap opens
/// the "Who is this?" sheet for that chip; the host hears what "Done" did.
struct PersonChipRow: View {
    /// One chip and what its sheet works on.
    struct Item: Identifiable {
        let id: String
        let name: String
        let person: PersonID?
        let origin: LinkOrigin?
        let saidName: String?
        let source: WhoIsThisViewModel.Source
        /// A waiting card's name the owner marked "Not a person": a quiet chip with the said name (R37).
        var isNotAPerson = false
        /// The person is one Keep made, or will make, from a contact.
        let fromContact: Bool

        /// `contacts` is what the app saw of the contacts for this chip's said name (PB1).
        func line(contacts: PersonChipLine.ContactsSeen) -> String? {
            isNotAPerson ? nil : PersonChipLine.text(origin: origin, saidName: saidName, fromContact: fromContact, contacts: contacts)
        }
        var accessibilityLabel: String {
            isNotAPerson ? PersonChipLine.notAPersonLabel(saidName: saidName ?? name)
                         : PersonChipLine.accessibilityLabel(name: name, origin: origin, saidName: saidName, fromContact: fromContact)
        }
        var identifier: String {
            if isNotAPerson { return "person.chip.notPerson" }
            return origin == .assumed ? "person.chip.assumed" : "person.chip"
        }

        /// A kept memory's link. The owner's link has no mark and still opens the sheet.
        init(link: PersonLink) {
            id = link.id; name = link.person.displayName; person = link.person.id
            origin = link.origin; saidName = link.saidName; fromContact = link.personFromContact
            source = .link(link)
        }

        /// What Keep will link on a card that waits.
        init(chip: PreviewChip, on candidate: Candidate) {
            id = "\(candidate.id.rawValue)|\(chip.id)|\(chip.person?.rawValue ?? chip.name)"
            name = chip.name; person = chip.person
            origin = chip.origin; saidName = chip.saidName; fromContact = chip.fromContact
            source = .waiting(candidate: candidate, chip: chip)
            isNotAPerson = chip.isNotAPerson
        }
    }

    let items: [Item]
    let deps: Dependencies
    let onDone: (WhoIsThisViewModel.Outcome) -> Void

    /// The open sheet's model, made once at the tap: the row's body re-runs (the landing polls each second)
    /// and must not read the people again each time.
    @State private var asking: Asking?

    private struct Asking: Identifiable {
        let id: String
        let model: WhoIsThisViewModel
    }
    @State private var covers: [EntityID: Photo] = [:]
    /// What each "New" chip's line says about the contacts, worked out in the row's task, not on each render (PB1).
    @State private var contactsSeen: [Item.ID: PersonChipLine.ContactsSeen] = [:]

    /// Only a "New" chip's line names the contacts; the others skip the scan.
    private static func contactsSeen(for items: [Item], deps: Dependencies) -> [Item.ID: PersonChipLine.ContactsSeen] {
        let fresh = items.filter { $0.origin == .new && !$0.isNotAPerson }
        guard !fresh.isEmpty else { return [:] }
        let held = deps.heldContactIdentifiers()
        return Dictionary(fresh.map { ($0.id, deps.contactsSeen(saidName: $0.saidName, held: held)) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("With").font(.caption.weight(.semibold)).foregroundStyle(Theme.oliveText)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { item in
                    PersonChip(name: item.name, line: item.line(contacts: contactsSeen[item.id] ?? .none), isAssumed: item.origin == .assumed && !item.isNotAPerson,
                               accessibilityLabel: item.accessibilityLabel, identifier: item.identifier,
                               personID: item.person, cover: item.person.flatMap { covers[EntityID(rawValue: $0.rawValue)] },
                               cache: deps.photoImages) {
                        asking = Asking(id: item.id, model: WhoIsThisViewModel(source: item.source, deps: deps))
                    }
                }
            }
            // Read again when a chip's person or origin changes (a look again after access links people to contacts),
            // or when the access or the contacts read change.
            .task(id: items.map { "\($0.id)|\($0.person?.rawValue ?? "")|\($0.origin?.rawValue ?? "")" }
                      + [deps.contacts.access().rawValue, String(deps.contactsCache.cards.count)]) {
                covers = (try? deps.extractionStore.photos.covers(type: .person)) ?? [:]
                contactsSeen = Self.contactsSeen(for: items, deps: deps)
            }
            .sheet(item: $asking) { asking in
                WhoIsThisSheet(viewModel: asking.model) { outcome in
                    self.asking = nil
                    onDone(outcome)
                }
            }
        }
    }
}
