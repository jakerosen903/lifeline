import LifelineKit
import SwiftUI

/// The four parts of You, each drawn its own way (S3), and the chips over "Who you are".
/// Quotation marks go only around the person's own words; a title standing in is plain.

extension PortraitLine {
    /// The text as drawn: in curly quotation marks only when it is the person's own words.
    var drawnText: String { isOwnWords ? "“\(text)”" : text }

    var memory: Memory? {
        if case .memory(let memory) = source { memory } else { nil }
    }

    var idea: Entity? {
        if case .idea(let entity) = source { entity } else { nil }
    }
}

/// A part's heading, then its lines. The caller shows a part only when it has lines.
struct PortraitPart<Content: View>: View {
    let heading: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).sectionHeadingStyle()
            content
        }
    }
}

/// A fact or a goal: the line, and under it its tags (a fact) or when it was said (a goal). Opens its memory.
struct PortraitSaidRow: View {
    let line: PortraitLine
    /// Tags for a fact, "said in October" for a goal; nil shows nothing.
    let note: String?
    let deps: Dependencies
    let onChange: () -> Void

    var body: some View {
        if let memory = line.memory {
            NavigationLink {
                MemoryScreen(viewModel: MemoryViewModel(memory: memory, deps: deps), deps: deps, onChange: onChange)
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.drawnText).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note {
                            Text(note).font(.footnote).foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line.text)
                .accessibilityValue(note ?? "")
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .accessibilityIdentifier("you.line")
        }
    }
}

/// A feeling: a sand card with the words in italic serif, and what it is about when the words named it.
struct PortraitFeelingCard: View {
    let line: PortraitLine
    let deps: Dependencies
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.drawnText).font(.system(.body, design: .serif).italic()).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(line.text)
                .accessibilityIdentifier("you.line")
            if let about = line.about {
                NavigationLink {
                    EntityScreen(viewModel: EntityViewModel(entity: about, deps: deps), onChange: onChange)
                } label: {
                    Text("about \(about.title)").font(.footnote).foregroundStyle(Theme.oliveText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("you.feelingAbout")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sand))
    }
}

/// An idea: its title large and plain beside an ochre rule. Opens its page, which keeps "Over time".
struct PortraitIdeaRow: View {
    let line: PortraitLine
    let deps: Dependencies
    let onChange: () -> Void

    var body: some View {
        if let idea = line.idea {
            NavigationLink {
                EntityScreen(viewModel: EntityViewModel(entity: idea, deps: deps), onChange: onChange)
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Rectangle().fill(Theme.ochre).frame(width: 3)
                    Text(line.text).font(.system(.title2, design: .serif)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line.text)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("entities.row")
        }
    }
}

/// "All", then the person's own tags. They wrap at the row's width. The chosen one is filled and
/// carries a checkmark and the selected trait, so the choice is not told by colour alone.
struct PortraitChips: View {
    let tags: [String]
    @Binding var chosen: String?

    var body: some View {
        FlowLayout(spacing: 8) {
            PortraitChip(title: "All", isSelected: chosen == nil) { chosen = nil }
                .accessibilityIdentifier("you.tag.all")
            ForEach(tags, id: \.self) { tag in
                PortraitChip(title: tag, isSelected: chosen?.lowercased() == tag.lowercased()) { chosen = tag }
                    .accessibilityIdentifier("you.tag")
            }
        }
    }
}

private struct PortraitChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent).tint(Theme.olive)
                .buttonBorderShape(.capsule)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered).tint(Theme.oliveOnFill)
                .buttonBorderShape(.capsule)
        }
    }

    private var label: some View {
        Label {
            Text(title)
        } icon: {
            if isSelected { Image(systemName: "checkmark") }
        }
        .labelStyle(.titleAndIcon)
        .font(.subheadline)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
