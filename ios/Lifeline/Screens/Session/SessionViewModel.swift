import Foundation
import LifelineKit

@MainActor
@Observable
final class SessionViewModel: Identifiable {
    let id = UUID()
    private(set) var state = RecorderState()
    private(set) var transcriberStatus: TranscriberAvailability?
    private(set) var isStopping = false
    private(set) var startError: String?
    private(set) var stopError: String?
    private(set) var cardQueue = CardQueue()
    private(set) var extractionStatus: String?
    private(set) var opening: Opening
    let cards: CardHandler

    private let deps: Dependencies
    private var recorder: SessionRecorder?
    private var queue: ExtractionQueue?
    private var observation: Task<Void, Never>?
    private var cardObservation: Task<Void, Never>?

    init(deps: Dependencies) {
        self.deps = deps
        cards = CardHandler(deps: deps)
        opening = deps.opening()
    }

    var prompt: String { opening.main.text }
    var alternates: [String] { opening.alternates.map(\.text) }

    /// Tapping an alternate makes it the question; the old main becomes an alternate.
    func swapIn(alternate index: Int) {
        guard opening.alternates.indices.contains(index) else { return }
        let chosen = opening.alternates.remove(at: index)
        opening.alternates.insert(opening.main, at: index)
        opening.main = chosen
        if let id = state.sessionID { try? deps.promptLog.record(promptID: chosen.logID, session: id) }
    }

    var startedAt: Date { state.startedAt ?? .now }
    /// True until start() has created the recorder; Stop is disabled meanwhile.
    var recorderNotStarted: Bool { recorder == nil }
    var visibleCards: [Card] { cardQueue.cards }

    /// Errors first, then an interruption, then the download hint, then extraction: a stuck hint must not hide a failure.
    var statusLine: String? {
        if let error = state.error ?? stopError ?? cards.error { return error }
        if state.isInterrupted { return "Paused" }
        if transcriberStatus == .needsDownload { return "Getting the speech model ready…" }
        if transcriberStatus == .unsupportedLocale { return "On-device transcription is not available for your language." }
        return extractionStatus
    }

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
            try await recorder.start(id: sessionID)
            try? deps.promptLog.record(promptID: opening.main.logID, session: sessionID)
        } catch {
            startError = "Could not start recording: \(error.localizedDescription)"
            observation?.cancel()
            cardObservation?.cancel()
            self.recorder = nil
        }
    }

    func stop() async {
        guard let recorder, !isStopping else { return }
        isStopping = true
        do { try await recorder.stop() } catch { stopError = error.localizedDescription }
        await queue?.finish()
        observation?.cancel()
    }

    // MARK: - Cards

    func accept(_ card: Card) {
        guard cards.accept(card) else { return }
        cardQueue.remove(card.id)
        if case .memory = card { cardQueue.memoryAccepted(card.id) }
    }
    func dismiss(_ card: Card) {
        guard cards.dismiss(card) else { return }
        cardQueue.remove(card.id)
        if case .memory = card { cardQueue.memoryDismissed(card.id) }
    }
    func resolve(_ card: Card, _ choice: MentionChoice) { if cards.resolve(card, choice) { cardQueue.remove(card.id) } }

    private func apply(_ s: RecorderState) { state = s }
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
        case .flags, .skipped:
            break
        }
    }
}
