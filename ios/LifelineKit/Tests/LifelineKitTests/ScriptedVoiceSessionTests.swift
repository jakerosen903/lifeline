import AVFoundation
import Foundation
import Testing
@testable import LifelineKit

@Test func scriptedSessionEmitsItsScriptAndWritesAudio() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
    let script = [
        SegmentTranscript(range: MsRange(start: 0, end: 1_000), text: "one", words: [w("one", 0, 900)]),
        SegmentTranscript(range: MsRange(start: 1_500, end: 2_500), text: "two", words: [w("two", 1_500, 2_400)]),
    ]
    let vs = ScriptedVoiceSession(script: script, intervalMs: 10)
    let events = try await vs.start(writingTo: url)
    var closed: [SegmentTranscript] = []
    for await e in events {
        if case .segmentClosed(let s) = e { closed.append(s) }
        if closed.count == 2 { break }
    }
    #expect(closed == script)
    try await vs.stop()
    let f = try AVAudioFile(forReading: url)
    #expect(Double(f.length) / f.fileFormat.sampleRate >= 2.4)
}

@Test func pauseLogAppendsLines() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).log")
    let log = PauseLog(url: url)
    await log.record("pause 1200")
    await log.record("say hello")        // not a pause line; ignored
    await log.record("pause 300")
    let text = try String(contentsOf: url, encoding: .utf8)
    let lines = text.split(separator: "\n")
    let values: [String] = lines.map { line in String(line.split(separator: "\t").last ?? "") }
    #expect(values == ["1200", "300"])
}
