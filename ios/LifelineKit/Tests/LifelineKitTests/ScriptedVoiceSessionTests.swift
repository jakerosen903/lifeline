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

@Test func scriptedSessionPlaysATurnForItsWords() async throws {
    let session = ScriptedVoiceSession(intervalMs: 60_000)   // the script stays quiet during the test
    let url = FileManager.default.temporaryDirectory.appending(path: "scripted-\(UUID().uuidString).m4a")
    let events = try await session.start(writingTo: url)
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "What would you like to tell me?")   // 7 words: 1,050 ms
    let started = ContinuousClock.now
    #expect(await session.say(turn))
    var all: [VoiceEvent] = []
    for await event in events {
        all.append(event)
        if case .turnEnded = event { break }
    }
    let elapsed = ContinuousClock.now - started
    #expect(all == [.turnStarted(turn.id, atMs: 0), .turnEnded(turn.id, atMs: 1_050, interrupted: false)])
    #expect(elapsed >= .milliseconds(1_050), "the turn plays for 150 ms a word; it ended after \(elapsed)")
    try await session.stop()
}

@Test func aScriptedSegmentCutsTheTurnItStartsIn() async throws {
    let session = ScriptedVoiceSession(intervalMs: 300)
    let url = FileManager.default.temporaryDirectory.appending(path: "scripted-\(UUID().uuidString).m4a")
    let events = try await session.start(writingTo: url)
    let turn = SpokenTurn(id: InterviewerTurnID(), text: "Take your time with this one, there is no hurry at all")   // 1.65 s
    #expect(await session.say(turn))
    var all: [VoiceEvent] = []
    for await event in events {
        all.append(event)
        if case .speechStarted = event { break }
    }
    try await session.stop()
    guard all.count == 3, case .turnEnded(let id, let endMs, let interrupted) = all[1] else {
        Issue.record("expected start, cut, speech; saw \(all)")
        return
    }
    #expect(all[0] == .turnStarted(turn.id, atMs: 0))
    #expect(id == turn.id && interrupted, "the segment ends the turn, interrupted, before it starts")
    #expect(endMs < 1_650, "the turn ends where it was cut")
    #expect(all[2] == .speechStarted(atMs: 0))
}

@Test func aTurnStillPlayingIsCutByTheNextOneAndByPause() async throws {
    let session = ScriptedVoiceSession(intervalMs: 60_000)
    let url = FileManager.default.temporaryDirectory.appending(path: "scripted-\(UUID().uuidString).m4a")
    let events = try await session.start(writingTo: url)
    let first = SpokenTurn(id: InterviewerTurnID(), text: "One two three four five six seven eight")
    let second = SpokenTurn(id: InterviewerTurnID(), text: "Nine ten eleven twelve")
    #expect(await session.say(first))
    #expect(await session.say(second))
    try await session.pause()
    #expect(await session.say(first) == false, "a paused session refuses a turn")
    try await session.stop()
    var all: [VoiceEvent] = []
    for await event in events { all.append(event) }
    let ends = all.compactMap { event -> (InterviewerTurnID, Bool)? in
        if case .turnEnded(let id, _, let interrupted) = event { (id, interrupted) } else { nil }
    }
    #expect(ends.map(\.0) == [first.id, second.id], "each turn ends once; saw \(all)")
    #expect(ends.allSatisfy { $0.1 }, "both were cut")
    #expect(all.last == .paused)
}
