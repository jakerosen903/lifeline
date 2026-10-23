import Foundation
import Synchronization
@testable import LifelineKit

/// Scripted extraction results. Each call consumes the next entry; when the script is empty
/// it returns an empty output so queues can drain.
final class FakeExtractionService: ExtractionService, Sendable {
    let version = "fake"
    private let state = Mutex<(script: [Result<ExtractorOutput, ExtractionError>], requests: [ExtractionRequest])>(([], []))

    /// When set, every call sleeps this long first (simulates a slow network).
    let delay = Mutex<Duration?>(nil)

    init(_ script: [Result<ExtractorOutput, ExtractionError>] = []) { state.withLock { $0.script = script } }

    var requests: [ExtractionRequest] { state.withLock { $0.requests } }

    func push(_ result: Result<ExtractorOutput, ExtractionError>) { state.withLock { $0.script.append(result) } }

    func extract(_ request: ExtractionRequest) async throws(ExtractionError) -> ExtractionResponse {
        if let d = delay.withLock({ $0 }) { try? await Task.sleep(for: d) }
        let next: Result<ExtractorOutput, ExtractionError> = state.withLock { s in
            s.requests.append(request)
            return s.script.isEmpty ? .success(ExtractorOutput(memories: [], mentions: [], flags: .none)) : s.script.removeFirst()
        }
        switch next {
        case .success(let output):
            return ExtractionResponse(output: output, version: version, model: "fake",
                                      usage: Usage(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0))
        case .failure(let error):
            throw error
        }
    }
}
