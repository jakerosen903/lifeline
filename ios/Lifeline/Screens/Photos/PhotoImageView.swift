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
    private let images = NSCache<NSString, UIImage>()

    init(library: PhotoLibrary) {
        self.library = library
    }

    /// Nil when the file is missing or cannot be read; the view then keeps its placeholder.
    func image(for photo: Photo, size: PhotoImageSize) -> UIImage? {
        let key = "\(photo.fileName)@\(size.rawValue)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let decoded = try? PhotoImport.thumbnail(at: library.url(for: photo), maxPixel: size.rawValue) else { return nil }
        let image = UIImage(cgImage: decoded)
        images.setObject(image, forKey: key)
        return image
    }
}

/// A stored photo that fills the frame its parent gives it and is clipped to it. The placeholder shows
/// until the image is there, and stays when the image cannot load (decision 10: a missing file does not show).
struct PhotoImageView<Placeholder: View>: View {
    let photo: Photo
    let size: PhotoImageSize
    let cache: PhotoImageCache
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        // A clear rectangle takes the parent's frame; the image fills it as an overlay, so a wide photo never widens the layout.
        Rectangle().fill(.clear)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    placeholder()
                }
            }
            .clipped()
            .task(id: photo.fileName) {
                image = nil
                image = await cache.image(for: photo, size: size)
            }
    }
}
