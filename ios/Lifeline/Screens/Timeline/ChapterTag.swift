import SwiftUI

/// The chapter a moment belongs to, as the person named it: one line, truncated. Read only in
/// S6a; a tap does nothing yet (the chapter's sheet comes in S6c).
struct ChapterTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.oliveOnFill)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.olive.opacity(0.2), in: Capsule())
            .accessibilityIdentifier("timeline.tag")
    }
}
