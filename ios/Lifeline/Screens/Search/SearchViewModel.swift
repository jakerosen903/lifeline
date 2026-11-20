import Foundation
import LifelineKit

/// Search: a query run against an index read off the main actor. It holds no matching rule
/// (`Search.run` does) and keeps nothing typed: the query lives only in memory (decision 19).
@MainActor
@Observable
final class SearchViewModel {
    /// Each change runs the search again on the index in hand.
    var query = "" { didSet { if query != oldValue { run() } } }
    /// Nil for the opening state: an empty query, one with no letter or digit, or no index yet.
    private(set) var results: SearchResults?
    /// Each person's cover photo, for the faces in the People group.
    private(set) var covers: [EntityID: Photo] = [:]
    /// The first read has come back. A query typed before it runs when it does (decision 22).
    private(set) var isLoaded = false
    /// The read failed. It holds the database's reason, never the query.
    private(set) var error: String?
    let deps: Dependencies

    private var index = SearchIndex.empty
    /// The number of the latest read: an older read that comes back later is dropped.
    private var latestRead = 0

    init(deps: Dependencies) {
        self.deps = deps
    }

    /// Reads the index and the covers again (the screen appears, a page reports a change, a session cover closes).
    func refresh() {
        latestRead += 1
        let read = latestRead
        let store = deps.extractionStore
        // The index reads the `word` table, the largest in the archive: not on the main actor.
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = Result { (index: try store.searchIndex(), covers: try store.photos.covers(type: .person)) }
            await self?.finish(read, outcome)
        }
    }

    private func finish(_ read: Int, _ outcome: Result<(index: SearchIndex, covers: [EntityID: Photo]), any Error>) {
        guard read == latestRead else { return }
        isLoaded = true
        switch outcome {
        case .success(let loaded):
            index = loaded.index
            covers = loaded.covers
            error = nil
            run()
        case .failure(let failure):
            error = "Could not search: \(failure.localizedDescription)"
        }
    }

    private func run() {
        results = isLoaded ? Search.run(query, in: index) : nil
    }
}
