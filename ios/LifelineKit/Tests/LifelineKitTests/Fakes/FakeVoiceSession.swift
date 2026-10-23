import Foundation
@testable import LifelineKit

actor FakeVoiceSession: VoiceSession {
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var audioURL: URL?
    private var continuation: AsyncStream<VoiceEvent>.Continuation?
    var shouldFailOnStart = false

    func start(writingTo audioURL: URL) async throws -> AsyncStream<VoiceEvent> {
        if shouldFailOnStart { throw NSError(domain: "FakeVoiceSession", code: 1) }
        startCalled = true
        self.audioURL = audioURL
        let (stream, c) = AsyncStream<VoiceEvent>.makeStream()
        continuation = c
        return stream
    }

    func stop() async throws { stopCalled = true; continuation?.finish() }
    private(set) var pauseCalls = 0
    private(set) var resumeCalls = 0
    func pause() async throws { pauseCalls += 1; continuation?.yield(.paused) }
    func resume() async throws { resumeCalls += 1; continuation?.yield(.resumed) }
    func say(_ text: String) async {}
    func acknowledge() async {}
    func interrupt() async {}

    func emit(_ event: VoiceEvent) { continuation?.yield(event) }
    func setFailOnStart() { shouldFailOnStart = true }
}
