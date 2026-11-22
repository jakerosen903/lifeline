import LifelineKit
import SwiftUI

/// The person's words around a match, as said (P1): one `Text`, so it wraps as one line of reading.
/// A matched word is marked by weight, never by colour alone: semibold in ink, the rest in the secondary colour.
/// The words may hold a line break; nothing limits the lines, so it wraps and is never cut.
struct SnippetText: View {
    let snippet: SearchSnippet

    var body: some View {
        snippet.parts
            .reduce(Text(verbatim: "")) { line, part in Text("\(line)\(styled(part))") }
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func styled(_ part: SearchSnippet.Part) -> Text {
        part.isMatch
            ? Text(verbatim: part.text).fontWeight(.semibold).foregroundStyle(Theme.ink)
            : Text(verbatim: part.text).foregroundStyle(Theme.secondaryText)
    }
}
