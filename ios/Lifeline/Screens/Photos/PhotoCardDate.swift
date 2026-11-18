import LifelineKit
import SwiftUI

/// Part 3 of the photo card, "When did this happen?": one offer for the story, then the same block in its used state with
/// "Undo". The words come from `PhotoDatePart`. The layout does not move after a tap: the button and the used text share
/// one full-width face, "Undo" takes the place of "Choose moments", and the sentence and the face never get shorter while
/// the block is on screen.
struct PhotoCardDate: View {
    let part: PhotoDatePart
    let onUse: ([Memory]) -> Void
    let onChoose: () -> Void
    let onUndo: () -> Void

    /// The tallest each has been. "…now use that date." can need one line less than "…have no date you said.".
    @State private var textHeight: CGFloat = 0
    @State private var faceHeight: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When did this happen?").font(.system(.title3, design: .serif).weight(.medium)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            switch part {
            case .hidden:
                EmptyView()
            case .offer(let offer):
                sentence(offer.text)
                Button { onUse(offer.memories) } label: { face(offer.button, ticked: false) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("photoCard.useDate")
                links(choose: true, undo: offer.canUndo)
            case .used(let text, let button):
                sentence(text)
                face(button, ticked: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(button)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("photoCard.dateUsed")
                links(choose: false, undo: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoCard.date")
        // A new text size measures again from nothing.
        .onChange(of: typeSize) { textHeight = 0; faceHeight = 0 }
    }

    private func sentence(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .keepsTallest($textHeight, alignment: .topLeading)
            .accessibilityIdentifier("photoCard.dateText")
    }

    /// The button's face, and the used text in the same frame: filled, with a tick once used.
    private func face(_ title: String, ticked: Bool) -> some View {
        HStack(spacing: 6) {
            if ticked { Image(systemName: "checkmark").font(.footnote.weight(.bold)) }
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.card)
        .padding(.horizontal, 18).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .keepsTallest($faceHeight, alignment: .center)
        .background(Capsule().fill(Theme.olive))
        .contentShape(Capsule())
    }

    /// "Choose moments", then "Undo", at the start of the row under the face. After a later memory is kept, both show.
    private func links(choose: Bool, undo: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { linkButtons(choose: choose, undo: undo) }
            VStack(alignment: .leading, spacing: 0) { linkButtons(choose: choose, undo: undo) }
        }
    }

    @ViewBuilder private func linkButtons(choose: Bool, undo: Bool) -> some View {
        if choose { link("Choose moments", id: "photoCard.chooseMoments", action: onChoose) }
        if undo { link("Undo", id: "photoCard.undoDate", action: onUndo) }
    }

    private func link(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.oliveText)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
    }
}

private extension View {
    /// Never shorter than the tallest height this view has had: a state with fewer lines keeps the earlier height.
    func keepsTallest(_ tallest: Binding<CGFloat>, alignment: Alignment) -> some View {
        frame(minHeight: tallest.wrappedValue > 0 ? tallest.wrappedValue : nil, alignment: alignment)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > tallest.wrappedValue { tallest.wrappedValue = height }
            }
    }
}
