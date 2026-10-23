#if os(iOS)
import AVFoundation

/// The audio session for each mode. Recording: play-and-record category with spoken-audio
/// mode, Bluetooth headsets allowed; `UIBackgroundModes: audio` keeps it alive with the
/// screen off. The spoken-audio mode is rejected (OSStatus -50) with the plain record
/// category on device, and play-and-record is what the voice interviewer needs later anyway.
/// Playback: the playback category, which ignores the silent switch and routes to the speaker.
public enum AudioSessionConfigurator {
    public static func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
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
