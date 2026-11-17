import SwiftUI

/// The shell's one notice: a sentence about something the app did on its own (the launch repair). It shows
/// once above the record bar on whichever tab is on screen, and goes after `duration` or on a tap. It has no
/// Undo. It is not stored: what caused it happens once, so a relaunch has nothing to say.
@MainActor
@Observable
final class ShellNotice {
    static let duration: Duration = .seconds(6)

    private(set) var text: String?
    /// The sentence waiting for the shell to be on screen. Its time must not run out under first open or a cover.
    @ObservationIgnored private var waiting: String?
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Says the sentence to VoiceOver when it shows.
    @ObservationIgnored var announce: (String) -> Void = { AccessibilityNotification.Announcement($0).post() }

    /// `text` nil or empty: there is nothing to say, and `present()` does nothing.
    init(_ text: String?) {
        waiting = (text?.isEmpty ?? true) ? nil : text
    }

    /// The shell is on screen with nothing over it: show what waits, say it, and start its time. Once only.
    func present() {
        guard let sentence = waiting else { return }
        waiting = nil
        text = sentence
        announce(sentence)
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.text = nil
        }
    }

    /// A tap on the notice.
    func dismiss() {
        timer?.cancel()
        text = nil
    }
}

/// The shell's notice in the shared slot. The whole slot is the control: a tap sends it away.
struct ShellNoticeBar: View {
    let notice: ShellNotice

    var body: some View {
        if let text = notice.text {
            Button(action: notice.dismiss) { NoticeSlot(text: text) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shell.notice")
                .accessibilityHint("Dismisses this message")
                .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}
