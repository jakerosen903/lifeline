import LifelineKit
import SwiftUI

/// An entity page (M7, S2), in the spec's order: the title, the person's own words for it, a span
/// only if they gave one, Play, the life strip, what they said about it, what it is often with,
/// then its moments in order, then tags. A section with nothing in it does not show; a page with
/// nothing at all invites a story. Nothing here asks for a date; "Add dates" waits for the person.
struct EntityScreen: View {
    /// Created once per presentation, so playback and sheets survive a parent re-render.
    @State private var viewModel: EntityViewModel
    let onChange: () -> Void

    init(viewModel: EntityViewModel, onChange: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onChange = onChange
    }
    @State private var renaming = false
    @State private var draftTitle = ""
    @State private var addingDates = false
    @State private var addingTag = false
    @State private var draftTag = ""
    /// The page an "Often with" chip opened.
    @State private var opened: Entity?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.entity.type.singular)
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.oliveText)
                    Text(viewModel.entity.title).titleStyle().accessibilityIdentifier("entity.title")
                    if let ownWords = viewModel.ownWords {
                        Text(ownWords).font(.subheadline).foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("entity.ownWords")
                    }
                    if let span = viewModel.statedSpanText {
                        Text(span).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ochreText)
                            .accessibilityIdentifier("entity.span")
                    }
                    if viewModel.firstTelling != nil {
                        Button { viewModel.togglePlayback() } label: {
                            Label(viewModel.isPlaying ? "Stop" : "Play", systemImage: viewModel.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        }
                        .buttonStyle(.borderless).tint(Theme.oliveText)
                        .accessibilityIdentifier("entity.play")
                    }
                    if let strip = viewModel.strip, strip.sentence != nil {
                        LifeStripView(strip: strip)
                    }
                }
                .listRowBackground(Color.clear)
            }

            if viewModel.entity.type == .idea {
                if !viewModel.ideaLines.isEmpty {
                    Section("Over time") {
                        ForEach(viewModel.ideaLines) { memory in line(memory) }
                    }
                }
            } else {
                if !viewModel.said.isEmpty {
                    Section(EntityPage.saidHeading(viewModel.entity.type, isOwner: viewModel.isOwner)) {
                        ForEach(viewModel.said) { memory in detail(memory) }
                    }
                }
            }

            if !viewModel.oftenWith.isEmpty {
                OftenWithSection(items: viewModel.oftenWith) { opened = $0 }
            }

            if viewModel.entity.type != .idea, !viewModel.moments.isEmpty {
                Section(EntityPage.momentsHeading(title: viewModel.entity.title, isOwner: viewModel.isOwner)) {
                    ForEach(viewModel.moments) { memory in moment(memory) }
                }
            }

            if showsInvitation {
                Section {
                    Text(EntityPage.invitation(title: viewModel.entity.title, isOwner: viewModel.isOwner))
                        .font(.body).foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("entity.invite")
                        .listRowBackground(Color.clear)
                }
            }

            // The heading sits in the row, not the section header: a List row whose only element is one
            // button is read as that button, the size of the whole row.
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tags").font(.headline).foregroundStyle(Theme.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                    FlowLayout(spacing: 6) {
                        ForEach(viewModel.tags, id: \.self) { tag in
                            Button { viewModel.removeTag(tag) } label: { Label(tag, systemImage: "xmark") }
                                .tagPill(tint: Theme.secondaryText)
                                .accessibilityIdentifier("entity.tag")
                        }
                        Button("Add a tag", systemImage: "tag") { draftTag = ""; addingTag = true }
                            .tagPill(tint: Theme.oliveText)
                            .accessibilityIdentifier("entity.addTag")
                    }
                }
                .listRowBackground(Color.clear)
            }

            if let error = viewModel.error { Text(error).foregroundStyle(.red) }
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .navigationDestination(item: $opened) { other in
            EntityScreen(viewModel: EntityViewModel(entity: other, deps: viewModel.deps), onChange: onChange)
        }
        .linenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Change the name", systemImage: "pencil") { draftTitle = viewModel.entity.title; renaming = true }
                    .accessibilityIdentifier("entity.rename")
                if viewModel.canAddDates {
                    Button("Add dates", systemImage: "calendar") { addingDates = true }
                        .accessibilityIdentifier("entity.addDates")
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityIdentifier("entity.more")
        }
        .alert("Change the name", isPresented: $renaming) {
            TextField("In your words", text: $draftTitle).accessibilityIdentifier("entity.renameField")
            Button("Save") { viewModel.rename(to: draftTitle); onChange() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Add a tag", isPresented: $addingTag) {
            TextField("home, work, or your own word", text: $draftTag).accessibilityIdentifier("entity.tagField")
            Button("Add") { viewModel.addTag(draftTag); onChange() }.accessibilityIdentifier("entity.tagSave")
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $addingDates, onDismiss: { viewModel.refresh(); onChange() }) {
            TellMeWhenSheet(title: viewModel.entity.title, birthDate: try? viewModel.deps.extractionStore.profile.ownerBirthDate(),
                            heading: "From when to when?") { viewModel.addDates($0) }
        }
        .onAppear { viewModel.refresh() }
        .onDisappear { viewModel.stop() }
        .sessionContext(viewModel.subject)
        .onChange(of: viewModel.isGone) { if viewModel.isGone { onChange(); dismiss() } }
    }

    /// Waits for the first load, so the first frame never says "nothing here" about a full page.
    private var showsInvitation: Bool {
        guard viewModel.isLoaded else { return false }
        return viewModel.entity.type == .idea ? viewModel.ideaLines.isEmpty : viewModel.said.isEmpty && viewModel.moments.isEmpty
    }

    private func open(_ memory: Memory) -> some View {
        MemoryScreen(viewModel: MemoryViewModel(memory: memory, deps: viewModel.deps), deps: viewModel.deps) { viewModel.refresh(); onChange() }
    }

    /// Something said about it: the whole quote, cleaned for reading only (the stored words stay).
    private func detail(_ memory: Memory) -> some View {
        let quote = ReadableQuote.text(memory.summaryQuote)
        return NavigationLink { open(memory) } label: {
            Text(quote).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(quote)
        }
        .accessibilityIdentifier("entity.detail")
    }

    /// A moment: its date above its title, as on Timeline.
    private func moment(_ memory: Memory) -> some View {
        NavigationLink { open(memory) } label: {
            VStack(alignment: .leading, spacing: 2) {
                if memory.range.isPlaced {
                    Text(memory.range.displayText).font(.footnote).foregroundStyle(Theme.ochreText)
                }
                Text(memory.title).foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(memory.title)
        }
        .accessibilityIdentifier("entity.moment")
    }

    /// An idea's line: its quote, and its date when it is a placed moment.
    private func line(_ memory: Memory) -> some View {
        NavigationLink { open(memory) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("“\(memory.summaryQuote)”").font(.system(.body, design: .serif)).foregroundStyle(Theme.ink).lineLimit(2)
                if memory.isMoment, memory.range.isPlaced {
                    Text(memory.range.displayText).font(.footnote).foregroundStyle(Theme.ochreText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(memory.title)
        }
        .accessibilityIdentifier(memory.isMoment ? "entity.moment" : "entity.detail")
    }
}

private extension View {
    /// A small capsule for a tag and for "Add a tag". `.titleAndIcon` is set explicitly: inside a
    /// List row the automatic label style answers an unsized proposal (FlowLayout's measure) with
    /// the icon alone in a tall frame, which drew "Add a tag" as a tall grey pill.
    func tagPill(tint: Color) -> some View {
        labelStyle(.titleAndIcon)
            .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).tint(tint)
            .fixedSize()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
