import LifelineKit
import SwiftUI

/// Part 2 of the photo card, "Also show this photo on": the pages as chips, in groups by kind. A tap on a chip that is not
/// chosen adds the photo to that page; a tap on a chosen chip takes it off. A chip keeps its frame in both states (plan
/// decision 10): the tick's space is there when it is not chosen, and the type does not change weight. A chip the story
/// chose looks the same as one the person tapped; the line and VoiceOver carry the difference. The words come from the kit.
/// The part has two layouts, by the owner's request (spec part 3): open, with every chip and "Done"; done, with only the
/// chosen chips (or the sentence) and "Edit". What each shows comes from the card.
struct PhotoCardPages: View {
    let card: PhotoStoryCard
    /// Pages emptied while the part is done (`PhotoCardViewModel.keptPages`).
    let kept: [PhotoStoryCard.Page]
    let onToggle: (PhotoStoryCard.Page) -> Void
    let onDone: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Also show this photo on").font(.system(.title3, design: .serif).weight(.medium)).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let line = card.shownPagesLine {
                    // Every line the kit can show is laid out, unseen, under the shown one: the space is the tallest line's,
                    // so the chips do not move under the finger when the line changes.
                    ZStack(alignment: .topLeading) {
                        ForEach(PhotoStoryCard.allPagesLines, id: \.self) { Text($0).hidden().accessibilityHidden(true) }
                        Text(line).accessibilityIdentifier("photoCard.pagesLine")
                    }
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if card.showsNoOtherPageSentence(keeping: kept) {
                Text(PhotoStoryCard.noOtherPageSentence).font(.subheadline).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photoCard.noOtherPage")
            }
            ForEach(card.shownPageGroups(keeping: kept)) { group in
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
            if card.pagesDone {
                partButton(PhotoStoryCard.editTitle, id: "photoCard.pagesEdit", action: onEdit)
            } else {
                partButton(PhotoStoryCard.doneTitle, id: "photoCard.pagesDone", action: onDone)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
    }

    /// "Done" or "Edit", at the start of the row under the chips, as the date part's links are.
    private func partButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.oliveText)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
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
