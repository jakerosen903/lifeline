import LifelineKit
import SwiftUI

/// A person, place, thing or idea found by search: it opens the page in the search tab's own stack (decision 15).
/// A person shows a face, the name and one line (the matched alias, else the own words); the others show the
/// title only (decision 13). One button for VoiceOver: label the title, value the second line (decision 26).
struct SearchEntityRow: View {
    let hit: SearchResults.EntityHit
    let cover: Photo?
    let deps: Dependencies
    let onChange: () -> Void
    /// The minimum tap size: the face only has to stay a face, and the text needs the width.
    private let faceSize: CGFloat = 44

    var body: some View {
        let entity = hit.summary.entity
        NavigationLink {
            EntityScreen(viewModel: EntityViewModel(entity: entity, deps: deps), onChange: onChange)
        } label: {
            HStack(spacing: 14) {
                if entity.type == .person {
                    TileFace(summary: hit.summary, cover: cover, cache: deps.photoImages, letterFont: .system(size: 20, design: .serif))
                        .frame(width: faceSize)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.title)
                        .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                    if let second = hit.secondLine {
                        Text(second).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entity.title)
            .accessibilityValue(hit.secondLine ?? "")
        }
        .accessibilityIdentifier("search.result")
    }
}
