import Foundation
import LifelineKit

/// The photos one subject holds, key photo first, and what a person does with them: add, change the order (a drag,
/// "Move to front", "Make this the key photo"), remove. Every action goes through the library, then reads the shelf again. A failure goes to `onError`
/// with the page's own words; the shelf keeps what it last read.
@MainActor
@Observable
final class PhotoShelf {
    let subject: PhotoSubject
    private(set) var photos: [PlacedPhoto] = []
    /// Adds in flight: from the moment a picked item arrives (before the system hands its file over, which is the long
    /// part for a photo in iCloud) until it is stored or refused. A count, so two picks never clear each other.
    private var adds = InFlightCount()
    /// "Adding the photo…" shows while this is true (decision 21).
    var isAdding: Bool { adds.isActive }
    /// Counts finished adds. The page passes it to its photos as `photoReloadKey`: an add can write a missing file
    /// back with the same name, and the open page must then load it.
    private(set) var addsFinished = 0
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

    /// The picker calls these around the hand-over; each `beginAdding()` must be paired with one `endAdding()`.
    func beginAdding() { adds.begin() }
    func endAdding() { adds.end() }

    func add(fileAt file: URL, assetLocalID: String?) async {
        beginAdding()
        defer { endAdding() }
        do { _ = try await deps.photos.add(fileAt: file, assetLocalID: assetLocalID, to: subject) } catch {
            onError("Could not add this photo: \(error.localizedDescription)")
        }
        load()
        addsFinished += 1
    }

    /// Moves `photo` to the front: it becomes the key photo.
    func makeCover(_ photo: PhotoID) async {
        do { try await deps.photos.setCover(photo, of: subject) } catch {
            onError("Could not make this the key photo: \(error.localizedDescription)")
        }
        load()
    }

    /// Stores `photos` as the page's order; the first is the key photo.
    func reorder(_ photos: [PhotoID]) async {
        do { try await deps.photos.reorder(photos, of: subject) } catch {
            onError("Could not change the order of the photos: \(error.localizedDescription)")
        }
        load()
    }

    /// A drag or "Move to front" ended at `index`. The kit gives the new order; a move that changes nothing writes nothing.
    func move(_ photo: PhotoID, to index: Int) async {
        guard let order = PhotoOrder.moving(photo, to: index, in: photos.map(\.id)) else { return }
        await reorder(order)
    }

    func remove(_ photo: PhotoID) async {
        do { try await deps.photos.remove(photo, from: subject) } catch {
            onError("Could not remove this photo: \(error.localizedDescription)")
        }
        load()
    }
}
