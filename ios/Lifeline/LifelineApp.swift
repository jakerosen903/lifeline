import LifelineKit
import SwiftUI

@main
struct LifelineApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            // Back in the foreground with moments still waiting: sorting starts again (M6). Not while a
            // session is live or landing: its own queue is sorting those segments.
            guard phase == .active, let deps = model.deps, model.timeline?.home.presented == nil, !deps.sortingStatus().pending.isEmpty else { return }
            deps.worker.requestStart()
        }
    }
}

/// Holds the dependencies, the timeline (and through it the one live session or landing), and
/// whether first open is done. At launch: unlanded sessions resume at their landing, and the
/// sorting worker picks up whatever was left pending.
@MainActor
@Observable
final class AppModel {
    private(set) var deps: Dependencies?
    private(set) var timeline: TimelineViewModel?
    private(set) var loadError: String?
    private(set) var hasProfile = false

    init() {
        do {
            let deps = CommandLine.arguments.contains("-uiTesting") ? try Dependencies.uiTesting() : try Dependencies.live()
            self.deps = deps
            hasProfile = try deps.profile.fetch() != nil
            let timeline = TimelineViewModel(deps: deps)
            self.timeline = timeline
            let crashed = try SessionRecorder.recoverUnfinishedSessions(deps.sessions)
            if let session = try deps.sessions.unlandedSessions().first {
                if crashed.contains(where: { $0.id == session.id }) { print("[lifeline] resuming a session cut short") }
                timeline.home.present(landing: LandingViewModel(resuming: session, deps: deps))
            }
            // Off the main actor: the backfill loads the embedding model and walks every memory.
            Task.detached(priority: .utility) {
                print("[matching] \(NLSentenceEmbedder.availability)")
                // Memories kept before M4.1 get their vectors once; idempotent.
                do {
                    let n = try deps.matcher.backfill()
                    print("[matching] backfill embedded \(n) earlier memories")
                } catch {
                    print("[matching] backfill failed: \(error)")
                }
                await deps.worker.start()
                // Then the duplicate pass: pairs the reconciler calls the same wait as cards.
                await deps.duplicates.run()
            }
        } catch {
            loadError = "Lifeline could not open its storage: \(error.localizedDescription)"
        }
    }

    func profileSaved() { hasProfile = true }
}

struct RootView: View {
    let model: AppModel

    var body: some View {
        if let deps = model.deps, let timeline = model.timeline {
            if model.hasProfile {
                TimelineScreen(viewModel: timeline)
            } else {
                FirstOpenScreen(deps: deps,
                                onStart: { kind in model.profileSaved(); Task { await timeline.home.startSession(kind: kind) } },
                                onProfileSaved: { model.profileSaved() })
            }
        } else {
            ContentUnavailableView("Something is wrong", systemImage: "exclamationmark.triangle",
                                   description: Text(model.loadError ?? ""))
        }
    }
}
