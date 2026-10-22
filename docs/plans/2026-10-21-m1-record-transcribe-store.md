# M1: Record, Transcribe, Store, Play Back — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An iPhone app that records a 30-minute screen-off session, transcribes it on the device with word timestamps, stores sessions, segments and words in SQLite next to an m4a file, lists past sessions, and plays any segment's own audio.

**Architecture:** One Swift package, `LifelineKit`, holds every piece of logic and compiles for iOS and macOS. A `ListenOnlyVoiceSession` actor owns one clock (the audio file's sample position), feeds one `AVAudioEngine` tap to both an m4a writer and the iOS 26 `SpeechTranscriber`, and closes segments with an energy-gate `Segmenter`. A `SessionRecorder` turns voice events into database rows. The app target holds only SwiftUI views, `@Observable` view models and a composition root. A `lifeline` macOS executable proves the package builds and opens the same database off the phone.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Swift Testing, GRDB.swift 7.11.1, AVFoundation, Speech (`SpeechAnalyzer` / `SpeechTranscriber`, iOS 26), xcodegen for the Xcode project.

**Spec:** `docs/specs/2026-10-21-v1-listening-app-design.md` (sections 3, 4, 5, 6, 9 crash rule, 10, 11 row M1). Read it first. This plan covers milestone M1 only. M2 to M5 get their own plans once M1's code exists.

## Global Constraints

- Minimum iOS 26. `LifelineKit` must compile for iOS 26 and macOS 26. Platform code (speech, audio capture) sits behind protocols with `#if os(iOS)` implementations.
- Swift 6 language mode, strict concurrency complete, in the package and the app.
- The app target must contain only views, view models and the composition root. All logic lives in `LifelineKit`.
- Audio file: m4a, AAC, 24 kHz, mono, at `Application Support/Lifeline/audio/<sessionID>.m4a`, excluded from iCloud backup.
- Segmenter defaults: `pauseThreshold` 1.8 s, `minSegmentSpeech` 3 s. Configuration, not literals in logic.
- All IDs are UUID strings. All times ISO-8601 UTC. All audio offsets are integer milliseconds from the start of the session file.
- `UIBackgroundModes: audio`; `AVAudioSession` category `.record`, mode `.spokenAudio`.
- Nothing in the store may contain text the owner did not say or type.
- Fixtures and sample content are invented. `*.m4a` is gitignored; tests generate audio in a temp directory.
- Docs under `docs/` use ASD-STE100 style. Commit messages: imperative, one line, body only when the why is not obvious. Never push.
- The design canvases for the three M1 screens are `docs/design/Onboard1.dc.html`, `Main.dc.html`, `Timeline.dc.html`. Palette and type come from there; M1 copies the layout loosely, not pixel for pixel.

## Review Focus

Each line names an input the spec implies but no acceptance criterion exercises, and the task whose tests pin it.

1. **A phone call or Siri interrupts the session.** Recording must pause, the open segment must close, and recording must resume on the same clock so file time stays continuous. Task 6 (`AudioFileWriterTests.appendAfterGapKeepsFileTimeContinuous`) and Task 4 (`interruptionClosesOpenSegment`).
2. **Final transcript results arrive after the segment closed, or a result spans the boundary.** Words must land in the segment whose range contains their start time; none may be lost or duplicated. Task 4 (`lateFinalWordsGoToTheSegmentTheyStartIn`).
3. **Silence only, or speech shorter than `minSegmentSpeech`.** No empty segment rows. Task 3 (`silenceOnlyProducesNoSegment`, `shortBlipDoesNotCloseASegment`).
4. **The app is killed mid-session.** The session row and audio written so far must survive, and the next launch must close the session rather than leave it open forever. M4 turns this into resume-to-wind-down; M1 closes it. Task 5 (`recoverUnfinishedSessionsSetsEndedAt`).
5. **The on-device speech model for the locale is not installed.** The first session must request the download and wait, not fail silently. Task 7 (`TranscriberAvailabilityTests`) plus the device checklist in Task 9.

---

## File Structure

```
ios/
  project.yml                          xcodegen source of truth for Lifeline.xcodeproj (generated, gitignored)
  Config/Local.xcconfig                gitignored: DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER prefix (M2 adds the API key)
  Config/Local.example.xcconfig        committed template
  Lifeline/                            app target
    LifelineApp.swift                  @main, builds Dependencies, routes first-open vs home
    Dependencies.swift                 composition root: database, voice session factory, recorder, player
    Screens/AboutYou/AboutYouScreen.swift, AboutYouViewModel.swift
    Screens/Home/HomeScreen.swift, HomeViewModel.swift            session list + Start
    Screens/Session/SessionScreen.swift, SessionViewModel.swift   live transcript, elapsed, Stop
    Screens/SessionDetail/SessionDetailScreen.swift, SessionDetailViewModel.swift   segments, tap to play
    Screens/Settings/SettingsScreen.swift                          reuses AboutYouScreen in edit mode
  LifelineKit/
    Package.swift
    Sources/LifelineKit/
      Domain/Identifiers.swift         SessionID, SegmentID, PersonID (typed UUID strings)
      Domain/Session.swift             Session, Segment, Word, SegmentStatus
      Domain/Profile.swift             Profile, Person
      Domain/Clock.swift               Milliseconds = Int; MsRange
      Store/AppDatabase.swift          open/create, migrator, in-memory for tests
      Store/Migrations.swift           v1 schema
      Store/SessionRepository.swift    insert/list/fetch sessions, segments, words
      Store/ProfileRepository.swift    upsert profile, mirror owner person
      Store/AudioLocation.swift        audio directory URL, backup exclusion
      Voice/VoiceSession.swift         VoiceSession protocol, VoiceEvent, SegmentTranscript, TranscribedWord
      Voice/AudioSource.swift          AudioSource protocol, AudioChunk
      Voice/Transcriber.swift          Transcriber protocol, TranscriptResult
      Voice/Segmenter.swift            pure energy-gate state machine + SegmenterConfig
      Voice/ListenOnlyVoiceSession.swift   actor composing source + writer + transcriber + segmenter
      Voice/AudioFileWriter.swift      AVAudioFile m4a writer (iOS and macOS)
      Voice/WordRuns.swift             pure: AttributedString runs -> [TranscribedWord]
      Voice/TranscriberAvailability.swift  pure decision over AssetInventory status
      Voice/iOS/AVAudioEngineSource.swift      #if os(iOS)
      Voice/iOS/AudioSessionConfigurator.swift #if os(iOS)
      Voice/iOS/SpeechAnalyzerTranscriber.swift  #if os(iOS)
      Playback/SegmentPlayer.swift     AVAudioPlayer range playback
      Session/SessionRecorder.swift    voice events -> rows; start/stop/recover
      Session/TranscriptImport.swift   transcript.json -> session rows (CLI and fixtures)
    Sources/lifeline/main.swift        CLI: `sessions`, `import`
    Tests/LifelineKitTests/            one file per source file under test
    Tests/Fixtures/transcript-garden.json   invented transcript
```

---

### Task 1: Package and project scaffold

**Files:**
- Create: `ios/LifelineKit/Package.swift`, `ios/LifelineKit/Sources/LifelineKit/LifelineKit.swift`, `ios/LifelineKit/Sources/lifeline/main.swift`, `ios/LifelineKit/Tests/LifelineKitTests/SmokeTests.swift`
- Create: `ios/project.yml`, `ios/Config/Local.example.xcconfig`, `ios/Lifeline/LifelineApp.swift`
- Modify: `.gitignore` (add `ios/Lifeline.xcodeproj/`, `ios/Config/Local.xcconfig`, `.build/`, `.swiftpm/`)
- Modify: `CLAUDE.md` Layout section: `ios/` now exists; note `xcodegen generate` regenerates the project

**Interfaces:**
- Produces: package `LifelineKit` with library product `LifelineKit` and executable product `lifeline`; test target `LifelineKitTests`; app target `Lifeline` depending on the library.

- [ ] **Step 1: Write the smoke test**

```swift
import Testing
@testable import LifelineKit

@Test func packageVersionIsSet() {
    #expect(LifelineKit.version == "0.1.0")
}
```

- [ ] **Step 2: Write `Package.swift`**

Swift tools 6.1. Platforms `.iOS(.v26)`, `.macOS(.v26)`. Dependency `https://github.com/groue/GRDB.swift.git` exact `7.11.1`. Targets: `LifelineKit` (depends on product `GRDB`), `lifeline` executable (depends on `LifelineKit`), `LifelineKitTests` with `resources: [.copy("../Fixtures")]`. Every target: `swiftSettings: [.swiftLanguageMode(.v6)]`. `LifelineKit.swift` holds `public enum LifelineKit { public static let version = "0.1.0" }`. `main.swift` prints usage and exits 2.

- [ ] **Step 3: Run the test**

Run: `cd ios/LifelineKit && swift test`
Expected: 1 test passed. (First run resolves GRDB; allow a few minutes.)

- [ ] **Step 4: Install xcodegen and write `project.yml`**

Run: `brew install xcodegen`. Then `project.yml`: name `Lifeline`; `options.deploymentTarget.iOS: "26.0"`; `packages.LifelineKit.path: LifelineKit`; target `Lifeline` type `application`, platform iOS, sources `Lifeline`, dependency on package product `LifelineKit`; `configFiles` Debug and Release both `Config/Local.xcconfig`; settings `SWIFT_VERSION: 6.0`, `SWIFT_STRICT_CONCURRENCY: complete`, `PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).lifeline`, `CODE_SIGN_STYLE: Automatic`; `info.path: Lifeline/Info.plist` with properties `UIBackgroundModes: [audio]`, `NSMicrophoneUsageDescription: "Lifeline records your sessions so you can hear them again."`, `NSSpeechRecognitionUsageDescription: "Lifeline transcribes your sessions on this device."`, `UILaunchScreen: {}`. `Local.example.xcconfig` holds `DEVELOPMENT_TEAM = ` and `BUNDLE_ID_PREFIX = com.example`. `LifelineApp.swift` is a `@main App` showing `Text("Lifeline")`.

- [ ] **Step 5: Generate and build for the simulator**

Run: `cp ios/Config/Local.example.xcconfig ios/Config/Local.xcconfig && cd ios && xcodegen generate && xcodebuild -project Lifeline.xcodeproj -scheme Lifeline -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.3' build | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add .gitignore CLAUDE.md ios
git commit -m "Scaffold LifelineKit package and Lifeline app project"
```

---

### Task 2: Domain types, schema v1 and repositories

**Files:**
- Create: `Domain/Identifiers.swift`, `Domain/Clock.swift`, `Domain/Session.swift`, `Domain/Profile.swift`, `Store/AppDatabase.swift`, `Store/Migrations.swift`, `Store/SessionRepository.swift`, `Store/ProfileRepository.swift`, `Store/AudioLocation.swift`
- Test: `Tests/LifelineKitTests/MigrationsTests.swift`, `SessionRepositoryTests.swift`, `ProfileRepositoryTests.swift`

**Interfaces:**
- Produces:
  - `typealias Milliseconds = Int`; `struct MsRange: Equatable, Sendable { var start: Milliseconds; var end: Milliseconds; func contains(_ ms: Milliseconds) -> Bool }` (start inclusive, end exclusive).
  - `struct SessionID: Hashable, Codable, Sendable { let rawValue: String; init() /* UUID */ }`; same shape for `SegmentID`, `PersonID`.
  - `struct Session: Codable, Sendable, Equatable { var id: SessionID; var startedAt: Date; var endedAt: Date?; var audioPath: String; var stageLog: String /* JSON, "[]" in M1 */; var landingChoiceMade: Bool }`
  - `enum SegmentStatus: String, Codable, Sendable { case pending, extracted, failed }`
  - `struct Segment: Codable, Sendable, Equatable { var id: SegmentID; var sessionID: SessionID; var index: Int; var startMs: Milliseconds; var endMs: Milliseconds; var text: String; var status: SegmentStatus }`
  - `struct Word: Codable, Sendable, Equatable { var segmentID: SegmentID; var index: Int; var text: String; var startMs: Milliseconds; var endMs: Milliseconds }`
  - `struct Profile: Codable, Sendable, Equatable { var displayName: String?; var birthDate: Date?; var birthPlaceText: String?; var freeText: String?; var updatedAt: Date }`
  - `enum BirthDateOrigin: String, Codable, Sendable { case stated, typed }`
  - `struct Person: Codable, Sendable, Equatable { var id: PersonID; var displayName: String; var notes: String?; var isOwner: Bool; var birthDate: Date?; var birthDateOrigin: BirthDateOrigin? }`
  - `final class AppDatabase: Sendable { static func open(at url: URL) throws -> AppDatabase; static func inMemory() throws -> AppDatabase; let writer: any DatabaseWriter }`
  - `struct SessionRepository: Sendable { init(_ db: AppDatabase); func insert(_ s: Session) throws; func update(_ s: Session) throws; func fetch(_ id: SessionID) throws -> Session?; func listSessions() throws -> [Session] /* newest first */; func unfinishedSessions() throws -> [Session]; func insert(_ seg: Segment, words: [Word]) throws; func segments(in: SessionID) throws -> [Segment]; func words(in: SegmentID) throws -> [Word] }`
  - `struct ProfileRepository: Sendable { init(_ db: AppDatabase); func fetch() throws -> Profile?; func save(_ p: Profile) throws /* also upserts the owner Person */; func owner() throws -> Person? }`
  - `enum AudioLocation { static func directory(fileManager: FileManager = .default) throws -> URL /* creates Application Support/Lifeline/audio, sets isExcludedFromBackup */; static func url(for: SessionID) throws -> URL }`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func v1CreatesAllTables() throws {
    let db = try AppDatabase.inMemory()
    let names = try db.writer.read { try String.fetchAll($0, sql: "select name from sqlite_master where type='table' order by name") }
    #expect(Set(names).isSuperset(of: ["session","segment","word","profile","person"]))
}

@Test func sessionSegmentWordRoundTrip() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let s = Session(id: .init(), startedAt: .init(timeIntervalSince1970: 1_000), endedAt: nil, audioPath: "a.m4a", stageLog: "[]", landingChoiceMade: false)
    try repo.insert(s)
    let seg = Segment(id: .init(), sessionID: s.id, index: 0, startMs: 0, endMs: 4_200, text: "the house had a blue door", status: .pending)
    let words = ["the","house","had","a","blue","door"].enumerated().map { Word(segmentID: seg.id, index: $0, text: $1, startMs: $0*700, endMs: $0*700+600) }
    try repo.insert(seg, words: words)
    #expect(try repo.segments(in: s.id) == [seg])
    #expect(try repo.words(in: seg.id) == words)
    #expect(try repo.unfinishedSessions().map(\.id) == [s.id])
}

@Test func listSessionsIsNewestFirst() throws { /* insert two with startedAt 1_000 and 2_000; expect ids [second, first] */ }

@Test func savingProfileMirrorsOwnerPerson() throws {
    let db = try AppDatabase.inMemory(); let repo = ProfileRepository(db)
    try repo.save(Profile(displayName: "Rina", birthDate: .init(timeIntervalSince1970: 0), birthPlaceText: "Oslo", freeText: nil, updatedAt: .now))
    let owner = try #require(try repo.owner())
    #expect(owner.isOwner && owner.displayName == "Rina" && owner.birthDateOrigin == .typed)
    try repo.save(Profile(displayName: "Rina B", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    #expect(try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from person where is_owner = 1") } == 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MigrationsTests` (and the other two)
Expected: compile failure, types not found.

- [ ] **Step 3: Implement the domain types and `Migrations.v1`**

Column names are snake_case per the spec table (`session.started_at`, `segment.session_id`, …). Record types adopt `FetchableRecord, PersistableRecord` with `databaseTableName` and `CodingKeys` mapping camelCase to snake_case (or set `databaseColumnDecodingStrategy = .convertFromSnakeCase` on each record). `word` primary key is `(segment_id, index)`. `profile` has a single row with `id = 1`. `person` has an index on `is_owner`. Foreign keys on, cascade delete from session to segment to word. `AppDatabase.open` uses `DatabasePool`; `inMemory` uses `DatabaseQueue`.

- [ ] **Step 4: Implement the repositories and `AudioLocation`**

`ProfileRepository.save` runs in one write transaction: upsert profile row, then upsert the person where `is_owner = 1` (insert if none) with `birthDateOrigin = .typed` when `birthDate` is non-nil.

- [ ] **Step 5: Run the tests**

Run: `swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add domain types, schema v1 and repositories"
```

---

### Task 3: Segmenter (pure energy gate)

**Files:**
- Create: `Voice/Segmenter.swift`
- Test: `Tests/LifelineKitTests/SegmenterTests.swift`

**Interfaces:**
- Produces:
  - `struct SegmenterConfig: Sendable { var pauseThresholdMs: Milliseconds = 1_800; var minSegmentSpeechMs: Milliseconds = 3_000; var speechThresholdDb: Float = -40; var maxSegmentMs: Milliseconds = 90_000 }`
  - `enum SegmenterEvent: Equatable, Sendable { case speechStarted(atMs: Milliseconds); case segmentEnded(MsRange); case pauseObserved(ms: Milliseconds) }`
  - `struct Segmenter: Sendable { init(config: SegmenterConfig = .init()); mutating func observe(levelDb: Float, startMs: Milliseconds, durationMs: Milliseconds) -> [SegmenterEvent]; mutating func flush(atMs: Milliseconds) -> [SegmenterEvent] }`

Rules the tests pin: a segment opens at the first chunk above threshold; it ends when silence has lasted `pauseThresholdMs` and accumulated speech in the segment is at least `minSegmentSpeechMs`; if speech is shorter, the segment is abandoned (no event); the end of a segment is the last speech chunk's end, not the end of the pause; `pauseObserved` is emitted with the pause length every time a pause ends, for calibration logging; `maxSegmentMs` force-closes a long segment at the next chunk boundary; `flush` closes an open segment that has enough speech.

- [ ] **Step 1: Write the failing tests**

```swift
func feed(_ s: inout Segmenter, db: Float, from: Int, count: Int, step: Int = 100) -> [SegmenterEvent] {
    var out: [SegmenterEvent] = []
    for i in 0..<count { out += s.observe(levelDb: db, startMs: from + i*step, durationMs: step) }
    return out
}

@Test func speechThenLongPauseClosesSegment() {
    var s = Segmenter()
    var ev = feed(&s, db: -20, from: 0, count: 40)          // 4 s speech
    ev += feed(&s, db: -60, from: 4_000, count: 20)         // 2 s silence
    #expect(ev.contains(.speechStarted(atMs: 0)))
    #expect(ev.contains(.segmentEnded(MsRange(start: 0, end: 4_000))))
}

@Test func silenceOnlyProducesNoSegment() { var s = Segmenter(); #expect(feed(&s, db: -70, from: 0, count: 600).isEmpty) }

@Test func shortBlipDoesNotCloseASegment() {
    var s = Segmenter()
    var ev = feed(&s, db: -20, from: 0, count: 10)          // 1 s speech
    ev += feed(&s, db: -60, from: 1_000, count: 30)
    #expect(!ev.contains { if case .segmentEnded = $0 { true } else { false } })
}

@Test func pauseInsideSpeechDoesNotSplit() {
    var s = Segmenter()
    var ev = feed(&s, db: -20, from: 0, count: 30)
    ev += feed(&s, db: -60, from: 3_000, count: 10)         // 1 s pause, under threshold
    ev += feed(&s, db: -20, from: 4_000, count: 20)
    ev += feed(&s, db: -60, from: 6_000, count: 20)
    #expect(ev.filter { if case .segmentEnded = $0 { true } else { false } } == [.segmentEnded(MsRange(start: 0, end: 6_000))])
    #expect(ev.contains(.pauseObserved(ms: 1_000)))
}

@Test func flushClosesOpenSegment() { var s = Segmenter(); _ = feed(&s, db: -20, from: 0, count: 50); #expect(s.flush(atMs: 5_000) == [.segmentEnded(MsRange(start: 0, end: 5_000))]) }

@Test func maxSegmentForcesClose() { var s = Segmenter(config: .init(maxSegmentMs: 10_000)); let ev = feed(&s, db: -20, from: 0, count: 120); #expect(ev.contains(.segmentEnded(MsRange(start: 0, end: 10_000)))) }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SegmenterTests`
Expected: compile failure.

- [ ] **Step 3: Implement `Segmenter`**

State: `idle`, `inSpeech(segmentStart, speechMs, lastSpeechEnd)`, `inPause(segmentStart, speechMs, lastSpeechEnd, pauseStart)`. Pure; no clocks, no logging. The caller logs `pauseObserved`.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SegmenterTests`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add energy-gate Segmenter"
```

---

### Task 4: Voice protocols and `ListenOnlyVoiceSession`

**Files:**
- Create: `Voice/VoiceSession.swift`, `Voice/AudioSource.swift`, `Voice/Transcriber.swift`, `Voice/ListenOnlyVoiceSession.swift`
- Test: `Tests/LifelineKitTests/ListenOnlyVoiceSessionTests.swift`, `Tests/LifelineKitTests/Fakes/FakeAudioSource.swift`, `Fakes/FakeTranscriber.swift`, `Fakes/FakeAudioSink.swift`

**Interfaces:**
- Produces:
  - `struct TranscribedWord: Equatable, Sendable, Codable { var text: String; var range: MsRange }`
  - `struct TranscriptResult: Equatable, Sendable { var text: String; var words: [TranscribedWord]; var range: MsRange; var isFinal: Bool }`
  - `struct SegmentTranscript: Equatable, Sendable { var range: MsRange; var text: String; var words: [TranscribedWord] }`
  - `enum VoiceEvent: Equatable, Sendable { case speechStarted(atMs: Milliseconds); case transcriptPartial(String); case transcriptFinal(TranscriptResult); case userPaused(afterMs: Milliseconds); case segmentClosed(SegmentTranscript); case interrupted; case resumed; case failed(String) }`
  - `protocol VoiceSession: Actor { func start(writingTo audioURL: URL) async throws -> AsyncStream<VoiceEvent>; func stop() async throws; func say(_ text: String) async; func acknowledge() async; func interrupt() async }`
  - `struct AudioChunk: @unchecked Sendable { let buffer: AVAudioPCMBuffer; let startMs: Milliseconds; let durationMs: Milliseconds; let levelDb: Float }` (unchecked because `AVAudioPCMBuffer` is handed off and never shared; comment says so)
  - `protocol AudioSource: Sendable { var format: AVAudioFormat { get } ; func start() async throws -> AsyncStream<AudioSourceEvent>; func stop() async }`; `enum AudioSourceEvent: Sendable { case chunk(AudioChunk); case interrupted; case resumed }`
  - `protocol AudioSink: Sendable { func open(url: URL, format: AVAudioFormat) async throws; func write(_ chunk: AudioChunk) async throws; func close() async throws }`
  - `protocol Transcriber: Sendable { func start(format: AVAudioFormat) async throws -> AsyncStream<TranscriptResult>; func feed(_ chunk: AudioChunk) async; func finalize(throughMs: Milliseconds) async; func finish() async }`
  - `actor ListenOnlyVoiceSession: VoiceSession { init(source: any AudioSource, sink: any AudioSink, transcriber: any Transcriber, segmenter: SegmenterConfig = .init(), log: @Sendable (String) -> Void = { _ in }) }`

Behaviour the tests pin: every chunk goes to the sink, the transcriber and the segmenter, in that order; `segmentEnded` from the segmenter triggers `transcriber.finalize(throughMs:)` and then one `segmentClosed` carrying every final word whose `range.start` lies inside the segment range, in time order; final words outside any closed segment are held for the next segment; `userPaused` is emitted on each `segmentEnded`; `interrupted` from the source flushes the segmenter at the last chunk end and forwards `.interrupted`; `stop()` flushes, finishes the transcriber, closes the sink and ends the stream; every `pauseObserved(ms)` from the segmenter calls `log("pause \(ms)")` and emits nothing; `say`, `acknowledge`, `interrupt` only call `log`.

- [ ] **Step 1: Write the fakes**

`FakeAudioSource`: `format` 24 kHz mono Float32; `start()` returns a stream whose continuation is exposed as `events` so a test can push chunks and `.interrupted`. A helper `chunk(startMs:durationMs:levelDb:)` builds an `AudioChunk` with an empty buffer of the right frame count. `FakeTranscriber`: records `fed` ranges and `finalizedThrough` values; exposes a continuation so tests push `TranscriptResult`s. `FakeAudioSink`: records `written` ranges and `closed`.

- [ ] **Step 2: Write the failing tests**

```swift
@Test func segmentClosedCarriesWordsInsideRange() async throws {
    let src = FakeAudioSource(), tr = FakeTranscriber(), sink = FakeAudioSink()
    let vs = ListenOnlyVoiceSession(source: src, sink: sink, transcriber: tr)
    let events = try await vs.start(writingTo: URL(fileURLWithPath: "/dev/null"))
    var it = events.makeAsyncIterator()
    src.push(speechMs: 0..<4_000, silenceMs: 4_000..<6_000)              // helper feeding 100 ms chunks
    tr.push(TranscriptResult(text: "the blue door", words: [w("the",0,300), w("blue",300,700), w("door",700,1_100)], range: .init(start:0,end:1_100), isFinal: true))
    tr.push(TranscriptResult(text: "later", words: [w("later",4_500,4_900)], range: .init(start:4_500,end:4_900), isFinal: true))
    let closed = try await #require(await it.first { if case .segmentClosed = $0 { true } else { false } })
    guard case .segmentClosed(let seg) = closed else { return }
    #expect(seg.range == MsRange(start: 0, end: 4_000))
    #expect(seg.words.map(\.text) == ["the","blue","door"])
    #expect(seg.text == "the blue door")
    #expect(tr.finalizedThrough == [4_000])
}

@Test func lateFinalWordsGoToTheSegmentTheyStartIn() async throws { /* push the final for 0..<4_000 only AFTER the segmenter closed the segment; expect segmentClosed waits for finalize and still carries the words; a word at 3_900..<4_200 belongs to this segment, a word at 4_100 does not */ }

@Test func interruptionClosesOpenSegment() async throws { /* 5 s speech, then src.pushInterrupted(); expect .segmentClosed(range 0..<5_000) then .interrupted */ }

@Test func everyChunkReachesSinkAndTranscriber() async throws { /* push 10 chunks; expect sink.written.count == 10 and tr.fed.count == 10 */ }

@Test func speakingCommandsAreNoOpsThatLog() async { /* log collector; call say/acknowledge/interrupt; expect 3 log lines, no events */ }
```

Waiting for the delayed final in `lateFinalWordsGoToTheSegmentTheyStartIn`: after `finalize(throughMs:)` the actor waits until it has received a final result whose `range.end >= segment.end` or a result with `isFinal` arriving after the finalize call, with a 2 s timeout, then closes. The test pushes the final after a short `Task.sleep`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ListenOnlyVoiceSessionTests`
Expected: compile failure.

- [ ] **Step 4: Implement the protocols and the actor**

The actor keeps: `segmenter`, `pendingFinals: [TranscribedWord]`, `lastChunkEndMs`, the event continuation, and two child tasks (source loop, transcriber results loop) cancelled in `stop()`. Partial results forward as `.transcriptPartial(text)`. Final results append their words to `pendingFinals` and forward `.transcriptFinal`. Closing a segment: partition `pendingFinals` by `segment.range.contains(word.range.start)`; `text` is the words joined by single spaces.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter ListenOnlyVoiceSessionTests`
Expected: 5 passed. Also run `swift build` with `-Xswiftc -strict-concurrency=complete` clean of warnings in this file.

- [ ] **Step 6: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add VoiceSession protocol and ListenOnlyVoiceSession actor"
```

---

### Task 5: `SessionRecorder`

**Files:**
- Create: `Session/SessionRecorder.swift`
- Test: `Tests/LifelineKitTests/SessionRecorderTests.swift`, `Fakes/FakeVoiceSession.swift`

**Interfaces:**
- Consumes: `VoiceSession`, `SessionRepository`, `AudioLocation`.
- Produces:
  - `struct RecorderState: Equatable, Sendable { var sessionID: SessionID?; var elapsedMs: Milliseconds; var partial: String; var segments: [Segment]; var isInterrupted: Bool; var error: String? }`
  - `actor SessionRecorder { init(voice: any VoiceSession, sessions: SessionRepository, audioURL: @Sendable (SessionID) throws -> URL, now: @Sendable () -> Date = Date.init); var states: AsyncStream<RecorderState> { get }; func start() async throws -> SessionID; func stop() async throws; nonisolated static func recoverUnfinishedSessions(_ repo: SessionRepository, now: Date = .now) throws -> Int }`

Behaviour: `start()` inserts the `Session` row (ended_at nil, audio_path = file name) before starting voice; each `.segmentClosed` inserts a `Segment` (index = count so far, status `.pending`) with its words; `.transcriptPartial` updates `partial`; `.interrupted`/`.resumed` toggle `isInterrupted`; `stop()` stops voice, sets `endedAt`, updates the row. `recoverUnfinishedSessions` sets `endedAt = now` on every session with nil `endedAt` and returns the count (M4 replaces this with resume-to-wind-down).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func startInsertsOpenSessionBeforeVoiceStarts() async throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db); let voice = FakeVoiceSession()
    let rec = SessionRecorder(voice: voice, sessions: repo, audioURL: { _ in URL(fileURLWithPath: "/tmp/x.m4a") })
    let id = try await rec.start()
    #expect(try repo.fetch(id)?.endedAt == nil)
    #expect(await voice.startCalled)
}

@Test func segmentClosedBecomesRows() async throws {
    /* start; voice.emit(.segmentClosed(SegmentTranscript(range: 0..<4_000, text: "the blue door", words: [...]))); expect one segment with index 0, text, and 3 words */
}

@Test func stopSetsEndedAt() async throws { /* start; stop; expect endedAt != nil and voice.stopCalled */ }

@Test func recoverUnfinishedSessionsSetsEndedAt() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    try repo.insert(Session(id: .init(), startedAt: .now, endedAt: nil, audioPath: "a.m4a", stageLog: "[]", landingChoiceMade: false))
    #expect(try SessionRecorder.recoverUnfinishedSessions(repo) == 1)
    #expect(try repo.unfinishedSessions().isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionRecorderTests`
Expected: compile failure.

- [ ] **Step 3: Implement `SessionRecorder` and `FakeVoiceSession`**

`FakeVoiceSession` is an actor conforming to `VoiceSession` with `emit(_:)`, `startCalled`, `stopCalled`.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SessionRecorderTests`
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add SessionRecorder"
```

---

### Task 6: Audio capture, conversion and m4a writing

**Files:**
- Create: `Voice/AudioFileWriter.swift`, `Voice/AudioLevel.swift`, `Voice/iOS/AVAudioEngineSource.swift`, `Voice/iOS/AudioSessionConfigurator.swift`
- Test: `Tests/LifelineKitTests/AudioFileWriterTests.swift`

**Interfaces:**
- Consumes: `AudioSink`, `AudioSource`, `AudioChunk`.
- Produces:
  - `enum CaptureFormat { static let format: AVAudioFormat /* 24 kHz, 1 ch, Float32, non-interleaved */ }`
  - `final class AudioFileWriter: AudioSink` writing AAC m4a at `CaptureFormat.format`'s rate; settings `AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000`.
  - `#if os(iOS) final class AVAudioEngineSource: AudioSource { init(bufferMs: Int = 100) }`: installs one tap on the input node, converts each buffer to `CaptureFormat.format` with `AVAudioConverter`, computes `levelDb` as 20·log10(RMS) clamped to −100, assigns `startMs` from a running frame counter at 24 kHz (the file clock), and forwards `.interrupted` / `.resumed` from `AVAudioSession.interruptionNotification` and route-change `oldDeviceUnavailable`. On resume it restarts the engine; the frame counter continues.
  - `#if os(iOS) enum AudioSessionConfigurator { static func activateForRecording() throws /* category .record, mode .spokenAudio, options [.allowBluetoothHFP]; setActive(true) */; static func deactivate() }`
  - `func rmsDb(_ buffer: AVAudioPCMBuffer) -> Float` as a free function in `Voice/AudioLevel.swift`, testable on macOS.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func writesPlayableM4AOfExpectedDuration() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
    let w = AudioFileWriter()
    try await w.open(url: url, format: CaptureFormat.format)
    for i in 0..<30 { try await w.write(sine(startMs: i*100, durationMs: 100, hz: 440)) }   // 3 s
    try await w.close()
    let f = try AVAudioFile(forReading: url)
    let seconds = Double(f.length) / f.fileFormat.sampleRate
    #expect(abs(seconds - 3.0) < 0.1)
    #expect(f.fileFormat.sampleRate == 24_000 && f.fileFormat.channelCount == 1)
}

@Test func appendAfterGapKeepsFileTimeContinuous() async throws {
    /* write 1 s, then a chunk with startMs 5_000 (simulating a 4 s interruption): the writer must NOT pad silence; file length is 2 s; so the clock that matters is the frame counter, which the source keeps continuous. Assert file length == 2 s and that AudioChunk.startMs for the second chunk was 5_000 as given (documenting the contract: file time == cumulative frames written, and the source's counter only counts delivered frames). */
}

@Test func rmsDbOfSilenceIsFloor() { #expect(rmsDb(silence(durationMs: 100)) <= -99) }
@Test func rmsDbOfFullScaleSineIsNearMinus3() { #expect(abs(rmsDb(sine(startMs: 0, durationMs: 100, hz: 440, amplitude: 1).buffer) - (-3.01)) < 0.3) }
```

Test helpers `sine(...)` and `silence(...)` build `AVAudioPCMBuffer`s in `CaptureFormat.format`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AudioFileWriterTests`
Expected: compile failure.

- [ ] **Step 3: Implement `AudioFileWriter`, `rmsDb`, `CaptureFormat`**

`AVAudioFile(forWriting:settings:commonFormat: .pcmFormatFloat32, interleaved: false)`; write buffers as given. The writer's contract: file time equals cumulative frames written. Because the engine source's `startMs` also counts only delivered frames, the two clocks agree through interruptions without padding.

- [ ] **Step 4: Implement `AVAudioEngineSource` and `AudioSessionConfigurator` (iOS only)**

Compile them with the simulator build from Task 1 (`xcodebuild … build`). They cannot be unit-tested on macOS; Task 9's device checklist covers them.

- [ ] **Step 5: Run the tests and the simulator build**

Run: `swift test --filter AudioFileWriterTests && cd ../ && xcodebuild -project Lifeline.xcodeproj -scheme Lifeline -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.3' build | tail -1`
Expected: 4 passed; `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add audio capture, conversion and m4a writer"
```

---

### Task 7: `SpeechAnalyzerTranscriber` (iOS 26)

**Files:**
- Create: `Voice/WordRuns.swift`, `Voice/TranscriberAvailability.swift`, `Voice/iOS/SpeechAnalyzerTranscriber.swift`
- Test: `Tests/LifelineKitTests/WordRunsTests.swift`, `TranscriberAvailabilityTests.swift`

**Interfaces:**
- Consumes: `Transcriber`, `TranscriptResult`, `TranscribedWord`, `AudioChunk`.
- Produces:
  - `enum WordRuns { static func words(from text: AttributedString) -> [TranscribedWord] }` — one word per run that carries `audioTimeRange`; a run whose text has several whitespace-separated tokens is split evenly across its time range; runs without a time range are attached to the previous word's text; ms values are rounded from `CMTime.seconds`.
  - `enum TranscriberAvailability: Equatable { case ready, needsDownload, unsupportedLocale; static func decide(isSupported: Bool, isInstalled: Bool) -> TranscriberAvailability }`
  - `#if os(iOS) final class SpeechAnalyzerTranscriber: Transcriber { init(locale: Locale = .current, onStatus: @Sendable (TranscriberAvailability) -> Void = { _ in }) }`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func oneWordPerTimedRun() {
    var s = AttributedString("the blue door")
    // give each word a range; CMTime at 1000 timescale
    s[s.range(of: "the")!].audioTimeRange  = CMTimeRange(start: .init(value: 0, timescale: 1000), end: .init(value: 300, timescale: 1000))
    s[s.range(of: "blue")!].audioTimeRange = CMTimeRange(start: .init(value: 300, timescale: 1000), end: .init(value: 700, timescale: 1000))
    s[s.range(of: "door")!].audioTimeRange = CMTimeRange(start: .init(value: 700, timescale: 1000), end: .init(value: 1100, timescale: 1000))
    #expect(WordRuns.words(from: s) == [w("the",0,300), w("blue",300,700), w("door",700,1_100)])
}

@Test func multiTokenRunIsSplitEvenly() { /* one run "a b" over 0..<1000 → a 0..<500, b 500..<1000 */ }
@Test func punctuationWithoutTimeJoinsPreviousWord() { /* runs: "door" timed, "." untimed → one word "door." */ }

@Test func availabilityDecision() {
    #expect(TranscriberAvailability.decide(isSupported: true, isInstalled: true) == .ready)
    #expect(TranscriberAvailability.decide(isSupported: true, isInstalled: false) == .needsDownload)
    #expect(TranscriberAvailability.decide(isSupported: false, isInstalled: false) == .unsupportedLocale)
}
```

The `audioTimeRange` attribute lives in `AttributeScopes.SpeechAttributes` and is available on macOS 26, so these tests run under `swift test`. If the dynamic-member spelling `.audioTimeRange` does not compile, use the key type: `s[range][AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = …`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'WordRunsTests|TranscriberAvailabilityTests'`
Expected: compile failure.

- [ ] **Step 3: Implement `WordRuns` and `TranscriberAvailability`**

- [ ] **Step 4: Implement `SpeechAnalyzerTranscriber`**

The declarations verified in the iOS 27.1 SDK interface, so the implementer does not have to hunt:

```swift
let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
// availability
let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil
let installed = SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
onStatus(TranscriberAvailability.decide(isSupported: supported, isInstalled: installed))
if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await req.downloadAndInstall() }
// format and analyzer
let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])   // convert from CaptureFormat if it differs
let (input, cont) = AsyncStream<AnalyzerInput>.makeStream()
let analyzer = SpeechAnalyzer(modules: [transcriber])
try await analyzer.start(inputSequence: input)
// feed: cont.yield(AnalyzerInput(buffer: converted))
// results: for try await r in transcriber.results { TranscriptResult(text: String(r.text.characters), words: WordRuns.words(from: r.text), range: ms(r.range), isFinal: r.isFinal) }
// finalize(throughMs:): try await analyzer.finalize(through: CMTime(value: Int64(ms), timescale: 1000))
// finish(): cont.finish(); try await analyzer.finalizeAndFinishThroughEndOfInput()
```

If `best` differs from `CaptureFormat.format`, add an `AVAudioConverter` inside `feed`. Analyzer time starts at zero with the first buffer, so it equals file time as long as `feed` receives every chunk the sink receives (the actor in Task 4 guarantees this order).

- [ ] **Step 5: Run the tests and the simulator build**

Run: `swift test --filter 'WordRunsTests|TranscriberAvailabilityTests'` then the `xcodebuild` simulator build.
Expected: 4 passed; `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add SpeechAnalyzer transcriber adapter"
```

---

### Task 8: `SegmentPlayer`

**Files:**
- Create: `Playback/SegmentPlayer.swift`
- Test: `Tests/LifelineKitTests/SegmentPlayerTests.swift`

**Interfaces:**
- Produces: `@MainActor final class SegmentPlayer { init(); var isPlaying: Bool { get }; var positionMs: Milliseconds { get }; func play(url: URL, range: MsRange) throws; func stop(); static func clamp(_ range: MsRange, toDurationMs: Milliseconds) -> MsRange }`

`play` opens an `AVAudioPlayer`, sets `currentTime` to `range.start / 1000`, plays, and stops at `range.end` via a timer that polls every 50 ms. `clamp` is pure.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func clampKeepsRangeInsideFile() {
    #expect(SegmentPlayer.clamp(MsRange(start: 1_000, end: 99_000), toDurationMs: 5_000) == MsRange(start: 1_000, end: 5_000))
    #expect(SegmentPlayer.clamp(MsRange(start: 9_000, end: 9_500), toDurationMs: 5_000) == MsRange(start: 5_000, end: 5_000))
}

@Test @MainActor func playStartsAtRangeStart() async throws {
    /* write a 3 s sine m4a with AudioFileWriter (Task 6 helper); play range 1_000..<2_000; expect positionMs >= 1_000 right after play(); after 1.3 s expect isPlaying == false */
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SegmentPlayerTests`
Expected: compile failure.

- [ ] **Step 3: Implement `SegmentPlayer`**

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SegmentPlayerTests`
Expected: 2 passed. If `playStartsAtRangeStart` cannot run headless (no audio device), mark it `.enabled(if: ProcessInfo.processInfo.environment["LIFELINE_AUDIO_TESTS"] == "1")` and note that in the commit body.

- [ ] **Step 5: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add SegmentPlayer for range playback"
```

---

### Task 9: App screens and composition root

**Files:**
- Create: `ios/Lifeline/Dependencies.swift`, `Screens/AboutYou/AboutYouScreen.swift`, `AboutYouViewModel.swift`, `Screens/Home/HomeScreen.swift`, `HomeViewModel.swift`, `Screens/Session/SessionScreen.swift`, `SessionViewModel.swift`, `Screens/SessionDetail/SessionDetailScreen.swift`, `SessionDetailViewModel.swift`, `Screens/Settings/SettingsScreen.swift`
- Modify: `ios/Lifeline/LifelineApp.swift`
- Test: none automated in M1 beyond the simulator build; the device checklist below is the acceptance test for milestone M1.

**Interfaces:**
- Consumes: everything above.
- Produces: `struct Dependencies: Sendable { let database: AppDatabase; let sessions: SessionRepository; let profile: ProfileRepository; let makeRecorder: @Sendable () -> SessionRecorder; let makePlayer: @MainActor () -> SegmentPlayer; static func live() throws -> Dependencies }`

- [ ] **Step 1: Composition root**

`Dependencies.live()` opens the database at `Application Support/Lifeline/lifeline.sqlite`, calls `SessionRecorder.recoverUnfinishedSessions` once, and builds `makeRecorder` as `ListenOnlyVoiceSession(source: AVAudioEngineSource(), sink: AudioFileWriter(), transcriber: SpeechAnalyzerTranscriber(), log: { print("[voice] \($0)") })` wrapped in a `SessionRecorder` whose `audioURL` is `AudioLocation.url(for:)` and whose pause log appends `pauseObserved` values to `Application Support/Lifeline/pauses.log`. `LifelineApp` shows `AboutYouScreen` when `profile.fetch()` is nil, else `HomeScreen`.

- [ ] **Step 2: About you (Onboard1)**

Fields: name, "Do you want to add your birthday?" toggle revealing a `DatePicker` (date only), "Where did you grow up?", "Anything useful for me to know?" multi-line. Buttons: Skip (saves an empty `Profile`, so first-open does not repeat) and Continue. Copy on screen: "Everything here is optional. You can change it in Settings." `SettingsScreen` presents the same view pre-filled, button "Save".

- [ ] **Step 3: Home**

List of sessions, newest first, each row: date, duration (from last segment end), segment count. A large circular Start button at the bottom. Toolbar: Settings. Tapping Start calls `AudioSessionConfigurator.activateForRecording()`, then `recorder.start()`, and pushes `SessionScreen`.

- [ ] **Step 4: Session (Main)**

Shows elapsed time, the partial transcript line, and the list of closed segments' text, newest at the bottom, auto-scrolling. An interruption shows a quiet "Paused" label. One button: Stop. Stop calls `recorder.stop()`, deactivates the audio session, and pops to Home. `UIApplication.shared.isIdleTimerDisabled` stays false: the screen may lock, and recording continues under the audio background mode. The first prompt text on this screen is "Tell me about the house you grew up in." with three alternates in small type: "A meal you can still taste." "A teacher you remember." "The first place that felt like yours."

- [ ] **Step 5: Session detail (Timeline, M1 form)**

Segments in order with start time and text. Tapping a row plays that segment's range from the session file with `SegmentPlayer`; the playing row shows a stop glyph. A second tap stops.

- [ ] **Step 6: Build and run on the simulator**

Run: `cd ios && xcodegen generate && xcodebuild -project Lifeline.xcodeproj -scheme Lifeline -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.3' build | tail -1`
Expected: `** BUILD SUCCEEDED **`. Launch in the simulator and confirm About you, Skip, Home and Settings render. The simulator has no microphone transcription; recording is checked on the device.

- [ ] **Step 7: Device checklist (owner runs this; it is M1's done-when)**

1. Fill `ios/Config/Local.xcconfig` with the team and bundle prefix. Build and run on the iPhone.
2. First open shows About you. Enter a birthday. Continue.
3. Tap Start. If the speech model downloads, the screen says so and waits.
4. Talk for two minutes, lock the phone, keep talking for one minute, unlock. Expected: segments appear for speech while locked.
5. Receive a phone call or trigger Siri during speech. Expected: "Paused" shows, then recording resumes, and the next segment's timestamps continue from where the file left off.
6. Record a 30-minute session with the screen off. Tap Stop.
7. Home shows the session with its duration. Open it. Tap a segment. Expected: that span of audio plays and the words match.
8. Force-quit the app during a session. Relaunch. Expected: the session appears in Home with an end time, and its audio up to the kill plays.
9. Check Settings shows the saved birthday.

Record the outcome of each item in the commit body of Step 8, including the pause distribution file's first lines.

- [ ] **Step 8: Commit**

```bash
git add ios
git commit -m "Add About you, Home, Session and Session detail screens"
```

---

### Task 10: CLI `sessions` and `import`

**Files:**
- Create: `Session/TranscriptImport.swift`, `Tests/Fixtures/transcript-garden.json`
- Modify: `Sources/lifeline/main.swift`
- Test: `Tests/LifelineKitTests/TranscriptImportTests.swift`

**Interfaces:**
- Produces:
  - Transcript JSON format: `{ "started_at": ISO-8601, "segments": [ { "start_ms": Int, "end_ms": Int, "words": [ { "text": String, "start_ms": Int, "end_ms": Int } ] } ] }`.
  - `enum TranscriptImport { static func importTranscript(at url: URL, into repo: SessionRepository, audioPath: String = "") throws -> SessionID }` — segment `text` is the words joined by single spaces; status `.pending`.
  - CLI: `lifeline sessions --db <path>` prints one line per session: id, started_at, segment count. `lifeline import <transcript.json> --db <path>` imports and prints the new session id. Unknown command prints usage and exits 2.

- [ ] **Step 1: Write the fixture and the failing test**

`transcript-garden.json`: an invented three-segment transcript about a childhood garden with a pomegranate tree, each segment 4 to 8 seconds, word times contiguous.

```swift
@Test func importsFixtureAsSessionWithSegmentsAndWords() throws {
    let db = try AppDatabase.inMemory(); let repo = SessionRepository(db)
    let url = try #require(Bundle.module.url(forResource: "transcript-garden", withExtension: "json", subdirectory: "Fixtures"))
    let id = try TranscriptImport.importTranscript(at: url, into: repo)
    let segs = try repo.segments(in: id)
    #expect(segs.count == 3 && segs[0].index == 0 && segs[0].text.hasPrefix("the garden"))
    #expect(try repo.words(in: segs[0].id).count == segs[0].text.split(separator: " ").count)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TranscriptImportTests`
Expected: compile failure.

- [ ] **Step 3: Implement `TranscriptImport` and `main.swift`**

Hand-parse `CommandLine.arguments`; no ArgumentParser dependency in M1.

- [ ] **Step 4: Run the test and the CLI end to end**

Run: `swift test --filter TranscriptImportTests && swift run lifeline import Tests/Fixtures/transcript-garden.json --db /tmp/lifeline-cli.sqlite && swift run lifeline sessions --db /tmp/lifeline-cli.sqlite`
Expected: 1 passed; the import prints a UUID; `sessions` prints one line with `3` segments.

- [ ] **Step 5: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add lifeline CLI with sessions and import commands"
```

---

## After M1

M2 (extract and confirm) starts from these seams: `Segment.status == .pending` rows, `Profile.freeText` for the context packet, the `candidate` table added in migration v2, and `ExtractionService` in a new `Extraction` module. Its plan is written after M1's device checklist passes, because the pause distribution and the real segment lengths decide the context-packet window and the retry policy.
