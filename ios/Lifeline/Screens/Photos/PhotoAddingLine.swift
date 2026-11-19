import LifelineKit
import SwiftUI

/// "Adding the photo…" (or "Adding photo {i} of {n}…") with a spinner, where the photo will go (decision 21). It
/// shows only while a photo is being added, so a page without a photo never shows an empty frame.
struct PhotoAddingLine: View {
    var text = PhotoAddProgress.line(adding: 1, of: 1)

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text).font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photo.adding")
    }
}
