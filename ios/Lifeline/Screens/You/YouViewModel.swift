import Foundation
import LifelineKit

/// The You page (S3): the portrait read in one batch, the line that leads it, and the chosen chip.
/// `Portrait` decides what goes where; this keeps the lead across refreshes and the filter across taps.
@MainActor
@Observable
final class YouViewModel {
    private(set) var portrait: Portrait?
    private(set) var lead: PortraitLine?
    /// The chosen chip; nil is "All". Not remembered across launches.
    var tag: String?
    /// False until the first `refresh(newLead:)`: the page says nothing about being empty before it has read.
    private(set) var isLoaded = false
    private(set) var error: String?
    let deps: Dependencies

    /// Reads nothing: the page reads when it appears.
    init(deps: Dependencies) {
        self.deps = deps
    }

    /// One batched read. `newLead` picks the lead again (the root appeared); otherwise the lead stays
    /// while it can still lead (a session closed, Settings closed, a pushed page changed something).
    func refresh(newLead: Bool) {
        defer { isLoaded = true }
        do {
            let made = Portrait(try deps.extractionStore.portraitSource(), currentYear: CivilDate.today().year)
            portrait = made
            lead = made.lead(keeping: newLead ? nil : lead?.id, pick: deps.pickLead)
            // A chip whose tag is gone goes back to "All", so no chip shows selected that is not there.
            if let chosen = tag?.lowercased(), !tags.contains(where: { $0.lowercased() == chosen }) { tag = nil }
            error = nil
        } catch {
            self.error = "Could not read your page: \(error.localizedDescription)"
        }
    }

    /// The part's lines without the lead; "Who you are" only with the chosen tag.
    func lines(_ part: PortraitLine.Part) -> [PortraitLine] {
        portrait?.lines(part, leaving: lead?.id, tag: tag) ?? []
    }

    /// The chips after "All": the tags on the listed facts.
    var tags: [String] { portrait?.tags(leaving: lead?.id) ?? [] }

    /// What a story told from You is about: the owner, as "yourself".
    var ownerSubject: SessionSubject? {
        portrait?.owner.map { SessionSubject(entityID: $0.id, title: $0.title, isOwner: true, excludedFromAI: $0.excludedFromAI) }
    }

    /// A goal's "said in October": the session's start, which the app knows.
    func saidWhen(_ line: PortraitLine) -> String? {
        line.telling.map { Portrait.saidWhen($0.toldAt, now: .now, calendar: .current) }
    }
}
