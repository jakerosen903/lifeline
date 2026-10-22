import Foundation
import LifelineKit

/// The composition root. Everything the screens need, wired once at launch.
/// `live()` uses the microphone and on-device speech; `uiTesting()` plays a script.
struct Dependencies {
    let sessions: SessionRepository
    let profile: ProfileRepository
    let audioRoot: URL
    let makeVoiceSession: @Sendable (_ onStatus: @escaping @Sendable (TranscriberAvailability) -> Void) -> any VoiceSession
    let activateAudio: @Sendable () throws -> Void
    let activatePlayback: @Sendable () throws -> Void
    let deactivateAudio: @Sendable () -> Void
    let requestMicrophone: @Sendable () async -> Bool

    func audioURL(for id: SessionID) throws -> URL {
        try AudioLocation.url(for: id, under: audioRoot)
    }

    func audioURL(for session: Session) throws -> URL {
        try AudioLocation.directory(under: audioRoot).appending(path: session.audioPath)
    }

    func makeRecorder(onStatus: @escaping @Sendable (TranscriberAvailability) -> Void) -> SessionRecorder {
        SessionRecorder(voice: makeVoiceSession(onStatus), sessions: sessions, audioURL: { try audioURL(for: $0) })
    }

    static func live() throws -> Dependencies {
        let root = try AudioLocation.defaultRoot()
        let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
        let sessions = SessionRepository(db)
        let recovered = try SessionRecorder.recoverUnfinishedSessions(sessions)
        if recovered > 0 { print("[lifeline] closed \(recovered) unfinished session(s)") }
        let pauseLog = PauseLog(url: root.appending(path: "Lifeline/pauses.log"))
        return Dependencies(
            sessions: sessions,
            profile: ProfileRepository(db),
            audioRoot: root,
            makeVoiceSession: { onStatus in
                ListenOnlyVoiceSession(
                    source: AVAudioEngineSource(),
                    sink: AudioFileWriter(),
                    transcriber: SpeechAnalyzerTranscriber(onStatus: onStatus),
                    log: { line in
                        print("[voice] \(line)")
                        Task { await pauseLog.record(line) }
                    })
            },
            activateAudio: { try AudioSessionConfigurator.activateForRecording() },
            activatePlayback: { try AudioSessionConfigurator.activateForPlayback() },
            deactivateAudio: { AudioSessionConfigurator.deactivate() },
            requestMicrophone: { await AudioSessionConfigurator.requestMicrophoneAccess() })
    }

    /// Fresh temp database, scripted voice, no audio session. Selected by the `-uiTesting` launch argument.
    static func uiTesting() throws -> Dependencies {
        let root = FileManager.default.temporaryDirectory.appending(path: "lifeline-ui-\(UUID().uuidString)")
        let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
        return Dependencies(
            sessions: SessionRepository(db),
            profile: ProfileRepository(db),
            audioRoot: root,
            makeVoiceSession: { onStatus in
                onStatus(.ready)
                return ScriptedVoiceSession(intervalMs: 800)
            },
            activateAudio: {},
            activatePlayback: {},
            deactivateAudio: {},
            requestMicrophone: { true })
    }
}
