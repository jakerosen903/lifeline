import LifelineKit
import SwiftUI

extension View {
    /// The photo viewer's sheet, with "Tell its story" wired. The viewer calls `tellStory` with the photo; the
    /// session starts once the sheet has closed, never while it is leaving (plan decision 12). It takes the
    /// photo and the home model and nothing about the screen, so any screen that shows photos can use it.
    /// `tellStory` is nil where no session can start: there is no home model (a screen inside the session or
    /// landing cover), or a cover is up. A start there would do nothing, or replace an unanswered landing.
    func photoViewerSheet<Viewer: View>(item: Binding<PlacedPhoto?>, home: HomeViewModel?,
                                        @ViewBuilder viewer: @escaping (PlacedPhoto, _ tellStory: (() -> Void)?) -> Viewer) -> some View {
        modifier(PhotoViewerSheet(item: item, home: home, viewer: viewer))
    }
}

private struct PhotoViewerSheet<Viewer: View>: ViewModifier {
    @Binding var item: PlacedPhoto?
    let home: HomeViewModel?
    let viewer: (PlacedPhoto, _ tellStory: (() -> Void)?) -> Viewer
    /// "Tell its story" was tapped: the session starts when the viewer has closed.
    @State private var tellingStoryOf: Photo?

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: startPendingStory) { placed in
            viewer(placed, canStartSession ? { tellingStoryOf = placed.photo } : nil)
        }
    }

    private var canStartSession: Bool {
        guard let home else { return false }
        return home.presented == nil
    }

    private func startPendingStory() {
        guard let photo = tellingStoryOf else { return }
        tellingStoryOf = nil
        Task { await home?.startPhotoSession(photo) }
    }
}
