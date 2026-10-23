import Foundation
import LifelineKit

/// The composition root. Everything the screens need, wired once at launch.
/// `live()` uses the microphone, on-device speech, the Keychain and the Messages API;
/// `uiTesting()` plays scripts and keeps secrets in memory.
struct Dependencies {
    let sessions: SessionRepository
    let profile: ProfileRepository
    let audioRoot: URL
    let makeVoiceSession: @Sendable (_ onStatus: @escaping @Sendable (TranscriberAvailability) -> Void) -> any VoiceSession
    let activateAudio: @Sendable () throws -> Void
    let activatePlayback: @Sendable () throws -> Void
    let deactivateAudio: @Sendable () -> Void
    let requestMicrophone: @Sendable () async -> Bool
    let secrets: any SecretStore
    let extraction: any ExtractionService
    let extractionStore: ExtractionStore
    let actions: CandidateActions
    let promptLog: PromptLogRepository
    /// The arc's numbers: short under `-uiTesting`.
    let arcConfig: ArcConfig

    /// A fresh question for the next session: an open thread first, then the bank without repeats.
    func opening() -> Opening {
        let bank = (try? PromptBank.load()) ?? []
        let curiosity = (try? extractionStore.curiosity.open()) ?? []
        let used = (try? promptLog.lastUsed()) ?? [:]
        return OpeningChooser.choose(curiosity: curiosity, bank: bank, lastUsed: used, now: .now)
    }

    func audioURL(for id: SessionID) throws -> URL {
        try AudioLocation.url(for: id, under: audioRoot)
    }

    func audioURL(for session: Session) throws -> URL {
        try AudioLocation.directory(under: audioRoot).appending(path: session.audioPath)
    }

    func makeExtractionQueue(for session: SessionID) -> ExtractionQueue {
        ExtractionQueue(session: session, service: extraction, store: extractionStore, log: { print("[extract] \($0)") })
    }

    /// A recorder whose stored segments feed `queue`. Finish returns at once; the queue keeps
    /// sorting in the background and the launch-time worker picks up anything it leaves.
    func makeRecorder(onStatus: @escaping @Sendable (TranscriberAvailability) -> Void, queue: ExtractionQueue) -> SessionRecorder {
        SessionRecorder(voice: makeVoiceSession(onStatus), sessions: sessions, audioURL: { try audioURL(for: $0) },
                        hooks: RecorderHooks(onSegmentStored: { id in Task { await queue.enqueue(id) } },
                                             onStopped: { Task { await queue.drain() } }))
    }

    static func live() throws -> Dependencies {
        let root = try AudioLocation.defaultRoot()
        let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
        let sessions = SessionRepository(db)
        let resume = try SessionRecorder.recoverUnfinishedSessions(sessions)
        if !resume.isEmpty { print("[lifeline] \(resume.count) session(s) to resume at the landing") }
        let pauseLog = PauseLog(url: root.appending(path: "Lifeline/pauses.log"))
        let secrets = KeychainSecretStore()
        let store = ExtractionStore(db)
        return Dependencies(
            sessions: sessions,
            profile: ProfileRepository(db),
            audioRoot: root,
            makeVoiceSession: { onStatus in
                ListenOnlyVoiceSession(
                    source: AVAudioEngineSource(),
                    sink: AudioFileWriter(),
                    transcriber: SpeechAnalyzerTranscriber(onStatus: onStatus, log: { print("[speech] \($0)") }),
                    log: { line in
                        print("[voice] \(line)")
                        Task { await pauseLog.record(line) }
                    })
            },
            activateAudio: { try AudioSessionConfigurator.activateForRecording() },
            activatePlayback: { try AudioSessionConfigurator.activateForPlayback() },
            deactivateAudio: { AudioSessionConfigurator.deactivate() },
            requestMicrophone: { await AudioSessionConfigurator.requestMicrophoneAccess() },
            secrets: secrets,
            extraction: AnthropicExtractionService(apiKey: { try? secrets.read(.anthropicAPIKey) }),
            extractionStore: store,
            actions: CandidateActions(store: store),
            promptLog: PromptLogRepository(db),
            arcConfig: .default)
    }

    /// Fresh temp database, scripted voice and extraction, in-memory secrets with a fake key.
    /// Selected by the `-uiTesting` launch argument.
    static func uiTesting() throws -> Dependencies {
        let root = FileManager.default.temporaryDirectory.appending(path: "lifeline-ui-\(UUID().uuidString)")
        let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
        let store = ExtractionStore(db)
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
            requestMicrophone: { true },
            secrets: InMemorySecretStore([.anthropicAPIKey: "sk-ant-api03-" + String(repeating: "x", count: 40)]),
            extraction: ScriptedExtractionService(delayMs: 200, heavy: CommandLine.arguments.contains("-uiTesting-heavy")),
            extractionStore: store,
            actions: CandidateActions(store: store),
            promptLog: PromptLogRepository(db),
            arcConfig: .uiTesting)
    }
}
