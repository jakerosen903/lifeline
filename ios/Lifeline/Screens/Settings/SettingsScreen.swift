import LifelineKit
import SwiftUI

/// Settings: the About you form in edit mode, the key that lets the app sort what you say, and whether Lifeline speaks.
struct SettingsScreen: View {
    let deps: Dependencies
    /// True while a session is live or unlanded; export and restore wait for it (M6).
    var isSessionLive: () -> Bool = { false }
    @Environment(\.dismiss) private var dismiss
    @State private var key = APIKeyViewModel()
    @State private var backup: BackupViewModel?

    var body: some View {
        NavigationStack {
            Form {
                AboutYouFields(viewModel: AboutYouViewModel(profile: deps.profile, mode: .settings) {
                    // A new birthday can place every age-anchored memory.
                    _ = try? ResolverRunner(store: deps.extractionStore).run()
                    dismiss()
                })

                // A saved key starts sorting whatever waited for one (M6).
                APIKeySection(key: key, secrets: deps.secrets, onSaved: { deps.worker.requestStart() })

                SpeaksSection()

                if let backup {
                    YourCopySection(viewModel: backup)
                }
            }
            .scrollContentBackground(.hidden)
            .linenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }.accessibilityIdentifier("settings.done")
            }
            .onAppear {
                key.load(from: deps.secrets)
                if backup == nil { backup = BackupViewModel(deps: deps, isSessionLive: isSessionLive) }
            }
        }
    }
}

/// The "Sorting" section: the key field, Save and Remove, and the saved state.
private struct APIKeySection: View {
    @Bindable var key: APIKeyViewModel
    let secrets: any SecretStore
    var onSaved: () -> Void = {}

    var body: some View {
        Section {
            // A plain field: a pasted key's stray character must be visible, and the
            // stored key is never shown here anyway.
            TextField("Anthropic API key", text: $key.draft)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { if key.canSave { key.save(into: secrets); if key.isSaved { onSaved() } } }
                .accessibilityIdentifier("settings.apiKey")
            HStack {
                Button("Save key") { key.save(into: secrets); if key.isSaved { onSaved() } }
                    .buttonStyle(.borderless)
                    .disabled(!key.canSave)
                    .accessibilityIdentifier("settings.apiKeySave")
                Spacer()
                if key.isSaved {
                    Button("Remove", role: .destructive) { key.remove(from: secrets) }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("settings.apiKeyRemove")
                }
            }
            Text(key.statusText)
                .font(.footnote)
                .foregroundStyle(key.isSaved ? Theme.olive : Theme.stone)
                .accessibilityIdentifier("settings.apiKeyStatus")
        } header: {
            Text("Sorting")
        } footer: {
            Text("The key stays in this phone's Keychain. The field never shows a saved key.")
        }
    }
}

/// The key field's state. The stored key is never read back into the field, only its presence.
@MainActor
@Observable
final class APIKeyViewModel {
    var draft = ""
    private(set) var isSaved = false
    private(set) var error: String?

    var canSave: Bool { APIKeyFormat.looksValid(draft) }

    var statusText: String {
        if let error { return error }
        return isSaved ? "Key saved" : "No key. Sessions are recorded; nothing is sorted until you add one."
    }

    func load(from secrets: any SecretStore) {
        isSaved = ((try? secrets.read(.anthropicAPIKey)) ?? nil) != nil
    }

    func save(into secrets: any SecretStore) {
        do {
            try secrets.write(APIKeyFormat.normalized(draft), for: .anthropicAPIKey)
            draft = ""
            isSaved = true
            error = nil
        } catch {
            self.error = "Could not save the key: \(error.localizedDescription)"
        }
    }

    func remove(from secrets: any SecretStore) {
        do {
            try secrets.delete(.anthropicAPIKey)
            isSaved = false
            error = nil
        } catch {
            self.error = "Could not remove the key: \(error.localizedDescription)"
        }
    }
}
