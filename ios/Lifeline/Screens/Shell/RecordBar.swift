import LifelineKit
import SwiftUI

/// The tab view's bottom accessory: one button across the bar starts a quick story about the page
/// on screen, and a trailing menu holds "Settle in". The system draws the bar's glass.
struct RecordBar: View {
    let home: HomeViewModel

    var body: some View {
        HStack(spacing: 0) {
            startButton
            moreMenu
        }
    }

    /// While a start error stands, the bar shows it in place of the label; tapping tries again.
    private var startButton: some View {
        let error = home.startError
        return
        Button { Task { await home.startSession(kind: .quick) } } label: {
            Label {
                Text(error ?? SessionSubject.barLabel(home.context))
                    .lineLimit(error == nil ? 1 : 2)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: error == nil ? "mic.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(error == nil ? Theme.olive : .red)
            }
            .font(error == nil ? .headline : .footnote)
            .foregroundStyle(error == nil ? Color.primary : .red)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(error == nil ? "home.start" : "timeline.error")
        .accessibilityHint(error == nil ? "" : "Tries again")
    }

    private var moreMenu: some View {
        Menu {
            Button("Settle in", systemImage: "leaf") { Task { await home.startSession(kind: .settleIn) } }
                .accessibilityIdentifier("home.settleIn")
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .accessibilityLabel("More ways to start")
        .accessibilityIdentifier("home.more")
    }
}
