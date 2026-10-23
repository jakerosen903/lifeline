import LifelineKit
import SwiftUI

/// "Sounds like a memory": the title in the owner's words, the quote, time phrases in ochre,
/// people chips, and three choices: Keep, Change…, Dismiss. Low confidence is a word, never a
/// fade. Swipe left also dismisses; the button is the visible way.
struct MemoryCard: View {
    let memory: MemoryOut
    let confidence: Double
    let onKeep: () -> Void
    let onChange: () -> Void
    let onDismiss: () -> Void

    @State private var offset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(memory.kindOrDefault.cardLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.olive)
                Spacer()
                ForEach(CheckThisTags.tags(range: .unplaced, mentions: [], confidence: confidence), id: \.label) { tag in
                    CheckThisTag(tag: tag)
                }
            }
            Text(memory.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("card.title")
            Text("“\(memory.quote)”")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.stone)
                .lineLimit(4)
            if !memory.anchors.isEmpty {
                Label(memory.anchors.map(\.phrase).joined(separator: " · "), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ochre)
            }
            if !memory.peopleRefs.isEmpty || memory.placeText != nil {
                FlowChips(items: memory.peopleRefs + (memory.placeText.map { [$0] } ?? []))
            }
            HStack(spacing: 12) {
                Button("Keep", action: onKeep)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("card.add")
                Button("Change…", action: onChange)
                    .buttonStyle(.bordered)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("card.change")
                Spacer(minLength: 0)
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("card.dismiss")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
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

/// "Check this: around 1998?" A word and a symbol in ochre, never colour alone.
struct CheckThisTag: View {
    let tag: CheckThis

    var body: some View {
        Label(tag.label, systemImage: "questionmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ochre)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tag.label)
            .accessibilityIdentifier("card.checkThis")
    }
}

/// People and place chips, wrapping.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
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

/// "Suggestion dismissed. Your recording is untouched." with Undo, for the undo window.
struct DismissedNotice: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Suggestion dismissed. Your recording is untouched.")
                .font(.footnote)
                .foregroundStyle(Theme.stone)
                .accessibilityIdentifier("card.dismissedNotice")
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .buttonStyle(.bordered)
                .tint(Theme.olive)
                .accessibilityIdentifier("card.undo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.sand))
        .transition(.opacity)
    }
}
