import Foundation
import LifelineKit
import PhotosUI
import SwiftUI
import UIKit

/// "Tell a story about a photo", from the tap to a stored photo: the explanation and the system prompt the first
/// time, then the grid or the picker (`PhotoStoryStart.route`). A tapped or picked photo is stored with no link and
/// handed to `onChosen`; the sheet then closes, and the session starts once it is gone. A failure shows the S4 error
/// line and starts nothing.
@MainActor
@Observable
final class PhotoStoryStartViewModel: Identifiable {
    let id = UUID()
    /// Nil until `load()` has read the access.
    private(set) var start: PhotoStoryStart?
    var isLoaded: Bool { start != nil }
    /// The grid's photos, newest first.
    private(set) var photos: [LibraryPhoto] = []
    /// Each thumbnail is read and decoded once, then kept while the grid is up. One that could not be read is asked again.
    private(set) var thumbnails: [String: UIImage] = [:]
    /// "Adding the photo…" shows while this is true.
    private(set) var isAdding = false
    private(set) var error: String?
    /// "All photos" was tapped in the grid: the picker shows in the same sheet.
    var showsAllPhotos = false
    @ObservationIgnored private let source: any PhotoPickSource
    @ObservationIgnored private let library: PhotoLibrary
    @ObservationIgnored private let onChosen: (PhotoStoryStartViewModel, Photo) -> Void
    @ObservationIgnored private var thumbnailsAsked: Set<String> = []
    /// The sheet closed with no photo chosen: a copy still on its way is not stored.
    @ObservationIgnored private(set) var isCancelled = false

    /// Reads nothing: the sheet calls `load()` when it is on screen.
    init(source: any PhotoPickSource, library: PhotoLibrary, onChosen: @escaping (_ from: PhotoStoryStartViewModel, _ photo: Photo) -> Void) {
        self.source = source
        self.library = library
        self.onChosen = onChosen
    }

    /// The access as it is now, so a change made in Settings between two starts applies to this one.
    func load() async {
        let access = source.access()
        if access == .notAsked { start = .explain } else { await show(access) }
    }

    /// "Continue" on the explanation: the system prompt, then what its answer allows.
    func continueTapped() async {
        let access = await source.requestAccess()
        // The system always answers; a status still "not asked" would only bring the explanation back, so it counts as none.
        await show(access == .notAsked ? .none : access)
    }

    private func show(_ access: PhotoAccess) async {
        photos = await source.photos()
        start = PhotoStoryStart.route(access: access, photoCount: photos.count)
    }

    func thumbnail(for photo: LibraryPhoto, side: CGFloat) async {
        guard thumbnailsAsked.insert(photo.id).inserted else { return }
        // Nil is forgotten, so the tile asks again the next time it appears.
        if let image = await source.thumbnail(for: photo, side: side) { thumbnails[photo.id] = image } else { thumbnailsAsked.remove(photo.id) }
    }

    /// The sheet closed before a photo was chosen ("Cancel" or a swipe), perhaps while one is being copied.
    func cancel() { isCancelled = true }

    /// A tap in the grid: copies the original, stores it unless the sheet closed meanwhile, removes the copy.
    /// A second tap while one adds does nothing.
    func pick(_ photo: LibraryPhoto) async {
        await adding {
            try await CancellablePhotoStore.fetchAndStore(fetch: { try await source.file(for: photo) }, assetLocalID: photo.id,
                                                          into: library, isCancelled: { isCancelled })
        }
    }

    /// A photo from the system picker, through the S4 picked-copy path, which removes its copy. "Adding the photo…"
    /// shows from now: the hand-over can take seconds for a photo in iCloud.
    func picked(_ item: PhotosPickerItem) async {
        await adding {
            var stored: Result<Photo?, any Error> = .failure(PhotoImport.Error.unreadable)
            try await PickedPhotoFile.receive(item) { file, assetLocalID in
                do { stored = .success(try await self.store(file, assetLocalID: assetLocalID)) } catch { stored = .failure(error) }
            }
            return try stored.get()
        }
    }

    /// Under `-uiTesting-pickPhoto`: the test's file, which the test owns and which stays.
    func picked(fileAt file: URL) async {
        await adding { try await store(file, assetLocalID: nil) }
    }

    private func store(_ file: URL, assetLocalID: String?) async throws -> Photo? {
        try await CancellablePhotoStore.store(fileAt: file, assetLocalID: assetLocalID, into: library, isCancelled: { isCancelled })
    }

    /// Nil from `store`: the sheet was cancelled, so nothing was stored and nothing starts.
    private func adding(_ store: () async throws -> Photo?) async {
        guard !isAdding else { return }
        isAdding = true
        error = nil
        defer { isAdding = false }
        do {
            if let photo = try await store() { onChosen(self, photo) }
        } catch {
            self.error = "Could not add this photo: \(error.localizedDescription)"
        }
    }
}
