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
    /// Durable sorting: started at launch, cancelled per session before a delete.
    let worker: SortingWorker
    /// "Same as X?": retrieval by on-device embeddings; the extractor decides, the person confirms.
    let matcher: MemoryMatcher
    /// "Are these the same?": the reconciler judges pairs in a batch; the pass runs after the
    /// backfill at launch and a little after every Keep (M5).
    let reconcile: any ReconcileService
    let duplicates: DuplicatePass
    /// What is still sorting, for the status line (M6).
    let reporter: SortingReporter
    /// Under `-uiTesting-restoreFrom <path>`: Restore stages this file without the picker.
    var restoreFromPath: String? = nil
    /// Under `-uiTesting`: Export keeps the file in Documents and shows no share sheet, which a UI test cannot drive.
    var exportWithoutShareSheet = false

    /// "1.0 (12)": the marketing version and the build, for the backup manifest.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var hasKey: Bool { ((try? secrets.read(.anthropicAPIKey)) ?? nil) != nil }

    func sortingStatus() -> SortingStatus {
        (try? SortingStatus.current(store: extractionStore, reporter: reporter, hasKey: hasKey)) ?? .empty
    }

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
        ExtractionQueue(session: session, service: extraction, store: extractionStore, matcher: matcher, reporter: reporter, log: { print("[extract] \($0)") })
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
        // A restore the person staged is applied now, before anything opens the database (M6).
        if try Backup.applyPendingRestore(root: root) { print("[backup] restored a copy at launch") }
        let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
        let sessions = SessionRepository(db)
        let pauseLog = PauseLog(url: root.appending(path: "Lifeline/pauses.log"))
        let secrets = KeychainSecretStore()
        let store = ExtractionStore(db)
        let extraction = AnthropicExtractionService(apiKey: { try? secrets.read(.anthropicAPIKey) })
        let matcher = MemoryMatcher(store: store, embedder: NLSentenceEmbedder())
        let actions = CandidateActions(store: store, matcher: matcher)
        let reconcile = AnthropicReconcileService(apiKey: { try? secrets.read(.anthropicAPIKey) })
        let reporter = SortingReporter()
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
            extraction: extraction,
            extractionStore: store,
            actions: actions,
            promptLog: PromptLogRepository(db),
            arcConfig: .default,
            worker: SortingWorker(store: store, service: extraction, matcher: matcher, reporter: reporter, log: { print("[sorting] \($0)") }),
            matcher: matcher,
            reconcile: reconcile,
            duplicates: DuplicatePass(store: store, matcher: matcher, reconcile: reconcile, actions: actions, reporter: reporter, log: { print($0) }),
            reporter: reporter)
    }

    /// Fresh temp database, scripted voice and extraction, in-memory secrets with a fake key.
    /// Selected by the `-uiTesting` launch argument.
    static func uiTesting() throws -> Dependencies {
        // `-uiTesting-db <dir>` reuses one directory across a terminate and relaunch (crash-resume tests).
        let args = CommandLine.arguments
        let root: URL
        if let i = args.firstIndex(of: "-uiTesting-db"), i + 1 < args.count {
            root = URL(fileURLWithPath: args[i + 1])
        } else {
            root = FileManager.default.temporaryDirectory.appending(path: "lifeline-ui-\(UUID().uuidString)")
        }
        if try Backup.applyPendingRestore(root: root) { print("[backup] restored a copy at launch") }
        let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
        let store = ExtractionStore(db)
        // `-uiTesting-slowExtract`: seconds per segment, for tests that watch sorting go on; `-uiTesting-noKey`:
        // an empty key store, and a scripted service that refuses to sort without one, as the live one does.
        let secrets = InMemorySecretStore(args.contains("-uiTesting-noKey") ? [:] : [.anthropicAPIKey: "sk-ant-api03-" + String(repeating: "x", count: 40)])
        let scripted = ScriptedExtractionService(delayMs: args.contains("-uiTesting-slowExtract") ? 4_000 : 200, heavy: args.contains("-uiTesting-heavy"))
        let extraction = KeyGatedExtractionService(inner: scripted, hasKey: { ((try? secrets.read(.anthropicAPIKey)) ?? nil) != nil })
        // Word-overlap vectors under test: deterministic, and enough for the scripted retelling
        // to be retrieved into the packet so the scripted extractor can name it.
        let matcher = MemoryMatcher(store: store, embedder: HashingEmbedder())
        let actions = CandidateActions(store: store, matcher: matcher)
        let reconcile = ScriptedReconcileService()
        let reporter = SortingReporter()
        var deps = Dependencies(
            sessions: SessionRepository(db),
            profile: ProfileRepository(db),
            audioRoot: root,
            makeVoiceSession: { onStatus in
                onStatus(.ready)
                // `-uiTesting-slow`: a segment every few seconds, for tests that act between segments.
                return ScriptedVoiceSession(intervalMs: args.contains("-uiTesting-slow") ? 2_500 : 800)
            },
            activateAudio: {},
            activatePlayback: {},
            deactivateAudio: {},
            requestMicrophone: { true },
            secrets: secrets,
            extraction: extraction,
            extractionStore: store,
            actions: actions,
            promptLog: PromptLogRepository(db),
            arcConfig: .uiTesting,
            worker: SortingWorker(store: store, service: extraction, matcher: matcher, reporter: reporter),
            matcher: matcher,
            reconcile: reconcile,
            duplicates: DuplicatePass(store: store, matcher: matcher, reconcile: reconcile, actions: actions, reporter: reporter, log: { line in
                print(line)
                // UI tests cannot see the app's console; the pass leaves its lines next to the test database.
                let url = root.appending(path: "duplicates.log")
                if let data = (line + "\n").data(using: .utf8) {
                    if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(data); try? handle.close() }
                    else { try? data.write(to: url) }
                }
            }),
            reporter: reporter)
        if let i = args.firstIndex(of: "-uiTesting-restoreFrom"), i + 1 < args.count { deps.restoreFromPath = args[i + 1] }
        deps.exportWithoutShareSheet = true
        return deps
    }
}

/// Under UI testing: the scripted service, but it refuses to sort without a key, as the live one does.
struct KeyGatedExtractionService: ExtractionService {
    let inner: ScriptedExtractionService
    let hasKey: @Sendable () -> Bool
    var version: String { inner.version }

    func extract(_ request: ExtractionRequest) async throws(ExtractionError) -> ExtractionResponse {
        guard hasKey() else { throw .noKey }
        return try await inner.extract(request)
    }
}
