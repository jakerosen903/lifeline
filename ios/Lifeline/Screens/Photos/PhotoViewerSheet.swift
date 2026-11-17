import LifelineKit
import SwiftUI

extension View {
    /// The photo viewer's sheet, with "Tell its story" wired. The viewer calls `tellStory` with the photo; the
    /// session starts once the sheet has closed, never while it is leaving (plan decision 12). It takes the
    /// photo and the home model and nothing about the screen, so any screen that shows photos can use it.
    func photoViewerSheet<Viewer: View>(item: Binding<PlacedPhoto?>, home: HomeViewModel?,
                                        @ViewBuilder viewer: @escaping (PlacedPhoto, _ tellStory: @escaping () -> Void) -> Viewer) -> some View {
        modifier(PhotoViewerSheet(item: item, home: home, viewer: viewer))
    }
}

private struct PhotoViewerSheet<Viewer: View>: ViewModifier {
    @Binding var item: PlacedPhoto?
    let home: HomeViewModel?
    let viewer: (PlacedPhoto, _ tellStory: @escaping () -> Void) -> Viewer
    /// "Tell its story" was tapped: the session starts when the viewer has closed.
    @State private var tellingStoryOf: Photo?

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: startPendingStory) { placed in
            viewer(placed) { tellingStoryOf = placed.photo }
        }
    }

    private func startPendingStory() {
        guard let photo = tellingStoryOf else { return }
        tellingStoryOf = nil
        Task { await home?.startPhotoSession(photo) }
    }
}
