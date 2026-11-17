import LifelineKit
import SwiftUI

/// "Photos" (decision 13): every photo the subject holds, cover first, then in the order added, as small
/// square buttons in one scrolling line. A tap opens the viewer. The heading sits in the row, as "Tags" does.
struct PhotoRow: View {
    let photos: [PlacedPhoto]
    let label: String
    let cache: PhotoImageCache
    let onOpen: (PlacedPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos").sectionHeadingStyle()
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(photos) { placed in thumb(placed) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func thumb(_ placed: PlacedPhoto) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return Button { onOpen(placed) } label: {
            PhotoImageView(photo: placed.photo, size: .small, cache: cache) { Theme.sand }
                .frame(width: 88, height: 88)
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(PhotoCaption.taken(placed.photo.takenAt) ?? "")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("photo.thumb")
    }
}
