import LifelineKit
import SwiftUI

/// The photo a session is about, at the top of the session screen. It shows the whole photo, never cropped,
/// and never more than `maxHeight` tall, so the question and Finish stay in reach at the largest text size.
/// Its accessibility label is the S4 caption's pair: "Photo for this story", with "taken …" as the value.
/// The app never says what the photo shows.
struct SessionPhoto: View {
    static let label = "Photo for this story"
    private static let maxHeight: CGFloat = 220

    let photo: Photo
    let cache: PhotoImageCache

    var body: some View {
        let ratio = CGFloat(max(photo.pixelWidth, 1)) / CGFloat(max(photo.pixelHeight, 1))
        PhotoImageView(photo: photo, size: .large, cache: cache) { Theme.sand }
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxHeight: Self.maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel(Self.label)
            .accessibilityValue(PhotoCaption.taken(photo.takenAt) ?? "")
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("session.photo")
    }
}
