import LifelineKit
import SwiftUI

/// One quiet line about what is still being sorted (M6): the landing's glyph and the status's
/// words. The key line opens Settings; "Not sorting right now" offers Try again.
struct SortingLine: View {
    let status: TimelineViewModel.SortingPresentation
    let onOpenSettings: () -> Void
    let onTryAgain: () -> Void

    var body: some View {
        if let line = status.line {
            HStack(spacing: 10) {
                if status.needsKey {
                    Button(action: onOpenSettings) {
                        Label(line, systemImage: "key")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(line)
                    .accessibilityIdentifier("timeline.sorting")
                } else {
                    Label(line, systemImage: status.canRetry ? "pause.circle" : "arrow.triangle.2.circlepath")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(line)
                        .accessibilityIdentifier("timeline.sorting")
                }
                Spacer(minLength: 0)
                if status.canRetry {
                    Button("Try again", action: onTryAgain)
                        .buttonStyle(.bordered)
                        .tint(Theme.olive)
                        .accessibilityIdentifier("timeline.sortingRetry")
                }
            }
            .font(.footnote)
            .foregroundStyle(status.needsKey || status.canRetry ? Theme.ochre : Theme.stone)
        }
    }
}
