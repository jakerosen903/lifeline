import LifelineKit
import os
import Photos
import UIKit

/// The person's photo library through PhotoKit. It reads only the Favorites album (full access) or the photos the
/// person allowed (limited access), and it never writes to the library (plan decision 10). The work runs off the
/// main actor.
struct LibraryPhotoPickSource: PhotoPickSource {
    func access() -> PhotoAccess {
        Self.access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// `.readWrite` is the only level that can read an album. The system shows its prompt only while it has not asked;
    /// after that it returns the person's answer at once.
    @concurrent func requestAccess() async -> PhotoAccess {
        Self.access(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    @concurrent func photos() async -> [LibraryPhoto] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets: PHFetchResult<PHAsset>
        switch access() {
        case .full:
            // No Favorites album (it can be missing on a new library) is an empty grid: the picker opens instead.
            guard let favorites = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil).firstObject
            else { return [] }
            assets = PHAsset.fetchAssets(in: favorites, options: options)
        case .limited:
            // Under limited access a fetch returns only the photos the person allowed.
            assets = PHAsset.fetchAssets(with: options)
        case .notAsked, .none:
            return []
        }
        return (0..<assets.count).map { LibraryPhoto(id: assets.object(at: $0).localIdentifier) }
    }

    /// From what is on the phone: a thumbnail never downloads. First the image at full quality; for a photo kept only in
    /// iCloud ("Optimize iPhone Storage") that is nil, and the phone's lower-quality copy is asked for next. Each request
    /// calls back exactly once, so the tile never waits on a second delivery that does not come. A cancelled task (the
    /// tile left the screen, the sheet closed) cancels its request and gets nil; the grid asks again when it needs to.
    /// The image is decoded here, so the grid draws it without decoding on the main thread.
    @concurrent func thumbnail(for photo: LibraryPhoto, side: CGFloat) async -> UIImage? {
        guard let asset = Self.asset(photo) else { return nil }
        let size = CGSize(width: side, height: side)
        var image = await Self.localImage(of: asset, size: size, delivery: .highQualityFormat)
        if image == nil, !Task.isCancelled { image = await Self.localImage(of: asset, size: size, delivery: .fastFormat) }
        return image?.preparingForDisplay() ?? image
    }

    /// One image request with the network off. In `.highQualityFormat` and `.fastFormat` PhotoKit calls back once, and
    /// that call is the answer whatever `PHImageResultIsDegradedKey` says. `ResumeOnce` still guards the continuation,
    /// because a cancel can race the callback.
    private static func localImage(of asset: PHAsset, size: CGSize, delivery: PHImageRequestOptionsDeliveryMode) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = delivery
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let request = OSAllocatedUnfairLock<(id: PHImageRequestID?, once: ResumeOnce<UIImage?>?)>(initialState: (nil, nil))
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let once = ResumeOnce<UIImage?>(continuation)
                let id = PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                    once.resume(image)
                }
                request.withLock { $0 = (id, once) }
                // Cancelled before `onCancel` could see the request: cancel it here.
                if Task.isCancelled {
                    PHImageManager.default().cancelImageRequest(id)
                    once.resume(nil)
                }
            }
        } onCancel: {
            let (id, once) = request.withLock { $0 }
            if let id { PHImageManager.default().cancelImageRequest(id) }
            once?.resume(nil)
        }
    }

    /// The edited version when the photo has one, as the grid shows it and as the system picker hands it over
    /// (`.current`); else the original. The system can download an iCloud original for this one photo.
    @concurrent func file(for photo: LibraryPhoto) async throws -> URL {
        guard let asset = Self.asset(photo) else { throw PhotoImport.Error.unreadable }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo })
        else { throw PhotoImport.Error.unreadable }
        // A picked copy by name, so launch removes one that a kill left behind.
        let copy = PickedPhotoCopy.url(in: FileManager.default.temporaryDirectory, extension: (resource.originalFilename as NSString).pathExtension)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: copy, options: options)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
        return copy
    }

    /// The one asset the person tapped in the grid, by its identifier: not a scan of the library.
    private static func asset(_ photo: LibraryPhoto) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [photo.id], options: nil).firstObject
    }

    private static func access(_ status: PHAuthorizationStatus) -> PhotoAccess {
        switch status {
        case .notDetermined: .notAsked
        case .authorized: .full
        case .limited: .limited
        case .denied, .restricted: .none
        @unknown default: .none
        }
    }
}
