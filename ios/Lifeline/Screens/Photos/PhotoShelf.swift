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
