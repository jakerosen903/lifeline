import LifelineKit
import SwiftUI

/// Part 2 of the photo card, "Also show this photo on": the pages as chips, in groups by kind. A tap on a chip that is not
/// chosen adds the photo to that page; a tap on a chosen chip takes it off. A chip keeps its frame in both states (plan
/// decision 10): the tick's space is there when it is not chosen, and the type does not change weight.
struct PhotoCardPages: View {
    let groups: [PhotoStoryCard.PageGroup]
    let onToggle: (PhotoStoryCard.Page) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Also show this photo on").font(.system(.title3, design: .serif).weight(.medium)).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Tap to add. Tap again to take it off.").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: Self.symbol(group.type)).foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
                        Text(group.title).foregroundStyle(Theme.secondaryText).accessibilityIdentifier("photoCard.group")
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    FlowLayout(spacing: 8) {
                        ForEach(group.pages) { page in chip(page) }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
    }

    /// Filled with a tick when chosen, an outline when not. Two lines at most, then an ellipsis.
    private func chip(_ page: PhotoStoryCard.Page) -> some View {
        Button { onToggle(page) } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.footnote.weight(.bold)).opacity(page.isChosen ? 1 : 0)
                Text(page.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
            }
            .foregroundStyle(page.isChosen ? Theme.card : Theme.oliveText)
            .padding(.leading, 12).padding(.trailing, 14)
            .frame(minHeight: 44)
            .background {
                Capsule().fill(page.isChosen ? Theme.olive : Color.clear)
                Capsule().strokeBorder(Theme.olive, lineWidth: 1.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.title)
        .accessibilityValue(page.stateValue)
        .accessibilityIdentifier("photoCard.page")
    }

    /// A small symbol for each kind of page. Decorative: the group's name says the same.
    private static func symbol(_ type: EntityType) -> String {
        switch type {
        case .person: "person"
        case .place: "mappin.and.ellipse"
        case .thing: "shippingbox"
        case .idea: "lightbulb"
        }
    }
}
