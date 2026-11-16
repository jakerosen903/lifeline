import LifelineKit
import SwiftUI

/// "Often with" (S2, decision 3): who and what share two or more told moments with this page,
/// with the count. It shows only what the person told and links nothing new. The caller leaves it
/// out when there are no items: absent, not empty.
///
/// Each chip is a borderless Button, not a NavigationLink: a List row turns its links into one
/// row link (with a chevron), so a tap anywhere in the row opened the last chip, not the one tapped.
/// The caller pushes the page with `navigationDestination(item:)`.
struct OftenWithSection: View {
    let items: [CoOccurrence]
    let open: (Entity) -> Void

    var body: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(items, id: \.entity.id) { item in
                    Button { open(item.entity) } label: { chip(item) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(item.entity.title), \(item.sharedMoments) moments together")
                        .accessibilityIdentifier("entity.oftenWith")
                }
            }
        } header: {
            Text("Often with").sectionHeadingStyle()
        }
    }

    /// At least 44 points high. A title too long for the row wraps to two lines.
    private func chip(_ item: CoOccurrence) -> some View {
        HStack(spacing: 6) {
            Text(item.entity.title).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
            Text(String(item.sharedMoments)).monospacedDigit().foregroundStyle(Theme.secondaryText).fixedSize()
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.linen))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
