import LifelineKit
import SwiftUI

/// An entity page (M7): the title, its details in the person's words, its span and first
/// telling, then the moments it appears in, then the people, places and things beside it.
/// Nothing here asks for a date; "Add dates" waits for the person.
struct EntityScreen: View {
    let viewModel: EntityViewModel
    let onChange: () -> Void
    @State private var renaming = false
    @State private var draftTitle = ""
    @State private var addingDates = false
    @State private var addingTag = false
    @State private var draftTag = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.entity.type.singular)
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.olive)
                    Text(viewModel.entity.title).titleStyle().accessibilityIdentifier("entity.title")
                    Text(viewModel.spanText).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ochre)
                        .accessibilityIdentifier("entity.span")
                    if viewModel.firstTelling != nil {
                        Button { viewModel.togglePlayback() } label: {
                            Label(viewModel.isPlaying ? "Stop" : "Play", systemImage: viewModel.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        }
                        .buttonStyle(.borderless).tint(Theme.olive)
                        .accessibilityIdentifier("entity.play")
                    }
                }
                .listRowBackground(Color.clear)
            }

            if viewModel.entity.type == .idea {
                Section("Over time") {
                    ForEach(viewModel.ideaLines) { memory in line(memory) }
                    if viewModel.ideaLines.isEmpty { Text("Nothing told about it yet.").foregroundStyle(Theme.stone) }
                }
                .accessibilityIdentifier("entity.ideaLines")
            } else {
                // Details first, moments below (owner's decision 6).
                Section("What you said about it") {
                    ForEach(viewModel.details) { memory in line(memory) }
                    if viewModel.details.isEmpty { Text("Nothing said about it yet.").foregroundStyle(Theme.stone) }
                }
                Section("Moments") {
                    ForEach(viewModel.moments) { memory in line(memory) }
                    if viewModel.moments.isEmpty { Text("No moments yet.").foregroundStyle(Theme.stone) }
                }
            }

            if !viewModel.coOccurring.isEmpty {
                Section("Beside it") {
                    FlowLayout(spacing: 6) {
                        ForEach(viewModel.coOccurring) { other in
                            NavigationLink {
                                EntityScreen(viewModel: EntityViewModel(entity: other, deps: viewModel.deps), onChange: onChange)
                            } label: {
                                Text(other.title).font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Theme.linen)).foregroundStyle(Theme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Tags") {
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.tags, id: \.self) { tag in
                        Button { viewModel.removeTag(tag) } label: {
                            Label(tag, systemImage: "xmark").font(.caption)
                        }
                        .buttonStyle(.bordered).tint(Theme.stone)
                        .accessibilityIdentifier("entity.tag")
                    }
                    Button("Add a tag", systemImage: "tag") { draftTag = ""; addingTag = true }
                        .buttonStyle(.bordered).tint(Theme.olive).font(.caption)
                        .accessibilityIdentifier("entity.addTag")
                }
            }

            if let error = viewModel.error { Text(error).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden)
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
        .onChange(of: viewModel.isGone) { if viewModel.isGone { onChange(); dismiss() } }
    }

    private func line(_ memory: Memory) -> some View {
        NavigationLink {
            MemoryScreen(viewModel: MemoryViewModel(memory: memory, deps: viewModel.deps), deps: viewModel.deps) { viewModel.refresh(); onChange() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("“\(memory.summaryQuote)”").font(.system(.body, design: .serif)).foregroundStyle(Theme.ink).lineLimit(2)
                if memory.isMoment, memory.range.isPlaced {
                    Text(memory.range.displayText).font(.caption).foregroundStyle(Theme.ochre)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(memory.title)
        }
        .accessibilityIdentifier(memory.isMoment ? "entity.moment" : "entity.detail")
    }
}
