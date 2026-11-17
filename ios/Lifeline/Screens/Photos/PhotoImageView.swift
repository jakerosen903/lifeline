import LifelineKit
import SwiftUI
import UIKit

/// The two decode sizes (decision 17): tiles and the row, then the header and the viewer.
enum PhotoImageSize: Int, Sendable {
    case small = 400
    case large = 1600
}

/// Decodes stored photos with ImageIO downsampling, on this actor, never on the main thread. Each file and
/// size decodes once: the check and the insert have no suspension point between them, so two views asking
/// for the same image at once still decode it once.
actor PhotoImageCache {
    private let library: PhotoLibrary
    /// `NSCache` is thread-safe, so `cached(_:size:)` reads it outside the actor; every write stays on the actor.
    private nonisolated(unsafe) let images = NSCache<NSString, UIImage>()

    init(library: PhotoLibrary) {
        self.library = library
    }

    /// Nil when the file is missing or cannot be read; the view then keeps its placeholder. A miss is not cached,
    /// so a file written back later (a repeat add repairs it) decodes on the next call.
    func image(for photo: Photo, size: PhotoImageSize) -> UIImage? {
        let key = Self.key(photo, size)
        if let cached = images.object(forKey: key) { return cached }
        guard let decoded = try? PhotoImport.thumbnail(at: library.url(for: photo), maxPixel: size.rawValue) else { return nil }
        let image = UIImage(cgImage: decoded)
        images.setObject(image, forKey: key)
        return image
    }

    /// An image already decoded, or nil. No decode and no wait: a view reads it while it is made, so a cached
    /// photo shows at once with no placeholder in between. `NSCache` is thread-safe.
    nonisolated func cached(_ photo: Photo, size: PhotoImageSize) -> UIImage? {
        images.object(forKey: Self.key(photo, size))
    }

    private nonisolated static func key(_ photo: Photo, _ size: PhotoImageSize) -> NSString { "\(photo.fileName)@\(size.rawValue)" as NSString }
}

extension EnvironmentValues {
    /// Changes when a page's shelf finishes an add, so an open page loads again a file the add wrote back.
    @Entry var photoReloadKey = 0
}

/// A stored photo that fills the frame its parent gives it and is clipped to it. A cached image shows at once;
/// otherwise the placeholder shows until the image is decoded, and stays when the image cannot load (decision 10:
/// a missing file does not show).
struct PhotoImageView<Placeholder: View>: View {
    let photo: Photo
    let size: PhotoImageSize
    let cache: PhotoImageCache
    @ViewBuilder let placeholder: () -> Placeholder
    @Environment(\.photoReloadKey) private var reloadKey
    /// The last image this view decoded, with its file: the cache may drop it, and it must never show for another photo.
    @State private var loaded: (fileName: String, image: UIImage)?

    private var shown: UIImage? {
        cache.cached(photo, size: size) ?? (loaded?.fileName == photo.fileName ? loaded?.image : nil)
    }

    private struct Load: Hashable {
        let fileName: String
        let reloadKey: Int
    }

    var body: some View {
        // A clear rectangle takes the parent's frame; the image fills it as an overlay, so a wide photo never widens the layout.
        Rectangle().fill(.clear)
            .overlay {
                if let image = shown {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    placeholder()
                }
            }
            .clipped()
            .task(id: Load(fileName: photo.fileName, reloadKey: reloadKey)) {
                guard cache.cached(photo, size: size) == nil else { return }
                let fileName = photo.fileName
                if let image = await cache.image(for: photo, size: size) { loaded = (fileName, image) }
            }
    }
}
