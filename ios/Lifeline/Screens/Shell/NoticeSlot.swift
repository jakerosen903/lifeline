import SwiftUI

/// One message pinned above the record bar, so it shows wherever the person is on the page and the page
/// does not jump. A plain message is not an error: ink text, no red. An error says what failed.
/// `trailing` holds what the person can do about it (You's Undo); the shell's own notice has nothing there.
struct NoticeSlot<Trailing: View>: View {
    let text: String
    let isError: Bool
    /// The message's accessibility identifier. A page that had its own identifiers before the slot was shared keeps them.
    let identifier: String
    let trailing: Trailing

    init(text: String, isError: Bool = false, identifier: String = "shell.notice", @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.isError = isError
        self.identifier = identifier
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if isError {
                ErrorLine(text: text).font(.footnote).accessibilityIdentifier(identifier)
            } else {
                Text(text).font(.footnote).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.sand))
        .transition(.opacity)
    }
}

extension NoticeSlot where Trailing == EmptyView {
    init(text: String, isError: Bool = false, identifier: String = "shell.notice") {
        self.init(text: text, isError: isError, identifier: identifier) { EmptyView() }
    }
}
