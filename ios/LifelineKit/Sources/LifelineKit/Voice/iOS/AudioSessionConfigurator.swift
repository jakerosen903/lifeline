#if os(iOS)
import AVFoundation

/// The audio session for each mode. Recording: record category, spoken-audio mode, Bluetooth
/// headsets allowed; `UIBackgroundModes: audio` keeps it alive with the screen off.
/// Playback: the playback category, because `.record` silences output and the default
/// category obeys the silent switch.
public enum AudioSessionConfigurator {
    public static func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP])
        try session.setActive(true)
    }

    public static func activateForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
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
