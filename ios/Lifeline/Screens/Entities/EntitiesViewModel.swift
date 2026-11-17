import Foundation
import LifelineKit

/// The rows of one kind of entity: People, Places and Things each have a tab; ideas list on You.
/// A free-text tag narrows any of them. The owner is never a row: their page is "About you" on You.
@MainActor
@Observable
final class EntitiesViewModel {
    let type: EntityType
    var tagFilter: String? { didSet { refresh() } }
    private(set) var rows: [EntitySummary] = []
    /// Each entity's cover photo, for People only: its tiles show them. Places and Things read none.
    private(set) var covers: [EntityID: Photo] = [:]
    private(set) var allTags: [String] = []
    /// The owner's own page: "About you" (M7), on the You tab.
    private(set) var aboutYou: Entity?
    private(set) var error: String?
    /// The first read has run. Until then a screen shows no "Nothing yet" text.
    private(set) var isLoaded = false
    let deps: Dependencies

    init(deps: Dependencies, type: EntityType) {
        self.deps = deps
        self.type = type
    }

    func refresh() {
        defer { isLoaded = true }
        do {
            let store = deps.extractionStore
            allTags = try store.tags.all()
            let tagged = try tagFilter.map { try store.tags.elements(.entity, tagged: $0) }
            let owner = try store.profile.owner()?.entityID
            aboutYou = try owner.flatMap { try store.entities.entity(id: $0) }
            rows = try store.entities.summaries(type: type)
                .filter { $0.id != owner && (tagged?.contains($0.id.rawValue) ?? true) }
            // One statement, whatever the number of people.
            covers = type == .person ? try store.photos.covers(type: .person) : [:]
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
