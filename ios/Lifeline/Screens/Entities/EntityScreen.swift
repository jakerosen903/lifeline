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
    @State private var addingPhoto = false
    /// The open "Who is this?" sheet's model, made once at the tap (the page re-renders and must not re-read the people).
    @State private var asking: Asking?
    private struct Asking: Identifiable {
        let id: String
        let model: WhoIsThisViewModel
    }
    /// The photo open in the viewer.
    @State private var viewing: PlacedPhoto?
    @Environment(\.dismiss) private var dismiss
    /// Absent outside the shell (a preview): then nothing watches the session cover.
    @Environment(HomeViewModel.self) private var home: HomeViewModel?
    /// The top page of its stack. A page under a cover stays visible: the cover sends no onDisappear.
    @State private var isVisible = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        // No photo, no frame: the page looks complete without one.
                        if hasPhotos, viewModel.shelf.isAdding || viewModel.shelf.cover != nil { photoHeader.padding(.bottom, 10) }
                        Text(viewModel.entity.type.singular)
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.oliveText)
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
                            // The 44-point frame sits in the label: outside the Button it grows the row,
                            // not the area a tap reaches.
                            Button { viewModel.togglePlayback() } label: {
                                Label(viewModel.isPlaying ? "Stop" : "Play", systemImage: viewModel.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless).tint(Theme.oliveText)
                            .accessibilityIdentifier("entity.play")
                        }
                        if let strip = viewModel.strip, strip.sentence != nil {
                            LifeStripView(strip: strip)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .id(Self.top)
                }

                if viewModel.entity.type == .idea {
                    if !viewModel.ideaLines.isEmpty {
                        Section {
                            ForEach(viewModel.ideaLines) { memory in line(memory) }
                        } header: { Text("Over time").sectionHeadingStyle() }
                    }
                } else {
                    if !viewModel.said.isEmpty {
                        Section {
                            ForEach(viewModel.said) { memory in detail(memory) }
                        } header: { Text(EntityPage.saidHeading(viewModel.entity.type, isOwner: viewModel.isOwner)).sectionHeadingStyle() }
                    }
                }

                if !viewModel.oftenWith.isEmpty {
                    OftenWithSection(items: viewModel.oftenWith) { opened = $0 }
                }

                if hasPhotos, viewModel.shelf.photos.count >= 2 {
                    Section {
                        PhotoRow(photos: viewModel.shelf.photos, label: viewModel.photoLabel, cache: viewModel.deps.photoImages) { viewing = $0 }
                            .listRowBackground(Color.clear)
                    }
                }

                if viewModel.entity.type != .idea, !viewModel.moments.isEmpty {
                    Section {
                        ForEach(viewModel.moments) { memory in moment(memory) }
                    } header: { Text(EntityPage.momentsHeading(title: viewModel.entity.title, isOwner: viewModel.isOwner)).sectionHeadingStyle() }
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
                        Text("Tags").sectionHeadingStyle()
                        FlowLayout(spacing: 6) {
                            ForEach(viewModel.tags, id: \.self) { tag in
                                Button { viewModel.removeTag(tag) } label: { TagPill(title: tag, systemImage: "xmark", tint: Theme.secondaryText) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("entity.tag")
                            }
                            Button { draftTag = ""; addingTag = true } label: { TagPill(title: "Add a tag", systemImage: "tag", tint: Theme.oliveOnFill) }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("entity.addTag")
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                if let error = viewModel.error { Text(error).foregroundStyle(.red) }
            }
            // A new cover is the page's news: the page goes back to the top, where the cover is.
            .onChange(of: viewModel.shelf.cover?.id) { withAnimation { proxy.scrollTo(Self.top, anchor: .top) } }
        }
        .scrollContentBackground(.hidden)
        // The person is gone and the notice is still up: the page shows what it last read, and writes nothing.
        .disabled(viewModel.isGone)
        .navigationDestination(item: $opened) { other in
            EntityScreen(viewModel: EntityViewModel(entity: other, deps: viewModel.deps), onChange: onChange)
        }
        .linenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                if hasPhotos {
                    Button("Add a photo", systemImage: "photo") { viewModel.clearPhotoError(); addingPhoto = true }
                        .accessibilityIdentifier("entity.addPhoto")
                }
                Button("Change the name", systemImage: "pencil") { draftTitle = viewModel.entity.title; renaming = true }
                    .accessibilityIdentifier("entity.rename")
                if viewModel.canAddDates {
                    Button("Add dates", systemImage: "calendar") { addingDates = true }
                        .accessibilityIdentifier("entity.addDates")
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .disabled(viewModel.isGone)
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
        .addPhotoFlow(isPresented: $addingPhoto, deps: viewModel.deps, shelf: viewModel.shelf,
                      onFile: { file, assetID in await viewModel.addPhoto(fileAt: file, assetLocalID: assetID); onChange() },
                      onError: { viewModel.photoFailed($0) })
        .photoViewerSheet(item: $viewing, home: home) { placed, tellStory in
            PhotoViewer(photo: placed, label: viewModel.photoLabel, canMakeCover: !placed.isCover, cache: viewModel.deps.photoImages,
                        onMakeCover: { await viewModel.makeCover(placed.id); onChange() },
                        onRemove: { await viewModel.removePhoto(placed.id); onChange() },
                        onTellStory: tellStory)
        }
        .photoErrorSlot(viewModel.photoError)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PersonMoveNoticeSlot(notice: viewModel.personMove) { if viewModel.undoPersonMove() { onChange() } }
        }
        .animation(.default, value: viewModel.personMove.text)
        .sheet(item: $asking) { asking in
            WhoIsThisSheet(viewModel: asking.model) { outcome in
                self.asking = nil
                viewModel.personSheetDone(outcome)
                onChange()
            }
        }
        .onAppear { isVisible = true; viewModel.refresh() }
        .onDisappear { isVisible = false; viewModel.stop(); viewModel.clearPhotoError() }
        // A session started here lands under a cover; when it closes, read what it added.
        .onChange(of: home?.coverClosings) { if isVisible { viewModel.refresh() } }
        .sessionContext(viewModel.subject)
        .onChange(of: viewModel.shouldClose) { if viewModel.shouldClose { onChange(); dismiss() } }
    }

    /// The header row's id, for the scroll back to the cover.
    private static let top = "entity.top"

    /// Photos hang on a person, place or thing. An idea keeps its layout.
    private var hasPhotos: Bool { viewModel.entity.type != .idea }

    /// The cover, or "Adding the photo…" where a first photo will go. Neither shows on a page without a photo.
    @ViewBuilder private var photoHeader: some View {
        if viewModel.shelf.isAdding { PhotoAddingLine() }
        if let cover = viewModel.shelf.cover {
            PhotoHeader(cover: cover, label: viewModel.photoLabel, cache: viewModel.deps.photoImages) {
                viewing = viewModel.shelf.photos.first(where: \.isCover)
            }
        }
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
        let quote = EntityPage.readableQuote(of: memory)
        return guessable(memory, identifier: "entity.detail") {
            Text(quote).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(quote)
        }
    }

    /// A moment: its date above its title, as on Timeline. A half-open range has no date to show.
    /// VoiceOver reads the title, then the date with its uncertainty ("around 1998").
    private func moment(_ memory: Memory) -> some View {
        guessable(memory, identifier: "entity.moment") {
            VStack(alignment: .leading, spacing: 2) {
                if memory.range.isDated {
                    Text(memory.range.displayText).font(.footnote).foregroundStyle(Theme.ochreText)
                }
                Text(memory.title).foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(memory.title)
            .accessibilityValue(memory.range.isDated ? memory.range.displayText : "")
        }
    }

    /// A row that opens its memory. When the person is here by a guess, the row is a card with the dashed
    /// mark, the "Assumed" line and the two answers. Otherwise it is the plain row, unchanged (PC3).
    @ViewBuilder private func guessable<Label: View>(_ memory: Memory, identifier: String, @ViewBuilder label: () -> Label) -> some View {
        if let link = viewModel.guessed[memory.id] {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { open(memory) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        label()
                        if let line = PersonChipLine.text(origin: link.origin, saidName: link.saidName,
                                                          fromContact: link.personFromContact, contacts: .none) {   // PB1: Task 5 passes the cache's value
                            Text(line).font(.footnote).foregroundStyle(Theme.ochreText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier(identifier)
                VStack(alignment: .leading, spacing: 4) {
                    Button(PersonChipLine.confirmLabel(name: link.person.displayName)) { viewModel.confirm(memory.id) }
                        .buttonStyle(.borderedProminent).tint(Theme.oliveOnFill).controlSize(.large)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("entity.moment.confirm")
                    Button("Someone else\u{2026}") {
                        asking = Asking(id: link.id, model: WhoIsThisViewModel(source: .link(link), deps: viewModel.deps))
                    }
                    .buttonStyle(.bordered).tint(Theme.oliveOnFill).controlSize(.large)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("entity.moment.someoneElse")
                }
            }
            .padding(14)
            .assumedOutline()
            // A container element: without it the identifier passes down and replaces the row's and the buttons' own.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("entity.moment.assumed")
        } else {
            NavigationLink { open(memory) } label: { label() }
                .accessibilityIdentifier(identifier)
        }
    }

    /// An idea's line: its quote, and its date when it is a placed moment.
    private func line(_ memory: Memory) -> some View {
        NavigationLink { open(memory) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(EntityPage.ownWordsQuote(of: memory).map { "“\($0)”" } ?? memory.title).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink).lineLimit(2)
                if memory.isMoment, memory.range.isDated {
                    Text(memory.range.displayText).font(.footnote).foregroundStyle(Theme.ochreText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(memory.title)
            .accessibilityValue(memory.isMoment && memory.range.isDated ? memory.range.displayText : "")
        }
        .accessibilityIdentifier(memory.isMoment ? "entity.moment" : "entity.detail")
    }
}

/// A small capsule for a tag and for "Add a tag", drawn in the button's label. The 44-point
/// frame and its content shape are in the label too, so the tap area is the button's own.
/// The text uses the tint on a 12% fill of itself: `oliveOnFill` and `secondaryText` both reach
/// 4.5:1 on that fill over linen, the page's surface.
/// `.titleAndIcon` is set explicitly: inside a List row the automatic label style answers an
/// unsized proposal (FlowLayout's measure) with the icon alone in a tall frame.
private struct TagPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.12)))
            // Never squeezed shorter than its text; narrower only when a long tag must wrap in the row.
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
