import LifelineKit
import SwiftUI

/// "Lifeline speaks" (M8), on by default. Off gives the listen-only session. A session reads it
/// once, when it starts, so a change applies to the next session.
enum LifelineSpeaks {
    static let key = "lifeline.speaks"
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// The "Voice" section: the switch, and a hint when the voice Lifeline would use is a compact one.
struct SpeaksSection: View {
    @AppStorage(LifelineSpeaks.key) private var speaks = true
    @State private var onlyCompact = false

    var body: some View {
        Section {
            Toggle("Lifeline speaks", isOn: $speaks)
                .accessibilityIdentifier("settings.speaks")
            if onlyCompact {
                Text("A more natural voice can be downloaded in iOS Settings → Accessibility → Spoken Content → Voices.")
                    .font(.footnote)
                    .foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("settings.voiceHint")
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Off, Lifeline only listens. A change applies to the next session.")
        }
        .onAppear { onlyCompact = VoicePicker.onlyCompact(AVSpeechVoiceOutput.installedVoices()) }
    }
}
