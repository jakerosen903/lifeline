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

        // PB1: `contacts: .none` until Task 5 passes what the contacts cache saw.
        var line: String? {
            isNotAPerson ? nil : PersonChipLine.text(origin: origin, saidName: saidName, fromContact: fromContact, contacts: .none)
        }
        var accessibilityLabel: String {
            isNotAPerson ? PersonChipLine.notAPersonLabel(saidName: saidName ?? name)
                         : PersonChipLine.accessibilityLabel(name: name, origin: origin, saidName: saidName)
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

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("With").font(.caption.weight(.semibold)).foregroundStyle(Theme.oliveText)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { item in
                    PersonChip(name: item.name, line: item.line, isAssumed: item.origin == .assumed && !item.isNotAPerson,
                               accessibilityLabel: item.accessibilityLabel, identifier: item.identifier,
                               personID: item.person, cover: item.person.flatMap { covers[EntityID(rawValue: $0.rawValue)] },
                               cache: deps.photoImages) {
                        asking = Asking(id: item.id, model: WhoIsThisViewModel(source: item.source, deps: deps))
                    }
                }
            }
            .task { covers = (try? deps.extractionStore.photos.covers(type: .person)) ?? [:] }
            .sheet(item: $asking) { asking in
                WhoIsThisSheet(viewModel: asking.model) { outcome in
                    self.asking = nil
                    onDone(outcome)
                }
            }
        }
    }
}
