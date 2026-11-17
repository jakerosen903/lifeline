import SwiftUI

extension View {
    /// The one slot pinned above the record bar (decision 21): wherever the page is scrolled, why the last photo
    /// action failed is on screen. The message is announced to VoiceOver when it appears.
    func photoErrorSlot(_ message: String?) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if let message {
                ErrorLine(text: message).font(.footnote).accessibilityIdentifier("photo.error")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.sand))
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: message)
        .onChange(of: message) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }
}
