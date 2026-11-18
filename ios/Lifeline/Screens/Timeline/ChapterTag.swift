import SwiftUI

/// The chapter a moment belongs to, as the person named it: one line, truncated. A tap opens the
/// chapter's sheet. It sits outside the row's main button, so it is an element of its own (S6a R15).
struct ChapterTag: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.oliveOnFill)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.olive.opacity(0.2), in: Capsule())
                // A taller target than the capsule, with the same look: the space above and below answers too.
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter: \(title)")
        .accessibilityIdentifier("timeline.tag")
    }
}
