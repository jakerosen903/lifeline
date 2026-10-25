import Foundation
import LifelineKit

/// People, Places, Things and Ideas: one screen, one segment per type (M7). A free-text tag
/// narrows any of them.
@MainActor
@Observable
final class EntitiesViewModel {
    struct Row: Identifiable, Hashable {
        let entity: Entity
        let spanText: String
        let count: Int
        var id: EntityID { entity.id }
    }

    var type: EntityType = .thing { didSet { refresh() } }
    var tagFilter: String? { didSet { refresh() } }
    private(set) var rows: [Row] = []
    private(set) var allTags: [String] = []
    /// The owner's own page: "About you" (M7), in the People segment.
    private(set) var aboutYou: Entity?
    private(set) var error: String?
    let deps: Dependencies

    init(deps: Dependencies, type: EntityType = .thing) {
        self.deps = deps
        self.type = type
        refresh()
    }

    func refresh() {
        do {
            let store = deps.extractionStore
            allTags = try store.tags.all()
            let tagged = try tagFilter.map { try store.tags.elements(.entity, tagged: $0) }
            let owner = try store.profile.owner()?.entityID
            aboutYou = try owner.flatMap { try store.entities.entity(id: $0) }
            rows = try store.entities.entities(type: type)
                .filter { $0.id != owner && (tagged?.contains($0.id.rawValue) ?? true) }
                .map { entity in
                    Row(entity: entity, spanText: EntityPage.spanText(try store.entities.span(of: entity.id)),
                        count: try store.entities.links(to: entity.id).count)
                }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
