import LifelineKit
import SwiftUI

/// A thing on the shelf. With a key photo: the photo fills the top, then the title and the moment count.
/// Without one: the sand face, the title, the person's own words in quotes, then the count. When a guess
/// placed the thing, the tile says so in words (P5). It shows no date and never asks for a photo.
/// One button for VoiceOver: the title is its label; the count, the guess and the quote are its value.
struct ThingTile: View {
    let tile: ThingShelf.Tile
    let keyPhoto: Photo?
    let quote: String?
    let deps: Dependencies
    let onChange: () -> Void
    /// One height for every tile at a size, so a row is even. At the accessibility sizes a tile fits its text instead.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 176
    @Environment(\.dynamicTypeSize) private var textSize

    private var fitsText: Bool { textSize.isAccessibilitySize }
    private var title: String { tile.summary.entity.title }

    var body: some View {
        NavigationLink {
            EntityScreen(viewModel: EntityViewModel(entity: tile.summary.entity, deps: deps), onChange: onChange)
        } label: {
            face
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: fitsText ? nil : height, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                // As `PersonLink`: one element, the title its label, the count, guess and quote its value.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(ThingTileText.accessibilityValue(moments: tile.summary.momentCount,
                                                                     placedByGuess: tile.placedByGuess, quote: quote))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("entities.row")
    }

    @ViewBuilder private var face: some View {
        if let keyPhoto {
            VStack(alignment: .leading, spacing: 0) {
                // A photo that cannot load leaves the sand fill; the tile keeps its size.
                PhotoImageView(photo: keyPhoto, size: .small, cache: deps.photoImages) { Theme.sand }
                    .frame(maxWidth: .infinity, minHeight: fitsText ? 120 : 0)
                    // Hidden alone, the image stayed in the automation tree; an empty representation removes it there too.
                    .accessibilityRepresentation { Color.clear }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                        .lineLimit(fitsText ? nil : 3)
                    footer
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .serif)).foregroundStyle(Theme.ink)
                    .lineLimit(fitsText ? nil : 3)
                    .layoutPriority(1)
                if let quote {
                    Text("“\(quote)”")
                        .font(.system(.subheadline, design: .serif).italic()).foregroundStyle(Theme.ink)
                        .lineLimit(fitsText ? nil : 4)
                }
                Spacer(minLength: 0)
                footer.fixedSize(horizontal: false, vertical: true).layoutPriority(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: fitsText ? nil : .infinity, alignment: .topLeading)
            .background(Theme.sand)
        }
    }

    /// The count, then the guess line. Each shows only when it has something to say.
    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let count = ThingTileText.countLine(tile.summary.momentCount) {
                Text(count).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if tile.placedByGuess {
                Text(ThingTileText.guessLine).font(.footnote).foregroundStyle(Theme.ochreText)
            }
        }
    }
}
