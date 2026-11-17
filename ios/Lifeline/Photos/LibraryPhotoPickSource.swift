import LifelineKit
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

    /// One result per request (`highQualityFormat`), from what is on the phone: a thumbnail never downloads.
    /// The image is decoded here, so the grid draws it without decoding on the main thread.
    @concurrent func thumbnail(for photo: LibraryPhoto, side: CGFloat) async -> UIImage? {
        guard let asset = Self.asset(photo) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill,
                                                  options: options) { image, info in
                // A degraded image comes only in opportunistic mode; skipping one keeps this to a single resume anyway.
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                continuation.resume(returning: image)
            }
        }
        return image?.preparingForDisplay() ?? image
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
