#if os(iOS)
import AVFoundation

/// The audio session for a recording session: record category, spoken-audio mode,
/// Bluetooth headsets allowed. `UIBackgroundModes: audio` keeps it alive with the screen off.
public enum AudioSessionConfigurator {
    public static func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP])
        try session.setActive(true)
    }

    public static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Asks for microphone access. Returns the granted state.
    public static func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
#endif
