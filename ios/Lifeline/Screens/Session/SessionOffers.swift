import SwiftUI

/// Settling in, at the planned length: a gentle question, never a stop.
struct WrapUpBanner: View {
    let onFinish: () -> Void
    let onKeepGoing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shall we leave it there for today?")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 12) {
                Button("Finish", action: onFinish)
                    .buttonStyle(.bordered)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("session.wrapUpFinish")
                Button("Keep going", action: onKeepGoing)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("session.keepGoing")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.wrapUp")
    }
}

/// Settling in, after a quiet moment: the next question, offered and never spoken.
struct NextPromptOffer: View {
    let text: String
    let onTake: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If you like:").font(.caption).foregroundStyle(Theme.stone)
            Text(text)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("session.nextPromptText")
            HStack(spacing: 12) {
                Button("Take it", action: onTake)
                    .buttonStyle(.bordered)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("session.nextPromptTake")
                Button("Another time", action: onLater)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("session.nextPromptLater")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.nextPrompt")
    }
}
