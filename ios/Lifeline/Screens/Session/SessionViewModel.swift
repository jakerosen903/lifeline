import Foundation
import LifelineKit

/// The live session. Owns the recorder, the extraction queue, the card queue and the arc.
/// A quick story never sees the clock; settling in is offered the next question when the room
/// goes quiet and a wrap-up at the planned length. Finishing never waits for sorting.
@MainActor
@Observable
final class SessionViewModel: Identifiable {
    enum ViewMode: Hashable { case listen, review }

    let id = UUID()
    let kind: SessionKind
    private(set) var state = RecorderState()
    private(set) var transcriberStatus: TranscriberAvailability?
    private(set) var isStopping = false
    /// True once the arc ended; the screen then leaves for the landing.
    private(set) var landed = false
    private(set) var startError: String?
    private(set) var stopError: String?
    private(set) var cardQueue = CardQueue()
    private(set) var extractionStatus: String?
    private(set) var opening: Opening
    private(set) var arc: SessionArc
    /// The wrap-up banner (settle in only).
    private(set) var wrapUpOffered = false
    /// The next question, offered after a quiet moment (settle in only).
    private(set) var nextPrompt: OpeningPrompt?
    /// The fixed words shown once after a disclosure.
    private(set) var disclosure: String?
    var view: ViewMode = .listen
    var changing: Memory?
    let cards: CardHandler

    let deps: Dependencies
    private var recorder: SessionRecorder?
    private var queue: ExtractionQueue?
    private var observation: Task<Void, Never>?
    private var cardObservation: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var quietTimer: Task<Void, Never>?
    private var segmentsSeen = 0
    private var declinedOffers = 0

    init(deps: Dependencies, kind: SessionKind = .quick) {
        self.deps = deps
        self.kind = kind
        cards = CardHandler(deps: deps)
        opening = deps.opening()
        arc = SessionArc(kind: kind, config: deps.arcConfig, startedAt: .now)
    }

    var prompt: String { opening.main.text }
    var alternates: [String] { opening.alternates.map(\.text) }
    var kindText: String { kind == .quick ? "a quick story" : "settling in" }
    var possibleMemoryCount: Int { cardQueue.possibleMemoryCount }
    var countText: String {
        let n = possibleMemoryCount
        return n == 1 ? "1 possible memory" : "\(n) possible memories"
    }
    var heavy: Bool { arc.heavy }
    var presentDanger: Bool { arc.presentDanger }
    var crisisLine: CrisisLine { FixedResponses.crisisLine() }

    /// Tapping an alternate makes it the question; the old main becomes an alternate.
    func swapIn(alternate index: Int) {
        guard opening.alternates.indices.contains(index) else { return }
        let chosen = opening.alternates.remove(at: index)
        opening.alternates.insert(opening.main, at: index)
        opening.main = chosen
        if let id = state.sessionID { try? deps.promptLog.record(promptID: chosen.logID, session: id) }
    }

    var startedAt: Date { state.startedAt ?? .now }
    /// True until start() has created the recorder; Finish is disabled meanwhile.
    var recorderNotStarted: Bool { recorder == nil }
    var visibleCards: [Card] { cardQueue.cards }
    var isPaused: Bool { state.isPaused }

    /// Errors first, then an interruption, then the download hint, then extraction: a stuck hint must not hide a failure.
    var statusLine: String? {
        if let error = state.error ?? stopError ?? cards.error { return error }
        if state.isInterrupted { return "Paused by another app" }
        if transcriberStatus == .needsDownload { return "Getting the speech model ready…" }
        if transcriberStatus == .unsupportedLocale { return "On-device transcription is not available for your language." }
        return extractionStatus
    }

    // MARK: - Lifecycle

    /// Starts the recorder. A failure is shown on the session screen, not thrown past it.
    func start() async {
        let (statuses, statusContinuation) = AsyncStream<TranscriberAvailability>.makeStream()
        let sessionID = SessionID()
        let queue = deps.makeExtractionQueue(for: sessionID)
        let recorder = deps.makeRecorder(onStatus: { status in statusContinuation.yield(status) }, queue: queue)
        self.recorder = recorder
        self.queue = queue
        observation = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await s in recorder.states { await self?.apply(s) } }
                group.addTask { for await status in statuses { await self?.apply(status) } }
            }
        }
        cardObservation = Task { [weak self] in
            for await event in queue.events { await self?.apply(event) }
        }
        do {
            try await recorder.start(id: sessionID, kind: kind)
            arc = SessionArc(kind: kind, config: deps.arcConfig, startedAt: startedAt)
            persistLog()
            try? deps.promptLog.record(promptID: opening.main.logID, session: sessionID)
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await self?.tick()
                }
            }
        } catch {
            startError = "Could not start recording: \(error.localizedDescription)"
            observation?.cancel()
            cardObservation?.cancel()
            self.recorder = nil
        }
    }

    /// Finish: stops capture, writes the row, returns at once. Sorting carries on behind the landing.
    func finish() async {
        guard let recorder, !isStopping else { return }
        isStopping = true
        apply(arc.apply(.finish, now: .now))
        ticker?.cancel()
        quietTimer?.cancel()
        do { try await recorder.stop() } catch { stopError = error.localizedDescription }
        persistLog()
        await queue?.finish()
        observation?.cancel()
        landed = true
    }

    func pause() async {
        guard let recorder else { return }
        do { try await recorder.pause() } catch { stopError = error.localizedDescription }
    }

    func resume() async {
        guard let recorder else { return }
        do { try await recorder.resume() } catch { stopError = error.localizedDescription }
    }

    func keepGoing() {
        wrapUpOffered = false
        apply(arc.apply(.keepGoing, now: .now))
    }

    func dismissDisclosure() { disclosure = nil }

    /// "If you like: …" taken: it becomes the question on screen.
    func takeNextPrompt() {
        guard let nextPrompt else { return }
        opening.alternates.insert(opening.main, at: 0)
        opening.main = nextPrompt
        self.nextPrompt = nil
    }

    func declineNextPrompt() {
        nextPrompt = nil
        declinedOffers += 1
    }

    // MARK: - Cards

    func accept(_ card: Card) {
        guard cards.accept(card) else { return }
        cardQueue.remove(card.id)
        if case .memory = card { cardQueue.memoryAccepted(card.id) }
    }
    func change(_ card: Card) {
        guard let memory = cards.keep(card) else { return }
        cardQueue.remove(card.id)
        cardQueue.memoryAccepted(card.id)
        changing = memory
    }
    func dismiss(_ card: Card) {
        guard cards.dismiss(card) else { return }
        cardQueue.remove(card.id)
        if case .memory = card { cardQueue.memoryDismissed(card.id) }
    }
    func undo() {
        if let card = cards.undo() { cardQueue.restore(card) }
    }
    func undoMerge() {
        if let card = cards.undoMerge() { cardQueue.restore(card) }
    }
    /// "Same story": the card joins an earlier memory; its hints follow as if it were kept.
    func sameStory(_ card: Card, into targets: [MemoryID]) {
        guard cards.sameStory(card, into: targets) else { return }
        cardQueue.remove(card.id)
        cardQueue.memoryAccepted(card.id)
    }
    func resolve(_ card: Card, _ choice: MentionChoice) { if cards.resolve(card, choice) { cardQueue.remove(card.id) } }

    // MARK: - The arc

    private func tick() {
        guard !isStopping else { return }
        apply(arc.apply(.tick(elapsed: .seconds(Date.now.timeIntervalSince(startedAt))), now: .now))
    }

    private func apply(_ effect: ArcEffect?) {
        persistLog()
        switch effect {
        case .offerWrapUp:
            wrapUpOffered = true
        case .showDisclosureCard:
            disclosure = (try? FixedResponses.disclosure()) ?? ""
            nextPrompt = nil
        case .land:
            if !isStopping { Task { await finish() } }
        case nil:
            break
        }
    }

    private var lastPersistedLogCount = 0
    private func persistLog() {
        guard arc.log.count != lastPersistedLogCount, let recorder, let json = try? SessionArc.encode(arc.log) else { return }
        lastPersistedLogCount = arc.log.count
        Task { try? await recorder.record(stageLog: json) }
    }

    /// Settling in: after a story lands and the room stays quiet, offer the next question.
    private func offerNextPromptAfterQuiet() {
        quietTimer?.cancel()
        guard kind == .settleIn, !arc.heavy, nextPrompt == nil, !isStopping else { return }
        let wait = deps.arcConfig.nextPromptAfterQuiet
        quietTimer = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.offerNextPrompt()
        }
    }

    private func offerNextPrompt() {
        guard kind == .settleIn, !arc.heavy, !state.isSpeaking, nextPrompt == nil, !isStopping else { return }
        let next = deps.opening().main
        guard next != opening.main else { return }
        nextPrompt = next
        if let id = state.sessionID { try? deps.promptLog.record(promptID: next.logID, session: id) }
    }

    // MARK: - Events

    private func apply(_ s: RecorderState) {
        let wasSpeaking = state.isSpeaking
        state = s
        if s.isSpeaking, !wasSpeaking { quietTimer?.cancel() }
        if s.segments.count > segmentsSeen {
            segmentsSeen = s.segments.count
            offerNextPromptAfterQuiet()
        }
    }
    private func apply(_ status: TranscriberAvailability) { transcriberStatus = status }

    private func apply(_ event: ExtractionEvent) {
        cardQueue.apply(event)
        switch event {
        case .failed(_, let error):
            switch error {
            case .noKey: extractionStatus = "Add a key in Settings to sort what you say"
            case .unauthorized: extractionStatus = "The key in Settings was not accepted"
            case .network, .server, .rateLimited: extractionStatus = "Not sorting right now"
            default: break
            }
        case .candidates:
            extractionStatus = nil
            cardQueue.cards.forEach { cards.shown($0) }
        case .flags(let flags, _):
            apply(arc.apply(.flags(flags), now: .now))
        case .skipped:
            break
        }
    }
}
