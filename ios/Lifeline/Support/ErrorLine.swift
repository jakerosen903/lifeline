import SwiftUI

/// An error that says what failed: ink text, with the red only in the symbol, as on the record bar.
struct ErrorLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .accessibilityElement(children: .combine)
    }
}
