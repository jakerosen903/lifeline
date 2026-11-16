import LifelineKit
import SwiftUI

extension View {
    /// While this screen is on screen, the record bar names `subject` and a session started from it
    /// is about it. Nil: the bar says "Tell a story".
    func sessionContext(_ subject: SessionSubject?) -> some View {
        modifier(SessionContextModifier(subject: subject))
    }
}

private struct SessionContextModifier: ViewModifier {
    let subject: SessionSubject?
    /// Absent outside the shell (a preview, a sheet with its own environment): the modifier does nothing.
    @Environment(HomeViewModel.self) private var home: HomeViewModel?
    /// This screen, so it clears only the context it set.
    @State private var screen = UUID()
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear { isVisible = true; home?.show(subject, from: screen) }
            .onDisappear { isVisible = false; home?.leave(screen) }
            // A rename on the page renames the bar.
            .onChange(of: subject) { if isVisible { home?.show(subject, from: screen) } }
    }
}
