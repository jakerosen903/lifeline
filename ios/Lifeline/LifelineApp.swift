import LifelineKit
import SwiftUI

@main
struct LifelineApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

/// Holds the dependencies and the one piece of app-level state: has the owner seen About you?
@MainActor
@Observable
final class AppModel {
    private(set) var deps: Dependencies?
    private(set) var loadError: String?
    private(set) var hasProfile = false

    init() {
        do {
            let deps = CommandLine.arguments.contains("-uiTesting") ? try Dependencies.uiTesting() : try Dependencies.live()
            self.deps = deps
            hasProfile = try deps.profile.fetch() != nil
        } catch {
            loadError = "Lifeline could not open its storage: \(error.localizedDescription)"
        }
    }

    func profileSaved() { hasProfile = true }
}

struct RootView: View {
    let model: AppModel

    var body: some View {
        if let deps = model.deps {
            if model.hasProfile {
                TimelineScreen(viewModel: TimelineViewModel(deps: deps))
            } else {
                AboutYouScreen(viewModel: AboutYouViewModel(profile: deps.profile, mode: .firstOpen) { model.profileSaved() })
            }
        } else {
            ContentUnavailableView("Something is wrong", systemImage: "exclamationmark.triangle",
                                   description: Text(model.loadError ?? ""))
        }
    }
}
