import SwiftUI

/// "Add a photo" in a page's "…" menu (the entity page, the memory page, You). It is disabled while the page's
/// photos are added, so two picks never run at the same time. With VoiceOver it says why it is dimmed.
struct AddPhotoButton: View {
    let isAdding: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button("Add a photo", systemImage: "photo", action: action)
            .disabled(isAdding)
            .accessibilityHint(isAdding ? "Photos are being added." : "")
            .accessibilityIdentifier(identifier)
    }
}
