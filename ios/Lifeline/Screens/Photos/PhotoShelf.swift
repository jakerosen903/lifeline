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
    /// Adds in flight, one per `add` call, inside a pick or not (a pick calls `add` once per photo): a count, so two
    /// adds never clear each other. Outside a pick it alone shows the adding line.
    private var adds = InFlightCount()
    /// The picks in flight (part 4): from the moment the picked items arrive (before the system hands a file over,
    /// which is the long part for a photo in iCloud) until the last is stored or refused.
    private var picks = PhotoAddBatch()
    /// The adding line shows while this is true (decision 21).
    var isAdding: Bool { adds.isActive || picks.isActive }
    /// "Adding photo {i} of {n}…", or "Adding the photo…" for one photo; nil when nothing is added.
    var addingLine: String? { picks.line ?? (adds.isActive ? PhotoAddProgress.line(adding: 1, of: 1) : nil) }
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
    /// Counts the reads that found another cover than the read before. The page watches it and goes back to the top,
    /// where the new cover is. The first read is not counted: it sets the cover the page opens with. A scroll in the
    /// page's first layout put a tall List at its bottom (the largest text size on an iPhone 17 Pro Max).
    private(set) var coverChanges = 0
    @ObservationIgnored private var hasRead = false

    func load() {
        let before = cover?.id
        do { photos = try deps.extractionStore.photos.photos(of: subject) } catch { onError("Could not show the photos: \(error.localizedDescription)") }
        if hasRead, cover?.id != before { coverChanges += 1 }
        hasRead = true
    }

    /// The flow calls these around a pick of `count` photos: `beginAdding(count:)`, then `finishedOne()` after each
    /// photo, then `endAdding()`, which shows the one failure line of the pick, if any.
    func beginAdding(count: Int) { picks.begin(count: count) }
    func finishedOne() { picks.finishOne() }
    func endAdding() { if let line = picks.end() { onError(line) } }

    /// A photo that could not be added: counted for the pick's one line, or shown at once outside a pick.
    /// `reason` is the error's own words.
    func failed(_ reason: String) {
        if picks.isActive { picks.fail(reason) } else { PhotoAddProgress.failureLine(failed: 1, lastError: reason).map(onError) }
    }

    /// Adds one photo last in the page's order. A photo the page holds already is found by its hash and not added again.
    func add(fileAt file: URL, assetLocalID: String?) async {
        adds.begin()
        defer { adds.end() }
        do { _ = try await deps.photos.add(fileAt: file, assetLocalID: assetLocalID, to: subject) } catch {
            failed(error.localizedDescription)
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
