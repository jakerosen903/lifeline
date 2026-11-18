import LifelineKit
import SwiftUI

/// A person on a story: the face, the name, and one line under it. A guess is marked by a dashed ochre
/// outline and the word "Assumed" in the line; the mark never relies on colour alone. One button that
/// opens the "Who is this?" sheet.
struct PersonChip: View {
    let name: String
    /// nil when the link has no line (said, confirmed, older).
    let line: String?
    let isAssumed: Bool
    let accessibilityLabel: String
    var personID: PersonID? = nil
    var cover: Photo? = nil
    var cache: PhotoImageCache? = nil
    let onTap: () -> Void

    private var outline: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                PersonFace(id: personID.map { EntityID(rawValue: $0.rawValue) } ?? EntityID(rawValue: name),
                           name: name, cover: cover, cache: cache, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let line {
                        Text(line)
                            .font(.footnote).foregroundStyle(isAssumed ? Theme.ochreText : Theme.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(outline.fill(Theme.card))
            .overlay {
                if isAssumed {
                    outline.strokeBorder(Theme.ochre, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                } else {
                    outline.strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
            .contentShape(outline)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(isAssumed ? "person.chip.assumed" : "person.chip")
    }
}
