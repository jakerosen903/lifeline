import Foundation
import Synchronization
import Testing
@testable import LifelineKit

@Test func scriptedSessionPausesAndResumes() async throws {
    let session = ScriptedVoiceSession(intervalMs: 60)
    let url = FileManager.default.temporaryDirectory.appending(path: "scripted-\(UUID().uuidString).m4a")
    let events = try await session.start(writingTo: url)
    try await session.pause()
    let seen = Mutex<[VoiceEvent]>([])
    let collector = Task {
        for await event in events {
            seen.withLock { $0.append(event) }
            if case .segmentClosed = event { break }
        }
    }
    try await Task.sleep(for: .milliseconds(400))
    let whilePaused = seen.withLock { $0 }
    #expect(!whilePaused.contains { if case .segmentClosed = $0 { true } else { false } }, "nothing arrives while paused; saw \(whilePaused)")
    try await session.resume()
    _ = await collector.value
    let all = seen.withLock { $0 }
    #expect(all.contains { if case .paused = $0 { true } else { false } })
    #expect(all.contains { if case .resumed = $0 { true } else { false } })
    #expect(all.contains { if case .segmentClosed = $0 { true } else { false } }, "the script goes on after resume")
    try await session.stop()
}

@Test func scriptedSessionReportsTurns() async throws {
    let session = ScriptedVoiceSession(intervalMs: 60_000)   // the script stays quiet during the test
    let url = FileManager.default.temporaryDirectory.appending(path: "scripted-\(UUID().uuidString).m4a")
    let events = try await session.start(writingTo: url)
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "What would you like to tell me about today?")
    await session.say(turn)
    try await session.stop()
    var all: [VoiceEvent] = []
    for await event in events { all.append(event) }
    #expect(all == [.turnStarted(turn.id, atMs: 0), .turnEnded(turn.id, atMs: 0, interrupted: false)])
}
