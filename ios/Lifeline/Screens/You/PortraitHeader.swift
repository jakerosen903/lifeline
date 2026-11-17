import LifelineKit
import SwiftUI

/// The top of You (S3): the owner's cover (S4), the person's name, the birth line they typed, and their life
/// strip, which is the way to their own page; then their photos in a row when there are two or more. Each shows
/// only when there is something to show; nothing asks to be filled in.
struct PortraitHeader: View {
    let portrait: Portrait
    let cover: Photo?
    let photos: [PlacedPhoto]
    /// True while a photo is being added: "Adding the photo…" shows where the photo will go.
    let isAdding: Bool
    /// "Photo of you" (decision 19).
    let label: String
    let cache: PhotoImageCache
    let deps: Dependencies
    let onOpen: (PlacedPhoto) -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // No photo, no frame: You looks complete without one.
            if isAdding { PhotoAddingLine() }
            if let cover {
                PhotoHeader(cover: cover, label: label, cache: cache) {
                    if let placed = photos.first(where: \.isCover) { onOpen(placed) }
                }
                .padding(.bottom, 10)
            }
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
            // Decision 13: one photo is already the cover; two or more sit in a row.
            if photos.count >= 2 {
                PhotoRow(photos: photos, label: label, cache: cache, onOpen: onOpen)
                    .padding(.top, 16)
            }
        }
    }
}
