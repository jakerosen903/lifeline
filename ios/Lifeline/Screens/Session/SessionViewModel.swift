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

    private let deps: Dependencies
    private var recorder: SessionRecorder?
    private var observation: Task<Void, Never>?

    init(deps: Dependencies) {
        self.deps = deps
    }

    var startedAt: Date { state.startedAt ?? .now }
    /// True until start() has created the recorder; Stop is disabled meanwhile.
    var recorderNotStarted: Bool { recorder == nil }

    /// Errors first, then an interruption, then the download hint: a stuck hint must not hide a failure.
    var statusLine: String? {
        if let error = state.error ?? stopError { return error }
        if state.isInterrupted { return "Paused" }
        if transcriberStatus == .needsDownload { return "Getting the speech model ready…" }
        if transcriberStatus == .unsupportedLocale { return "On-device transcription is not available for your language." }
        return nil
    }

    /// Starts the recorder. A failure is shown on the session screen, not thrown past it.
    func start() async {
        let (statuses, statusContinuation) = AsyncStream<TranscriberAvailability>.makeStream()
        let recorder = deps.makeRecorder { status in statusContinuation.yield(status) }
        self.recorder = recorder
        observation = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await s in recorder.states { await self?.apply(s) } }
                group.addTask { for await status in statuses { await self?.apply(status) } }
            }
        }
        do {
            try await recorder.start()
        } catch {
            startError = "Could not start recording: \(error.localizedDescription)"
            observation?.cancel()
            self.recorder = nil
        }
    }

    func stop() async {
        guard let recorder, !isStopping else { return }
        isStopping = true
        do { try await recorder.stop() } catch { stopError = error.localizedDescription }
        observation?.cancel()
    }

    private func apply(_ s: RecorderState) { state = s }
    private func apply(_ status: TranscriberAvailability) { transcriberStatus = status }
}
