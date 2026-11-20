import SwiftUI
import UIKit

/// One square photo of the Favorites grid. The tile owns its image: an arrival redraws this tile only, never the
/// whole grid during a fling. A cached thumbnail shows at once; otherwise sand shows until the thumbnail arrives,
/// and stays when it cannot be read. Its label says only that it is a photo and where it sits.
struct FavoriteTile: View {
    let photo: LibraryPhoto
    let position: Int
    let viewModel: PhotoStoryStartViewModel
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Button { Task { await viewModel.pick(photo) } } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    // The view model's cache is not observed: reading it here costs no redraw when another tile's image arrives.
                    if let shown = image ?? viewModel.cachedThumbnail(for: photo) {
                        Image(uiImage: shown).resizable().scaledToFill()
                    } else {
                        Theme.sand
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isAdding)
        // Cancelled when the tile leaves the screen; a cancelled read returns nil and the tile keeps its placeholder.
        .task(id: photo.id) {
            guard image == nil else { return }
            image = await viewModel.thumbnail(for: photo, side: side)
        }
        .accessibilityLabel("Photo")
        .accessibilityValue("\(position) of \(viewModel.photos.count)")
        .accessibilityIdentifier("favorites.photo")
    }
}
