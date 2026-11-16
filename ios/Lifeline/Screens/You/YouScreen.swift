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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let portrait = viewModel.portrait {
                    PortraitHeader(portrait: portrait, deps: viewModel.deps, onChange: changed)
                    if let lead = viewModel.lead {
                        // 12.3333, not 12: at 12 the chips below land where the accessibility frame reads 43.99999999999994 high (float noise, not a layout fault).
                        VStack(alignment: .leading, spacing: 12.3333) {
                            Text(lead.drawnText).font(.system(.title, design: .serif)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(lead.text)
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
                if let error = viewModel.error {
                    // Ink text for contrast; the red is only in the symbol, as on the record bar.
                    Label {
                        Text(error).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("you.error")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .linenBackground()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Settings") { showSettings = true }
                .accessibilityIdentifier("home.settings")
        }
        .sheet(isPresented: $showSettings, onDismiss: changed) {
            SettingsScreen(deps: viewModel.deps, isSessionLive: isSessionLive)
        }
        // The root appeared (tab selected, or back from a pushed page): a fresh lead (decision 8).
        // While a tag is chosen the lead stays (decisions 8 and 12): a new lead must not take the only fact with that tag.
        .onAppear { isVisible = true; viewModel.refresh(newLead: viewModel.tag == nil) }
        .onDisappear { isVisible = false; viewModel.stop() }
        // A recording starting under the cover must not talk over this page's player.
        .onChange(of: home?.presented != nil) { _, covered in if covered { viewModel.stop() } }
        // A story told from here lands under a cover; when it closes, read what it added and keep the lead.
        .onChange(of: home?.coverClosings) { if isVisible { viewModel.refresh(newLead: false) } }
        .sessionContext(viewModel.ownerSubject)
    }

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
                ForEach(ideas) { line in PortraitIdeaRow(line: line, deps: deps, onChange: changed) }
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
