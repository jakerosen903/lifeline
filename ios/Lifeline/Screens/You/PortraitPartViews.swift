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

extension View {
    /// "Hide" and "Delete…" on a line that is a memory. A long press shows them; VoiceOver reads them as actions
    /// on the element. Never on the play control, so its tap stays its own.
    func lineMenu(_ line: PortraitLine, _ viewModel: YouViewModel) -> some View {
        contextMenu {
            if line.memory != nil {
                Button("Hide", systemImage: "eye.slash") { viewModel.hide(line) }
                    .accessibilityIdentifier("you.hide")
                Button("Delete…", systemImage: "trash", role: .destructive) { viewModel.deleteTarget = line }
                    .accessibilityIdentifier("you.delete")
            }
        }
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
    let viewModel: YouViewModel
    let onChange: () -> Void

    var body: some View {
        let deps = viewModel.deps
        if let memory = line.memory {
            HStack(alignment: .center, spacing: 0) {
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
            .lineMenu(line, viewModel)
            .accessibilityIdentifier("you.line")
            // Beside the link, never inside it: nested controls swallow taps and merge for VoiceOver.
            PlayLineButton(line: line, viewModel: viewModel)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }
}

/// A feeling: a sand card with the words in italic serif, which open its memory, and what it is about
/// when the words named it, which opens that page.
struct PortraitFeelingCard: View {
    let line: PortraitLine
    let viewModel: YouViewModel
    let onChange: () -> Void

    var body: some View {
        let deps = viewModel.deps
        VStack(alignment: .leading, spacing: 0) {
            if let memory = line.memory {
                HStack(alignment: .center, spacing: 0) {
                NavigationLink {
                    MemoryScreen(viewModel: MemoryViewModel(memory: memory, deps: deps), deps: deps, onChange: onChange)
                } label: {
                    Text(line.drawnText).font(.system(.body, design: .serif).italic()).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityLabel(line.text)
                }
                .buttonStyle(.plain)
                .lineMenu(line, viewModel)
                .accessibilityIdentifier("you.line")
                PlayLineButton(line: line, viewModel: viewModel)
                }
            }
            if let about = line.about {
                NavigationLink {
                    EntityScreen(viewModel: EntityViewModel(entity: about, deps: deps), onChange: onChange)
                } label: {
                    // Centred in its 44-point hit area, whose slack is the card's bottom margin: no blank band.
                    Text("about \(about.title)").font(.footnote).foregroundStyle(Theme.oliveText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("you.feelingAbout")
            }
        }
        // The links' 44-point frames carry most of the vertical margin, so the card hugs its words.
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, line.about == nil ? 4 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sand))
    }
}

/// An idea: its title large and plain beside an ochre rule. Opens its page, which keeps "Over time".
struct PortraitIdeaRow: View {
    let line: PortraitLine
    let viewModel: YouViewModel
    let onChange: () -> Void

    var body: some View {
        let deps = viewModel.deps
        if let idea = line.idea {
            HStack(alignment: .center, spacing: 0) {
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
            // Its first telling, when it has one; beside the link, never inside it.
            PlayLineButton(line: line, viewModel: viewModel)
            }
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

/// One button whose look follows the selection, so VoiceOver keeps its focus on a tap. A capsule about
/// 44 points high, drawn in the label with its hit area. Chosen: olive fill, white text and a checkmark.
/// Not chosen: `oliveOnFill` text on a 12% fill of itself, which reaches 4.5:1 over linen (as `TagPill`).
private struct PortraitChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").fontWeight(.semibold) }
                Text(title).multilineTextAlignment(.leading)
            }
            .font(.subheadline)
            .foregroundStyle(isSelected ? Color.white : Theme.oliveOnFill)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
            .background(Capsule().fill(isSelected ? Theme.olive : Theme.oliveOnFill.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A line's own play control: its telling only, one line at a time. Shown only for a line with a recording.
/// Beside the row's link, never inside it. The 44-point frame and hit area are in the label.
struct PlayLineButton: View {
    let line: PortraitLine
    let viewModel: YouViewModel

    var body: some View {
        if line.telling != nil {
            let playing = viewModel.isPlaying(line)
            Button { viewModel.togglePlayback(line) } label: {
                Image(systemName: playing ? "stop.circle" : "play.circle").font(.title2)
                    .foregroundStyle(Theme.oliveText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(playing ? "Stop" : "Hear yourself say it")
            // The controls are identical to the ear: the value says which line each one plays.
            .accessibilityValue(line.text)
            .accessibilityIdentifier("you.play")
        }
    }
}

/// The lead's control: "Hear yourself say it, 0:04", or "Stop" while it plays.
struct PortraitLeadPlayButton: View {
    let line: PortraitLine
    let viewModel: YouViewModel

    var body: some View {
        if let telling = line.telling {
            let playing = viewModel.isPlaying(line)
            Button { viewModel.togglePlayback(line) } label: {
                Group {
                    if playing {
                        Label("Stop", systemImage: "stop.fill")
                    } else {
                        Label("Hear yourself say it, \(Format.duration(ms: telling.range.end - telling.range.start))", systemImage: "play.fill")
                    }
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.oliveOnFill)
            .accessibilityIdentifier("you.lead.play")
        }
    }
}
