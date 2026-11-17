import LifelineKit
import SwiftUI

/// The square at the top of a tile. A cover fills it, clipped to the same frame; the monogram is what shows
/// without one, and under a cover that is still loading or cannot load. A photo changes nothing about the layout.
struct TileFace: View {
    let summary: EntitySummary
    let cover: Photo?
    let cache: PhotoImageCache
    var letterFont: Font = .system(.largeTitle, design: .serif)

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Theme.monogramTints[Monogram.tintIndex(for: summary.id)])
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let cover {
                    PhotoImageView(photo: cover, size: .small, cache: cache) { monogram }
                } else {
                    monogram
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityHidden(true)
    }

    private var monogram: some View {
        Text(Monogram.letter(for: summary.entity.title))
            .font(letterFont)
            .foregroundStyle(Theme.ink)
    }
}

/// A person in the grid: a face, the name, and the person's own words for them ("my sister").
/// One button for VoiceOver: the name is its label, the own words its value. It shows no count
/// and no date, and never asks for a photo.
struct PersonTile: View {
    let summary: EntitySummary
    let cover: Photo?
    let deps: Dependencies
    let onChange: () -> Void

    var body: some View {
        PersonLink(summary: summary, deps: deps, onChange: onChange) {
            VStack(alignment: .leading, spacing: 6) {
                TileFace(summary: summary, cover: cover, cache: deps.photoImages)
                Text(summary.entity.title)
                    .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                // An empty line keeps the rows even when a person has no words of their own.
                Text(summary.ownWords ?? " ")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                    .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// The same person as a list row, for accessibility text sizes: a small face, then the words.
struct PersonRow: View {
    let summary: EntitySummary
    let cover: Photo?
    let deps: Dependencies
    let onChange: () -> Void
    /// Fixed: at accessibility sizes the text needs the width, and the face only has to stay a face.
    private let faceSize: CGFloat = 52

    var body: some View {
        PersonLink(summary: summary, deps: deps, onChange: onChange) {
            HStack(spacing: 14) {
                TileFace(summary: summary, cover: cover, cache: deps.photoImages, letterFont: .system(size: 24, design: .serif)).frame(width: faceSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.entity.title)
                        .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                    if let words = summary.ownWords {
                        Text(words).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
    }
}

/// The link to a person's page, read as one button: label the name, value the own words.
private struct PersonLink<Label: View>: View {
    let summary: EntitySummary
    let deps: Dependencies
    let onChange: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        NavigationLink {
            EntityScreen(viewModel: EntityViewModel(entity: summary.entity, deps: deps), onChange: onChange)
        } label: {
            label
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary.entity.title)
                .accessibilityValue(summary.ownWords ?? "")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("entities.row")
    }
}
