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

    /// While a start error stands, the bar shows it in place of the label. A refused microphone offers
    /// "Open Settings"; any other error is tried again by a tap.
    @ViewBuilder private var startButton: some View {
        if let error = home.startError {
            let denied = error == .microphoneDenied
            Button { Task { await home.startErrorTapped() } } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.message).lineLimit(2).minimumScaleFactor(0.8)
                        if denied { Text("Open Settings").fontWeight(.semibold).foregroundStyle(Theme.oliveText) }
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(denied ? "timeline.error.settings" : "timeline.error")
            .accessibilityHint(denied ? "Opens Settings" : "Tries again")
        } else {
            startButton(label: SessionSubject.barLabel(home.context), icon: "mic.fill", iconStyle: Theme.olive, textStyle: .primary, font: .headline, lines: 1)
                .accessibilityIdentifier("home.start")
        }
    }

    private func startButton(label: String, icon: String, iconStyle: Color, textStyle: Color, font: Font, lines: Int) -> some View {
        Button { Task { await home.startSession(kind: .quick) } } label: {
            Label {
                Text(label).lineLimit(lines).minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: icon).foregroundStyle(iconStyle)
            }
            .font(font)
            .foregroundStyle(textStyle)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
