import Foundation
import LifelineKit

/// The photos one subject holds, cover first, and the three things a person does with them: add, make a cover,
/// remove. Every action goes through the library, then reads the shelf again. A failure goes to `onError`
/// with the page's own words; the shelf keeps what it last read.
@MainActor
@Observable
final class PhotoShelf {
    let subject: PhotoSubject
    private(set) var photos: [PlacedPhoto] = []
    /// True from the moment a picked file reaches the shelf until it is stored or refused.
    private(set) var isAdding = false
    @ObservationIgnored private let deps: Dependencies
    @ObservationIgnored private let onError: (String) -> Void

    /// Reads nothing: the page calls `load()` when it is on screen.
    init(subject: PhotoSubject, deps: Dependencies, onError: @escaping (String) -> Void) {
        self.subject = subject
        self.deps = deps
        self.onError = onError
    }

    var cover: Photo? { photos.first(where: \.isCover)?.photo }

    func load() {
        do { photos = try deps.extractionStore.photos.photos(of: subject) } catch { onError("Could not show the photos: \(error.localizedDescription)") }
    }

    func add(fileAt file: URL, assetLocalID: String?) async {
        isAdding = true
        defer { isAdding = false }
        do { _ = try await deps.photos.add(fileAt: file, assetLocalID: assetLocalID, to: subject) } catch {
            onError("Could not add this photo: \(error.localizedDescription)")
        }
        load()
    }

    func makeCover(_ photo: PhotoID) async {
        do { try await deps.photos.setCover(photo, of: subject) } catch {
            onError("Could not make this the cover: \(error.localizedDescription)")
        }
        load()
    }

    func remove(_ photo: PhotoID) async {
        do { try await deps.photos.remove(photo, from: subject) } catch {
            onError("Could not remove this photo: \(error.localizedDescription)")
        }
        load()
    }
}
