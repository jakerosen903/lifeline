import SwiftUI

/// Settings is the About you form in edit mode. M2 adds the extractor controls here.
struct SettingsScreen: View {
    let deps: Dependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AboutYouScreen(viewModel: AboutYouViewModel(profile: deps.profile, mode: .settings) { dismiss() })
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Done") { dismiss() }.accessibilityIdentifier("settings.done")
                }
        }
    }
}
