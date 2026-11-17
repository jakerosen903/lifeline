import LifelineKit
import SwiftUI

/// One photo in a sheet (decision 14): the photo fitted to the screen, its caption, "Make this the cover" when
/// it is not the cover, "Tell its story", "Remove photo…" (asks first) and "Done". Each action finishes, then the sheet closes,
/// so the page under it already shows the change. No zoom in S4.
struct PhotoViewer: View {
    let photo: PlacedPhoto
    let label: String
    let canMakeCover: Bool
    let cache: PhotoImageCache
    let onMakeCover: () async -> Void
    let onRemove: () async -> Void
    /// "Tell its story": called once the sheet has closed, so the session starts on a clear screen (decision 12).
    let onTellStory: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemove = false

    var body: some View {
        let caption = PhotoCaption.taken(photo.photo.takenAt)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // A frame with the photo's own shape, filled: the whole photo shows, uncropped.
                    PhotoImageView(photo: photo.photo, size: .large, cache: cache) { Theme.sand }
                        .aspectRatio(CGFloat(max(photo.photo.pixelWidth, 1)) / CGFloat(max(photo.photo.pixelHeight, 1)), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement()
                        .accessibilityLabel(label)
                        .accessibilityValue(caption ?? "")
                        .accessibilityAddTraits(.isImage)
                    if let caption {
                        Text(caption).font(.footnote).foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("photo.caption")
                    }
                    Button { dismiss(); onTellStory() } label: { fullWidth("Tell its story") }
                        .buttonStyle(.borderedProminent).tint(Theme.oliveOnFill)
                        .accessibilityIdentifier("photo.tellStory")
                    if canMakeCover {
                        Button { Task { await onMakeCover(); dismiss() } } label: { fullWidth("Make this the cover") }
                            .buttonStyle(.bordered).tint(Theme.oliveOnFill)
                            .accessibilityIdentifier("photo.makeCover")
                    }
                    Button(role: .destructive) { confirmingRemove = true } label: { fullWidth("Remove photo…") }
                        .buttonStyle(.bordered).tint(Theme.oliveOnFill)
                        .accessibilityIdentifier("photo.remove")
                }
                .padding(16)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("photo.viewer")
            .linenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done").foregroundStyle(Theme.ink).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("photo.done")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .confirmationDialog("Remove this photo?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove photo", role: .destructive) { Task { await onRemove(); dismiss() } }
                    .accessibilityIdentifier("photo.confirmRemove")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It leaves this page. The original stays in your photo library.")
            }
        }
    }

    /// The 44-point frame and the content shape sit in the label, so the tap area is the button's own.
    private func fullWidth(_ title: String) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}
