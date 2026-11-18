import SwiftUI

/// The app's own words before the system asks for the photo library. It shows only while the system has not asked,
/// so it shows once. "Continue" brings the system prompt.
struct PhotoAccessScreen: View {
    let onContinue: () async -> Void
    @State private var asking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "photo.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.olive)
                    .accessibilityHidden(true)
                Text("Lifeline will ask to see your photos. They stay on this phone. Lifeline shows them only so you can pick one.")
                    .font(.title3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    asking = true
                    Task {
                        await onContinue()
                        asking = false
                    }
                } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.olive)
                .disabled(asking)
                .accessibilityIdentifier("photoAccess.continue")
            }
            .padding(24)
        }
    }
}
