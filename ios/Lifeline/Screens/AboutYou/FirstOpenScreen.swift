import LifelineKit
import SwiftUI

/// R1 FirstOpen: two ways in, and context only if they want to give it.
struct FirstOpenScreen: View {
    let deps: Dependencies
    let onStart: (SessionKind) -> Void
    let onProfileSaved: () -> Void
    @State private var context = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Tell me one story.").titleStyle()
            Text("I'll keep it safe, in your voice, and sort it into your timeline as you go.")
                .font(.system(.body, design: .serif)).foregroundStyle(Theme.stone)
            Button { begin(.quick) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tell a quick story").font(.headline)
                    Text("One question. A few minutes. Finish whenever you're done.").font(.footnote).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.olive)).foregroundStyle(.white)
            }
            .accessibilityIdentifier("firstOpen.quick")
            Button { begin(.settleIn) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settle in").font(.headline)
                    Text("More of a conversation. I'll offer the next question when you go quiet.").font(.footnote).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sand)).foregroundStyle(Theme.ink)
            }
            .accessibilityIdentifier("firstOpen.settleIn")
            Button("Add a little context") { context = true }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.stone)
                .accessibilityIdentifier("firstOpen.context")
            Spacer()
        }
        .padding(24)
        .linenBackground()
        .sheet(isPresented: $context) {
            AboutYouScreen(viewModel: AboutYouViewModel(profile: deps.profile, mode: .firstOpen) { context = false; onProfileSaved() })
        }
    }

    /// Starting counts as first open done: an empty profile is saved so this screen does not return.
    private func begin(_ kind: SessionKind) {
        AboutYouViewModel(profile: deps.profile, mode: .firstOpen) {}.skip()
        onStart(kind)
    }
}
