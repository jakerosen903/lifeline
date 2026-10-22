import Foundation
import LifelineKit

@MainActor
@Observable
final class SessionViewModel: Identifiable {
    let id = UUID()
    private(set) var state = RecorderState()
    private(set) var transcriberStatus: TranscriberAvailability?
    private(set) var isStopping = false
    private(set) var stopError: String?

    private let deps: Dependencies
    private var recorder: SessionRecorder?
    private var observation: Task<Void, Never>?

    init(deps: Dependencies) {
        self.deps = deps
    }

    var startedAt: Date { state.startedAt ?? .now }

    var statusLine: String? {
        if state.isInterrupted { return "Paused" }
        if transcriberStatus == .needsDownload { return "Getting the speech model ready…" }
        if transcriberStatus == .unsupportedLocale { return "On-device transcription is not available for your language." }
        return state.error
    }

    func start() async throws {
        let box = StatusBox()
        let recorder = deps.makeRecorder { status in Task { await box.set(status) } }
        self.recorder = recorder
        observation = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await s in recorder.states { await self?.apply(s) } }
                group.addTask { for await status in box.stream { await self?.apply(status) } }
            }
        }
        try await recorder.start()
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

/// Bridges the transcriber's status callback onto a stream the view model can observe.
private actor StatusBox {
    let stream: AsyncStream<TranscriberAvailability>
    private let continuation: AsyncStream<TranscriberAvailability>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func set(_ s: TranscriberAvailability) { continuation.yield(s) }
}
