import Foundation
import LifelineKit

/// What the Things shelf shows: the groups and their tiles, each tile's key photo and quote.
/// It reads only when asked (`refresh`), never in `init`, and in a fixed number of statements.
@MainActor
@Observable
final class ThingsShelfViewModel: TagFiltering {
    let deps: Dependencies
    var tagFilter: String? { didSet { refresh() } }
    private(set) var layout: ThingShelf.Layout = .flat([])
    private(set) var keyPhotos: [EntityID: Photo] = [:]
    /// The quote of each shown thing that has one. A tile with a key photo does not show it.
    private(set) var quotes: [EntityID: String] = [:]
    private(set) var allTags: [String] = []
    /// The first read has run. Until then the screen shows no "Nothing yet" text.
    private(set) var isLoaded = false
    private(set) var error: String?

    init(deps: Dependencies) {
        self.deps = deps
    }

    /// True when the shelf has no tile to show.
    var isEmpty: Bool {
        switch layout {
        case .flat(let tiles): return tiles.isEmpty
        case .grouped(let groups): return groups.allSatisfy { $0.tiles.isEmpty }
        }
    }

    func refresh() {
        defer { isLoaded = true }
        do {
            let store = deps.extractionStore
            let source = try store.thingShelfSource()
            allTags = try store.tags.all()
            let tagged = try tagFilter.map { try store.tags.elements(.entity, tagged: $0) }
            let things = source.things.filter { tagged?.contains($0.id.rawValue) ?? true }
            layout = ThingShelf.layout(things, birthYear: source.birthYear)
            keyPhotos = source.keyPhotos
            var chosen: [EntityID: String] = [:]
            for thing in things {
                chosen[thing.id] = ThingQuote.choose(details: source.details[thing.id] ?? [], tellings: source.tellings,
                                                     heavySessions: source.heavySessions)
            }
            quotes = chosen
            error = nil
        } catch {
            self.error = "Could not show your things: \(error.localizedDescription)"
        }
    }
}
