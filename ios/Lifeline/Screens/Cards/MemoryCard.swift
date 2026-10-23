import LifelineKit
import SwiftUI

/// "Sounds like a memory": the title in the owner's words, the quote, time phrases in ochre,
/// people chips, and two choices. Swipe left dismisses.
struct MemoryCard: View {
    let memory: MemoryOut
    let confidence: Double
    let onAdd: () -> Void
    let onDismiss: () -> Void

    @State private var offset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sounds like a memory")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.olive)
            Text(memory.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("card.title")
            Text("“\(memory.quote)”")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.stone)
                .lineLimit(4)
            if !memory.anchors.isEmpty {
                Text(memory.anchors.map(\.phrase).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.ochre)
            }
            if !memory.peopleRefs.isEmpty || memory.placeText != nil {
                FlowChips(items: memory.peopleRefs + (memory.placeText.map { [$0] } ?? []))
            }
            HStack(spacing: 12) {
                Button("Add to timeline", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("card.add")
                Button("Not quite", action: onDismiss)
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("card.dismiss")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .opacity(confidence < 0.5 ? 0.7 : 1)
        .offset(x: offset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in offset = min(0, value.translation.width) }
                .onEnded { value in
                    if value.translation.width < -120 { onDismiss() } else { withAnimation { offset = 0 } }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.memory")
    }
}

/// People and place chips, wrapping.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.linen))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}
