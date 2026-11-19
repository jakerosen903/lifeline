import LifelineKit
import SwiftUI

/// A person's face as a circle: their key photo when they have one, otherwise the monogram in their tint,
/// as `TileFace` draws it for the grid. Decoration only; the name beside it carries the meaning.
struct PersonFace: View {
    let id: EntityID
    let name: String
    let cover: Photo?
    let cache: PhotoImageCache?
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Theme.monogramTints[Monogram.tintIndex(for: id)])
            .frame(width: size, height: size)
            .overlay {
                if let cover, let cache {
                    PhotoImageView(photo: cover, size: .small, cache: cache) { monogram }
                } else {
                    monogram
                }
            }
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var monogram: some View {
        Text(Monogram.letter(for: name))
            .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
            .foregroundStyle(Theme.ink)
    }
}
