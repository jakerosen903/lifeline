import SwiftUI

extension View {
    /// The mark of a guess: a dashed ochre outline. It always comes with the word "Assumed" beside it.
    func assumedOutline(cornerRadius: CGFloat = 16) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.ochre, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }
    }
}
