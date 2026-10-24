import SwiftUI

/// "Part of: Growing up with Ryan" on a memory card, with the one-tap way out. Keep includes
/// the membership the person could see; "Not part of it" removes it before Keep (M5).
struct StoryLine: View {
    let text: String
    let onNotPartOfIt: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.stone)
                .accessibilityIdentifier("card.storyLine")
            Spacer(minLength: 0)
            Button("Not part of it", action: onNotPartOfIt)
                .font(.subheadline)
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.olive)
                .accessibilityIdentifier("card.notPartOfIt")
        }
    }
}
