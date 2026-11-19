import LifelineKit
import SwiftUI

/// You (S3): a portrait of the person in their own words. The header and strip, one line of theirs in
/// large type, then "Who you are", "How it felt", "What you think" and "What you're hoping for".
/// A part with nothing in it does not show; with nothing told, one line says where stories will go.
/// A story told from here is about yourself.
struct YouScreen: View {
    /// Created once per presentation: a parent re-render must not reload it.
    @State private var viewModel: YouViewModel
    @State private var showSettings = false
    @State private var addingPhoto = false
    /// The photo open in the viewer.
    @State private var viewing: PlacedPhoto?
    /// Absent outside the shell (a preview): then nothing watches the session cover.
    @Environment(HomeViewModel.self) private var home: HomeViewModel?
    /// The root of its stack, on screen. The session cover sends no onDisappear, so the root stays visible under it.
    @State private var isVisible = false
    let isSessionLive: () -> Bool

    init(deps: Dependencies, isSessionLive: @escaping () -> Bool) {
        _viewModel = State(initialValue: YouViewModel(deps: deps))
        self.isSessionLive = isSessionLive
    }

    var body: some View {
        // A plain stack, not a List or a lazy stack: tens of lines, each there for VoiceOver without scrolling (decision 19).
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let portrait = viewModel.portrait {
                        PortraitHeader(portrait: portrait, cover: viewModel.shelf?.cover, photos: viewModel.shelf?.photos ?? [],
                                       isAdding: viewModel.shelf?.isAdding ?? false, label: viewModel.photoLabel,
                                       cache: viewModel.deps.photoImages, deps: viewModel.deps, onOpen: { viewing = $0 },
                                       onMove: { id, index in Task { await viewModel.movePhoto(id, to: index) } }, onChange: changed)
                            .id(Self.top)
                        if let lead = viewModel.lead {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(lead.drawnText).font(.system(.title, design: .serif)).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityLabel(lead.text)
                                    .lineMenu(lead, viewModel)
                                    .accessibilityIdentifier("you.lead")
                                PortraitLeadPlayButton(line: lead, viewModel: viewModel)
                            }
                        }
                        parts
                        if viewModel.isLoaded, portrait.isEmpty {
                            Text(EntityPage.invitation(title: "", isOwner: true))
                                .font(.body).foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("you.invite")
                        }
                    }
                    if let error = viewModel.error { ErrorLine(text: error).accessibilityIdentifier("you.error") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // A new cover is the page's news: the page goes back to the top, where the cover is.
            .onChange(of: viewModel.shelf?.cover?.id) { withAnimation { proxy.scrollTo(Self.top, anchor: .top) } }
        }
        // One slot, pinned above the record bar: "Hidden." with Undo, or why something failed. Wherever the line
        // was on the page, its message is on screen, and the page does not jump.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = viewModel.notice {
                // "Hidden." is not an error. Undo shows while the hide can still be taken back, also beside an error,
                // so a failure never takes the way back with it.
                NoticeSlot(text: notice.text, isError: notice != .hidden, identifier: notice == .hidden ? "you.hidden" : "you.error") {
                    if viewModel.hiddenID != nil {
                        Button("Undo") { viewModel.undoHide() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(Theme.oliveOnFill)
                            .accessibilityIdentifier("you.undo")
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .animation(.default, value: viewModel.notice)
        .linenBackground()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Settings") { showSettings = true }
                .accessibilityIdentifier("home.settings")
            // Photos hang on the owner's entity: with no owner yet there is nowhere to add one.
            if viewModel.shelf != nil {
                Menu {
                    Button("Add a photo", systemImage: "photo") { viewModel.clearError(); addingPhoto = true }
                        .accessibilityIdentifier("you.addPhoto")
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("you.more")
            }
        }
        .addPhotoFlow(isPresented: $addingPhoto, deps: viewModel.deps, shelf: viewModel.shelf,
                      onFile: { file, assetID in await viewModel.addPhoto(fileAt: file, assetLocalID: assetID) },
                      onError: { viewModel.photoFailed($0) })
        .photoViewerSheet(item: $viewing, home: home) { placed, tellStory in
            PhotoViewer(photo: placed, label: viewModel.photoLabel, canMakeCover: !placed.isCover, cache: viewModel.deps.photoImages,
                        onMakeCover: { await viewModel.makeCover(placed.id) },
                        onRemove: { await viewModel.removePhoto(placed.id) },
                        onTellStory: tellStory)
        }
        .sheet(isPresented: $showSettings, onDismiss: changed) {
            SettingsScreen(deps: viewModel.deps, isSessionLive: isSessionLive)
        }
        // The root appeared (tab selected, or back from a pushed page): a fresh lead (decision 8).
        // While a tag is chosen the lead stays (decisions 8 and 12): a new lead must not take the only fact with that tag.
        .onAppear { isVisible = true; viewModel.refresh(newLead: viewModel.tag == nil) }
        .onDisappear { isVisible = false; viewModel.stop(); viewModel.clearSlot() }
        // A recording starting under the cover must not talk over this page's player.
        .onChange(of: home?.presented != nil) { _, covered in if covered { viewModel.stop() } }
        .confirmationDialog("Delete this memory?", isPresented: Binding(get: { viewModel.deleteTarget != nil }, set: { if !$0 { viewModel.deleteTarget = nil } }),
                            titleVisibility: .visible, presenting: viewModel.deleteTarget) { line in
            Button("Delete “\(line.memory?.title ?? line.text)”", role: .destructive) { viewModel.delete(line) }
                .accessibilityIdentifier("row.confirmDelete")
            Button("Cancel", role: .cancel) { viewModel.deleteTarget = nil }
        } message: { _ in
            Text("The memory, its people and its dates go. Your recording stays in Sessions.")
        }
        // A story told from here lands under a cover; when it closes, read what it added and keep the lead.
        .onChange(of: home?.coverClosings) { if isVisible { viewModel.refresh(newLead: false) } }
        .sessionContext(viewModel.ownerSubject)
    }

    /// The header's id, for the scroll back to the cover.
    private static let top = "you.top"

    /// Something changed elsewhere (Settings, a pushed page): read again, keeping the lead.
    private func changed() { viewModel.refresh(newLead: false) }

    @ViewBuilder private var parts: some View {
        let deps = viewModel.deps
        let who = viewModel.lines(.whoYouAre)
        if !who.isEmpty {
            PortraitPart(heading: "Who you are") {
                if !viewModel.tags.isEmpty {
                    PortraitChips(tags: viewModel.tags, chosen: $viewModel.tag)
                }
                ForEach(who) { line in
                    PortraitSaidRow(line: line, note: line.tags.isEmpty ? nil : line.tags.joined(separator: ", "), viewModel: viewModel, onChange: changed)
                }
            }
        }
        let felt = viewModel.lines(.howItFelt)
        if !felt.isEmpty {
            PortraitPart(heading: "How it felt") {
                ForEach(felt) { line in PortraitFeelingCard(line: line, viewModel: viewModel, onChange: changed) }
            }
        }
        let ideas = viewModel.lines(.whatYouThink)
        if !ideas.isEmpty {
            PortraitPart(heading: "What you think") {
                ForEach(ideas) { line in PortraitIdeaRow(line: line, viewModel: viewModel, onChange: changed) }
            }
        }
        let hopes = viewModel.lines(.hopingFor)
        if !hopes.isEmpty {
            PortraitPart(heading: "What you're hoping for") {
                ForEach(hopes) { line in
                    PortraitSaidRow(line: line, note: viewModel.saidWhen(line), viewModel: viewModel, onChange: changed)
                }
            }
        }
    }
}
