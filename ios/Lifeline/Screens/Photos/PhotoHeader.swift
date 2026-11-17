import LifelineKit
import SwiftUI

/// The cover at the top of a page (decision 12): inside the margins, rounded, filled and clipped; 4:3 for a
/// landscape cover and 3:4 for a portrait one, so a portrait photo is not cut to a strip. Nothing sits on it.
/// The caption sits under it when the date is known. A tap opens the viewer.
struct PhotoHeader: View {
    let cover: Photo
    let label: String
    let cache: PhotoImageCache
    let onOpen: () -> Void

    private var isPortrait: Bool { cover.pixelHeight > cover.pixelWidth }

    var body: some View {
        let caption = PhotoCaption.taken(cover.takenAt)
        let shape = RoundedRectangle(cornerRadius: 22)
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                PhotoImageView(photo: cover, size: .large, cache: cache) { Theme.sand }
                    .aspectRatio(isPortrait ? 3.0 / 4.0 : 4.0 / 3.0, contentMode: .fit)
                    .clipShape(shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(caption ?? "")
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("photo.header")
            if let caption {
                Text(caption).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.caption")
            }
        }
    }
}
