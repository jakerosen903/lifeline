import LifelineKit
import SwiftUI

/// The app's root: five tabs, each with its own navigation stack and Search button, and the record bar under them.
/// The one live session or landing covers every tab.
struct SectionsScreen: View {
    let model: AppModel
    @State private var tab: AppTab = .timeline

    var body: some View {
        // RootView shows the shell only once storage is open, so these are all present.
        if let deps = model.deps, let timeline = model.timeline, let home = model.home {
            TabView(selection: $tab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                        // Every root has a Search button: a sixth tab would fold You into "More" (ruling R4).
                        NavigationStack { root(of: tab, deps: deps, timeline: timeline, home: home).searchButton(deps: deps) }
                            // The shell's notice, above the record bar on every tab. A page's own slot (You) stacks above it.
                            .safeAreaInset(edge: .bottom, spacing: 0) { ShellNoticeBar(notice: model.notice) }
                    }
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                }
            }
            .tabViewBottomAccessory { RecordBar(home: home) }
            // The app's action colour: the selected tab and the bar's controls.
            .tint(Theme.oliveText)
            .tabBarMinimizeBehavior(.never)
            .onChange(of: tab) { home.tabChanged() }
            .animation(.default, value: model.notice.text)
            // A landing resumed at launch covers the shell: the notice waits until the person can see it.
            .onChange(of: home.presented == nil, initial: true) { _, uncovered in if uncovered { model.notice.present() } }
            // Pages name the bar's subject as they appear and clear it as they leave (see `sessionContext`).
            .environment(home)
            .sheet(item: Binding(get: { home.photoStart }, set: { home.photoStart = $0 }), onDismiss: home.photoStartClosed) { start in
                PhotoStoryStartSheet(viewModel: start, pickPhotoPath: deps.pickPhotoPath)
            }
            .fullScreenCover(item: Binding(get: { home.presented }, set: { home.presented = $0 }), onDismiss: home.coverClosed) { presented in
                switch presented {
                case .session(let session):
                    SessionScreen(viewModel: session) { home.sessionEnded() }
                case .landing(let landing):
                    LandingScreen(viewModel: landing) { another in home.landingClosed(tellAnother: another); timeline.refresh() }
                }
            }
        }
    }

    @ViewBuilder private func root(of tab: AppTab, deps: Dependencies, timeline: TimelineViewModel, home: HomeViewModel) -> some View {
        switch tab {
        case .timeline: TimelineScreen(viewModel: timeline)
        case .people: PeopleTabRoot(deps: deps)
        case .places: EntityListScreen(deps: deps, type: .place)
        case .things: ThingsShelfScreen(deps: deps)
        case .you: YouScreen(deps: deps, isSessionLive: { home.presented != nil })
        }
    }
}

/// People, with "Names you mentioned" (the who's-this queue and aliases) in its overflow menu.
private struct PeopleTabRoot: View {
    let deps: Dependencies
    @State private var showNames = false

    var body: some View {
        PeopleGridScreen(deps: deps)
            .toolbar {
                Menu {
                    Button("Names you mentioned", systemImage: "person.text.rectangle") { showNames = true }
                        .accessibilityIdentifier("home.people")
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("people.more")
            }
            .navigationDestination(isPresented: $showNames) { PeopleScreen(viewModel: PeopleViewModel(deps: deps)) }
    }
}
