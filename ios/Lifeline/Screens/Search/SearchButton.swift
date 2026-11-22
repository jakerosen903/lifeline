import SwiftUI

extension View {
    /// A tab's root: a "Search" button in its top bar that pushes search in this tab's own stack (ruling R4).
    /// Each tab keeps its own search, so each keeps its own query while it stays pushed.
    func searchButton(deps: Dependencies) -> some View {
        modifier(SearchButtonModifier(deps: deps))
    }
}

private struct SearchButtonModifier: ViewModifier {
    let deps: Dependencies
    @State private var isSearching = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isSearching = true } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ToolbarGlyphStyle())
                    .accessibilityIdentifier("shell.search")
                }
            }
            .navigationDestination(isPresented: $isSearching) { SearchScreen(deps: deps) { isSearching = false } }
    }
}

/// Draws the label in the app's olive at its own 44-point frame, and dims it while pressed.
private struct ToolbarGlyphStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Theme.oliveText).opacity(configuration.isPressed ? 0.4 : 1)
    }
}
