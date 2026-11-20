import LifelineKit
import SwiftUI

/// The one sheet of "Tell a story about a photo": the explanation, the grid, or the picker, as
/// `PhotoStoryStart.route` says, with "Adding the photo…" and the S4 error line. Every path ends in this sheet's
/// dismissal, and only then does the session start (see `HomeViewModel.photoStartClosed`).
struct PhotoStoryStartSheet: View {
    let viewModel: PhotoStoryStartViewModel
    let pickPhotoPath: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .linenBackground()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .navigationDestination(isPresented: Binding(get: { viewModel.showsAllPhotos }, set: { viewModel.showsAllPhotos = $0 })) {
                    picker
                }
        }
        // While the out-of-process picker shows, a downward swipe scrolls it and must not pull the sheet down.
        .interactiveDismissDisabled(!PhotoStoryStart.allowsSwipeToDismiss(start: viewModel.start, showsAllPhotos: viewModel.showsAllPhotos))
        .task { if !viewModel.isLoaded { await viewModel.load() } }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.start {
        case nil: ProgressView()
        case .explain: PhotoAccessScreen { await viewModel.continueTapped() }
        case .grid(let heading): FavoritesGridScreen(heading: heading, viewModel: viewModel).statusLines(viewModel)
        case .picker: picker
        }
    }

    private var picker: some View {
        AllPhotosPicker(viewModel: viewModel, pickPhotoPath: pickPhotoPath).statusLines(viewModel)
    }
}

private extension View {
    /// "Adding the photo…" above the photos while one is stored, and the S4 error line pinned below.
    func statusLines(_ viewModel: PhotoStoryStartViewModel) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.isAdding { PhotoAddingLine().frame(maxWidth: .infinity) }
        }
        .photoErrorSlot(viewModel.error)
    }
}
