import AVFoundation
import Foundation
import Testing
@testable import LifelineKit

@Test func clampKeepsRangeInsideFile() {
    #expect(SegmentPlayer.clamp(MsRange(start: 1_000, end: 99_000), toDurationMs: 5_000) == MsRange(start: 1_000, end: 5_000))
    #expect(SegmentPlayer.clamp(MsRange(start: 9_000, end: 9_500), toDurationMs: 5_000) == MsRange(start: 5_000, end: 5_000))
    #expect(SegmentPlayer.clamp(MsRange(start: -5, end: 100), toDurationMs: 5_000) == MsRange(start: 0, end: 100))
}

private func writeSine(seconds: Int) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
    let w = AudioFileWriter()
    try await w.open(url: url, format: CaptureFormat.format)
    for i in 0..<(seconds * 10) {
        let b = AudioFixtures.sine(durationMs: 100)
        try await w.write(AudioChunk(buffer: b, startMs: i * 100, durationMs: 100, levelDb: rmsDb(b)))
    }
    try await w.close()
    return url
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LIFELINE_SKIP_AUDIO_TESTS"] == nil))
@MainActor func playStartsAtRangeStartAndStopsAtRangeEnd() async throws {
    let url = try await writeSine(seconds: 3)
    let player = SegmentPlayer()
    try player.play(url: url, range: MsRange(start: 1_000, end: 2_000))
    #expect(player.isPlaying)
    #expect(player.positionMs >= 1_000)
    try await Task.sleep(for: .milliseconds(1_400))
    #expect(!player.isPlaying)
    #expect(player.playingRange == nil)
}

@Test @MainActor func stopClearsState() async throws {
    let url = try await writeSine(seconds: 1)
    let player = SegmentPlayer()
    try player.play(url: url, range: MsRange(start: 0, end: 1_000))
    player.stop()
    #expect(!player.isPlaying && player.playingRange == nil)
}

@Test @MainActor func playingAMissingFileThrows() {
    let player = SegmentPlayer()
    #expect(throws: (any Error).self) {
        try player.play(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).m4a"), range: MsRange(start: 0, end: 10))
    }
    #expect(!player.isPlaying)
}
