import SwiftUI

/// The person's Favorites (or the photos they allowed), newest first, under its heading, with "All photos" for the
/// system picker. A tap on a photo starts its story: there is no second confirmation. Each photo's label says only
/// that it is a photo and where it sits; the app never says what a photo shows.
struct FavoritesGridScreen: View {
    let heading: String
    let viewModel: PhotoStoryStartViewModel
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var cell: CGFloat = 104

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(heading)
                    .font(.system(.title, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("favorites.heading")
                // Above the grid, so it is in reach however many favorites there are.
                Button { viewModel.showsAllPhotos = true } label: {
                    Label("All photos", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Theme.oliveOnFill)
                .accessibilityIdentifier("favorites.allPhotos")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: 4)], spacing: 4) {
                    ForEach(Array(viewModel.photos.enumerated()), id: \.element.id) { index, photo in
                        FavoriteTile(photo: photo, position: index + 1, viewModel: viewModel, side: cell * displayScale)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("favorites.grid")
            }
            .padding(16)
        }
    }
}
