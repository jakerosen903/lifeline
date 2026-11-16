import LifelineKit
import SwiftUI

/// The top of You (S3): the person's name, the birth line they typed, and their life strip, which is the
/// way to their own page. Each shows only when there is something to show; nothing asks to be filled in.
struct PortraitHeader: View {
    let portrait: Portrait
    let deps: Dependencies
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = portrait.name {
                Text(name).titleStyle()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("you.name")
            }
            if let birth = portrait.birthLine {
                Text(birth).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("you.birth")
            }
            if let owner = portrait.owner, let strip = portrait.strip, let sentence = strip.sentence {
                NavigationLink {
                    EntityScreen(viewModel: EntityViewModel(entity: owner, deps: deps), onChange: onChange)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        LifeStripView(strip: strip)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    // The strip's sentence is its one label: the axis says the same in marks.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(sentence)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityHint("Opens your page")
                .accessibilityIdentifier("entities.aboutYou")
            }
        }
    }
}
