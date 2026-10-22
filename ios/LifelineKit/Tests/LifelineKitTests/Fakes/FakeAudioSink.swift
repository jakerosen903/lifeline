import AVFoundation
import Synchronization
@testable import LifelineKit

final class FakeAudioSink: AudioSink, Sendable {
    private let state = Mutex<(written: [MsRange], opened: URL?, closed: Bool)>(([], nil, false))

    var written: [MsRange] { state.withLock { $0.written } }
    var opened: URL? { state.withLock { $0.opened } }
    var closed: Bool { state.withLock { $0.closed } }

    func open(url: URL, format: AVAudioFormat) async throws { state.withLock { $0.opened = url } }
    func write(_ chunk: AudioChunk) async throws {
        state.withLock { $0.written.append(MsRange(start: chunk.startMs, end: chunk.startMs + chunk.durationMs)) }
    }
    func close() async throws { state.withLock { $0.closed = true } }
}
