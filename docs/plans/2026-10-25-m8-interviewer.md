# M8 Interviewer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app speaks its opening, short reflections and its fixed lines in a session, and the person always wins: any speech stops it, one word or tap makes it quiet, and its words never become the person's.

**Architecture:** A pure `TurnPolicy` decides every turn from events and a clock. An `InterviewerLoop` actor in the kit feeds the policy, asks the model for a reflection and hands each approved turn to `SessionRecorder.speak`. The listen-only voice session becomes `CascadeVoiceSession` with a `VoiceOutput` (silent, or `AVSpeechSynthesizer` through a player node on the capture engine with voice processing on). The session removes the app's own words from segments (`EchoFilter`), detects barge-in and voice commands on partials, and reports each turn's playback on the file clock; the recorder stores turns in `interviewer_turn` (v11).

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVSpeechSynthesizer.write`), GRDB 7 (migration v11), Swift Testing, XCUITest, Anthropic Messages API structured output (existing client).

**Spec:** `docs/specs/2026-10-25-m8-interviewer.md` (owner's calls A to C and 1 to 7 decided 2026-10-25). Read "Turn policy", "Goal 3", "Goal 2" and "Ship order" first.

## Ship order

| PR | Branch | Tasks | Base |
|---|---|---|---|
| 1 — The interviewer's turns, silent | `m8a-turns` | A1–A7 | `m8-interviewer-spec` rebased on `origin/main` after M7 PR B (#11) merges |
| 2 — Fixed turns are spoken | `m8b-voice` | B1–B3 | `m8a-turns` |
| 3 — Reflections and the gate | `m8c-model` | C1–C4 | `m8b-voice` |
| 4 — Device run | `m8d-device` | D1 | `m8c-model` |

Each PR is stacked on the one before. After a PR merges, rebase the next on `origin/main`. Nothing is pushed by the executor.

## Global Constraints

- At most 20 words per model turn. A turn that fails a client check is dropped, never repaired.
- Fixed copy, exact: wrap-up "We can leave it here, or carry on."; early wind-down "We can leave this here and come back whenever you want."; about the app "I'm Lifeline. I keep your recording on this phone. Your words go to Anthropic's model as text, so I can sort them and ask the next question."
- Disclosure, spoken: present danger speaks `disclosure.<locale>.md` exactly; past speaks `disclosure-spoken-past.<locale>.md` ("Thank you for telling me that. You can stop here, or keep going. It is your choice."). The card does not change.
- Numbers: `replyGrace` 1.5 s; a partial holds the floor for 1 s; echo window pad 300 ms; echo match 60 % of the turn's tokens in order; barge-in at 2 non-matching partial words; stop within 500 ms (device check); context budget 1500 tokens (characters ÷ 4). Policy numbers live in `ArcConfig`; echo numbers in `EchoConfig`.
- Interviewer model: `claude-haiku-5-5`, effort `low`, thinking disabled, `max_tokens` 512, one attempt, no `fallbacks` and no fallback beta (Haiku 5.5 has no server-side fallback), transport timeout 4 s.
- The opening counts as a question for rule 7 (plan's call). Rule 7 counts spoken turns only.
- The gate applies to every turn after the opening except the disclosure text and the early wind-down line. An unclean interviewer check ends model turns and the spoken wrap-up for the session (spec rule 4, amended 2026-10-25).
- After the planned length the arc stays in `windDown` even after "Keep going", so reflections stop there (rule 10 as written).
- "Lifeline speaks" off builds exactly today's session: no loop, no voice processing, `SilentVoiceOutput`.
- No code outside `Interviewer/InterviewerContext.swift` sends a segment's words to the interviewer model; it never reads earlier sessions.
- Kit tests: `cd ios/LifelineKit && swift test`. UI tests: `xcodebuild test -project ios/Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/<Class>`; run `xcodegen generate` in `ios/` after adding app or UI-test files.
- Fixtures are invented; never a real person's words.

## Review Focus

1. A short blip the segmenter abandons ("mm-hm", a cough): today no event follows `speechStarted`, so the policy would hold "speaking" forever and the app would never speak again. The segmenter emits `.abandoned` and the session emits `.userPaused`. Task A2 (`anAbandonedBlipEndsSpeaking`).
2. A disclosure in segment N, then a clean segment N+1 while the extractor is slow on N: no reflection on N+1. Task A4 (`anUncleanCheckOnAnEarlierSegmentSilencesLaterTurns`).
3. A past disclosure, then present danger later in the same session: the 988 line is spoken once, when present arrives. Task A2 (`presentAfterPastShowsTheCardAgain`), Task A6 (`presentAfterPastSpeaksThe988Line`).
4. The person barges in after three words of a turn: those three app words are removed, the person's words in the window stay, and the segment starts at the person's first word. Task A3 (`anInterruptedTurnRemovesOnlyThePlayedPrefix`), Task B2 (`bargeInStopsPlaybackAndKeepsThePersonsWords`).
5. A voice command inside a longer sentence ("there were no questions at school"): it does not set quiet. Commands count only in a partial of at most 4 words (plan's call). Task B2 (`aCommandInsideASentenceIsIgnored`).

---

## PR 1 — The interviewer's turns, silent

### Task A1: Store — `interviewer_turn`, v11

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Domain/Identifiers.swift` (`InterviewerTurnID`)
- Create: `Domain/InterviewerTurn.swift`, `Store/InterviewerTurnRepository.swift`
- Modify: `Store/Migrations.swift` (`v11`), `Store/AppDatabase.swift` (if repositories are listed there)
- Test: `MigrationsTests.swift`, new `InterviewerTurnRepositoryTests.swift`, `BackupTests.swift`

**Interfaces:**
- Produces: `enum TurnKind: String, Codable, CaseIterable { opening, reflection, question, wrapUp, earlyWindDown, disclosure, aboutApp }`; `var isQuestion: Bool` (`opening`, `question`); `enum TurnSource: String, Codable { fixed, model }`.
- Produces: `struct InterviewerTurn { id, sessionID, kind, source, text, startMs: Milliseconds, endMs: Milliseconds?, interrupted: Bool }` (GRDB record, table `interviewer_turn`).
- Produces: `InterviewerTurnRepository(_ db: AppDatabase)`: `insert(_:)`, `end(_ id:, atMs:, interrupted:)`, `turns(in: SessionID) -> [InterviewerTurn]` ordered by `start_ms`.

- [ ] **Step 1: Failing tests** — `v11OnAPopulatedV10Database` (the M7 fixture archive migrates; table exists; foreign key on `session` cascades); `turnsListInFileOrder`; `endSetsEndAndInterrupted`; `deletingASessionDeletesItsTurns` (`deleteSession`); `aTurnSurvivesBackupAndRestore` (follow the existing backup round-trip test).
- [ ] **Step 2: Run** `swift test --filter "v11|InterviewerTurn|aTurnSurvives"` — Expected: FAIL (no table).
- [ ] **Step 3: Implement.** v11: `interviewer_turn (id text pk, session_id text not null references session on delete cascade, kind text not null, source text not null, text text not null, start_ms integer not null, end_ms integer, interrupted boolean not null default false)`, index on `session_id`.
- [ ] **Step 4: Run** `swift test` — Expected: green.
- [ ] **Step 5: Commit** `git commit -m "Store: the interviewer's turns, on the session's file clock (v11)"`

### Task A2: Arc reasons, fixed text, abandoned blips

**Files:**
- Modify: `Arc/SessionArc.swift`, `Arc/FixedResponses.swift`, `Voice/Segmenter.swift`, `Voice/ListenOnlyVoiceSession.swift` (the `.abandoned` case only)
- Create: `Arc/FixedResponses/disclosure-spoken-past.en-US.md`, `Interviewer/FixedTurns.swift`
- Modify: `ios/Lifeline/Screens/Session/SessionViewModel.swift` (the effect switch compiles against the new cases)
- Test: `SessionArcTests.swift`, `FixedResponsesTests.swift`, `SegmenterTests.swift`, `ListenOnlyVoiceSessionTests.swift`

**Interfaces:**
- Produces: `enum WrapUpReason: Equatable { plannedLength, wantsToStop }`; `ArcEffect.offerWrapUp(WrapUpReason)`; `ArcEffect.showDisclosureCard(DisclosureKind)`. The card effect comes on the first disclosure and once more when a later flag escalates past → present.
- Produces: `FixedResponses.spokenDisclosure(_ kind: DisclosureKind, locale: Locale = .current) throws -> String?` (nil for `.none`).
- Produces: `enum FixedTurns { static let wrapUp, earlyWindDown, aboutTheApp: String }` (copy in Global Constraints).
- Produces: `SegmenterEvent.abandoned(MsRange)`, emitted where a segment with too little speech is dropped today. The voice session answers it with `.userPaused(afterMs: range.end)` and nothing else.

- [ ] **Step 1: Failing tests** — `plannedLengthAndGraceGiveThePlannedReason`; `wantsToStopGivesTheWantsToStopReason`; `presentAfterPastShowsTheCardAgain` (past → `.showDisclosureCard(.past)`; later present → `.showDisclosureCard(.present)`; a third flag → nil); `presentSpokenEqualsTheCard`; `theCardStartsWithThePastText`; `thePastTextHasNoCrisisNumber` (no "988"); `anAbandonedBlipEndsSpeaking` (segmenter: 500 ms of speech then 1.8 s quiet → `[.speechStarted, .abandoned]`; session: `.userPaused` follows, no `.segmentClosed`). Update the existing `SessionArcTests` expectations to the new cases.
- [ ] **Step 2: Run** `swift test --filter "SessionArc|FixedResponses|Segmenter|ListenOnly"` — Expected: FAIL.
- [ ] **Step 3: Implement**; the view model's existing behavior is unchanged (banner on any wrap-up reason, card on any kind).
- [ ] **Step 4: Run** `swift test` and an app build — Expected: green; BUILD SUCCEEDED.
- [ ] **Step 5: Commit** `git commit -m "Arc: say why the wrap-up is offered; a past and a present disclosure each have their spoken text"`

### Task A3: `TurnText` and `EchoFilter`

**Files:**
- Create: `Interviewer/TurnText.swift`, `Voice/EchoFilter.swift`
- Test: new `EchoFilterTests.swift`

**Interfaces:**
- Produces: `enum TurnText { static func tokens(_ text: String) -> [String] }` (lowercased; letters and digits only; inner apostrophes dropped, so "Maya's" → "mayas").
- Produces: `struct EchoConfig { padMs = 300, matchShare = 0.6, bargeInWords = 2 }`.
- Produces: `struct PlaybackWindow { range: MsRange, text: String }`.
- Produces: `enum EchoFilter { static func personsWords(_ words: [TranscribedWord], windows: [PlaybackWindow], config: EchoConfig) -> [TranscribedWord]; static func nonMatchingCount(_ partial: String, turnText: String) -> Int }`.

Algorithm (the tests do not fix it): for each window, take the words whose start lies in `range` widened by `padMs` on both sides. Align their tokens to the turn's tokens with a longest common subsequence. Let `k` be the index of the last turn token matched. The run is the app's if at least 2 tokens matched and `matched / (k + 1) ≥ matchShare`. Then only the aligned words are removed. Measuring against the matched prefix covers an interrupted turn. `nonMatchingCount` is the number of partial tokens outside the same alignment.

- [ ] **Step 1: Failing tests** — `aMatchingRunInsideTheWindowIsRemoved`; `aNonMatchingRunInsideTheWindowStays`; `aMatchingRunOutsideTheWindowStays`; `anInterruptedTurnRemovesOnlyThePlayedPrefix` (turn of 12 words, 3 heard plus 4 person words inside the window → the 4 stay); `oneCoincidentWordStays` ("yes" in the window, turn contains "yes"); `nonMatchingCountsThePersonsWords`.
- [ ] **Step 2: Run** `swift test --filter EchoFilter` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Voice: tell the app's own words from the person's"`

### Task A4: `TurnPolicy`

**Files:**
- Create: `Interviewer/TurnPolicy.swift`
- Modify: `Arc/ArcConfig.swift` (`replyGrace: Duration = .seconds(1.5)`, `partialHoldsFloor: Duration = .seconds(1)`; `uiTesting`: 0.3 s and 1 s)
- Test: new `TurnPolicyTests.swift`

**Interfaces:**
- Consumes: `TurnKind`, `TurnSource` (A1); `WrapUpReason` (A2); `Flags`, `DisclosureKind`, `Stage`, `SessionKind`.
- Produces: `struct SafetyCheck: Equatable { disclosure: DisclosureKind; wantsToStop: Bool; var isClean: Bool }`.
- Produces: `enum TurnInput { speechStarted, partial, userPaused, segmentStored(SegmentID), interviewerCheck(SegmentID, SafetyCheck?), extractorFlags(SegmentID, Flags), stage(Stage), quiet(Bool), turnStarted(TurnKind), turnEnded }`. A nil check means the call failed.
- Produces: `struct TurnOffer { kind: TurnKind; source: TurnSource; text: String; requestedAt: Duration? }`.
- Produces: `enum TurnDecision: Equatable { speak; stayQuiet(QuietReason) }`; `enum QuietReason { personSpeaking, appSpeaking, heavy, quiet, gate, stale, noSegmentSince, questionTooSoon, windDown, quickStory, openingTooLate }`.
- Produces: `struct TurnPolicy { init(kind: SessionKind, config: ArcConfig); mutating func observe(_ input: TurnInput, at: Duration); func decide(_ offer: TurnOffer, at: Duration) -> TurnDecision; func segmentAwaitingReply(at: Duration) -> SegmentID? }`. `at` is the time since the session started. `segmentAwaitingReply` returns the newest stored segment once `replyGrace` has passed with no speech and no turn since it; it returns nil in a quick story, when quiet, after heavy, and in `windDown`.

- [ ] **Step 1: Failing tests**, one per spec rule plus: `quietWhilePersonSpeaks` (speechStarted, no userPaused → `.personSpeaking`; a partial 0.8 s ago → `.personSpeaking`; 1.2 s ago → not); `neverTwoTurnsWithoutAStoredSegment`; `aFixedTurnAfterADisclosureMayFollowAtOnce`; `noQuestionWithinTwoTurnsOfAQuestion`; `theOpeningCountsAsAQuestion`; `heavyFlagsEndModelTurns`; `anUncleanCheckSilencesTheTurnAndLaterTurns`; `anUncleanCheckOnAnEarlierSegmentSilencesLaterTurns`; `noTurnBeforeTheCheckReturns`; `aFailedCheckIsSilent`; `extractorFlagsThatArrivedMustBeCleanToo`; `aStaleReplyIsDropped` (requestedAt before the last speechStarted); `quickStorySpeaksOnlyOpeningDisclosureAndWindDown`; `quietAllowsOnlyDisclosureAndWindDown`; `windDownAllowsOnlyWrapUpAndFixedTurns`; `theOpeningIsNotSpokenAfterSpeechStarted`; `noSegmentNoReplyRequest`. The 6 s next question is never an offer (it has no `TurnKind`); `nextQuestionIsNeverSpoken` asserts that `TurnKind.allCases` holds no bank question.
- [ ] **Step 2: Run** `swift test --filter TurnPolicy` — Expected: FAIL.
- [ ] **Step 3: Implement.** Rule precedence follows the spec: speaking, then heavy, quiet, gate, stale, rules 6, 7 and 10, then quick story.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Interviewer: a pure turn policy, silence by default"`

### Task A5: Voice session speaks turns (silently) and keeps them out of segments

**Files:**
- Rename: `Voice/ListenOnlyVoiceSession.swift` → `Voice/CascadeVoiceSession.swift` (type `CascadeVoiceSession`); `ListenOnlyVoiceSessionTests.swift` → `CascadeVoiceSessionTests.swift`
- Create: `Voice/VoiceOutput.swift` (protocol, `SilentVoiceOutput`)
- Modify: `Voice/VoiceSession.swift`, `Voice/ScriptedVoiceSession.swift`, `Session/SessionRecorder.swift`, `ios/Lifeline/Dependencies.swift`
- Test: `CascadeVoiceSessionTests.swift`, `SessionRecorderTests.swift`, `ScriptedVoiceSessionTests.swift`, `Tests/LifelineKitTests/Fakes/FakeVoiceOutput.swift`

**Interfaces:**
- Consumes: `EchoFilter`, `PlaybackWindow`, `EchoConfig` (A3); `InterviewerTurnRepository`, `TurnKind`, `TurnSource` (A1).
- Produces: `struct SpokenTurn { id: InterviewerTurnID; text: String }`. `VoiceSession.say(_ turn: SpokenTurn) async` replaces `say(_ text: String)` and returns at once; `acknowledge()` stays a no-op.
- Produces: `VoiceEvent.turnStarted(InterviewerTurnID, atMs:)`, `.turnEnded(InterviewerTurnID, atMs:, interrupted: Bool)`.
- Produces: `enum PlaybackEvent { started, finished(completed: Bool) }`; `protocol VoiceOutput: Sendable { func play(_ text: String) -> AsyncStream<PlaybackEvent>; func stop() async }`; `SilentVoiceOutput` yields `started`, then `finished(completed: true)`.
- Produces: `CascadeVoiceSession.init(..., output: any VoiceOutput = SilentVoiceOutput(), echo: EchoConfig = .init(), ...)`. Each turn is stamped with `lastChunkEndMs` at start and at end, which are also its `PlaybackWindow`. While a turn plays, the segmenter is fed `-Float.infinity`, so the app's voice does not open a segment or move the pause timer. `takeSegment` and the final flush in `stop()` pass words through `EchoFilter.personsWords`. Pause, an interruption and stop call `output.stop()`; a stopped turn ends with `interrupted: true` and is not resumed.
- Produces: `struct TurnDraft { kind: TurnKind; source: TurnSource; text: String }`; `SessionRecorder.speak(_ draft: TurnDraft) async`. The recorder inserts the row on `.turnStarted` (with `endMs` nil) and ends it on `.turnEnded`. `RecorderState.turns: [InterviewerTurn]`; `RecorderState.speakingTurn: InterviewerTurnID?`. `RecorderHooks.onVoiceEvent: @Sendable (VoiceEvent) -> Void` is called for every event.
- Produces: `SessionRecorder.init(..., turns: InterviewerTurnRepository, ...)`.

- [ ] **Step 1: Failing tests** — `aTurnIsStoredOnTheFileClock`; `appWordsInAFinalNeverReachASegment` (a fake transcriber returns the turn's words inside its window, then the person's words → the segment holds only the person's); `aSegmentOfOnlyAppWordsIsNotStored`; `energyDuringPlaybackOpensNoSegment`; `pauseCutsTheTurn` (`FakeVoiceOutput` keeps playing until stopped → `.turnEnded(interrupted: true)`); `aTurnCutByACrashHasNoEnd` (row present, `endMs` nil, crash-resume landing still shows the session); `scriptedSessionReportsTurns`.
- [ ] **Step 2: Run** `swift test --filter "Cascade|SessionRecorder|ScriptedVoice"` — Expected: FAIL.
- [ ] **Step 3: Implement**; fix the compiler's list of callers of the rename and of `say`.
- [ ] **Step 4: Run** `swift test` and an app build — Expected: green; BUILD SUCCEEDED.
- [ ] **Step 5: Commit** `git commit -m "Voice: the session can take a turn, and the app's words stay out of the person's"`

### Task A6: `InterviewerLoop` — fixed turns

**Files:**
- Create: `Interviewer/InterviewerLoop.swift`
- Test: new `InterviewerLoopTests.swift`

**Interfaces:**
- Consumes: `TurnPolicy` (A4), `TurnDraft` (A5), `FixedTurns`, `FixedResponses.spokenDisclosure` (A2).
- Produces: `struct InterviewerState: Equatable { isQuiet: Bool }`.
- Produces: `actor InterviewerLoop { init(kind:, config: ArcConfig, speak: @escaping @Sendable (TurnDraft) async -> Void, now: @escaping @Sendable () -> Duration, sleep: @escaping @Sendable (Duration) async -> Void); nonisolated let states: AsyncStream<InterviewerState>; func captureStarted(opening: String); func voice(_ event: VoiceEvent); func segmentStored(_ id: SegmentID); func flags(_ flags: Flags, segment: SegmentID); func arc(_ effect: ArcEffect, stage: Stage); func setQuiet(_ quiet: Bool); func keepGoing() }`.
- Behavior:
  - The opening is offered once, at `captureStarted`.
  - `.showDisclosureCard(kind)` offers the spoken disclosure, then the early wind-down line.
  - `.offerWrapUp(.wantsToStop)` offers the early wind-down line.
  - `.offerWrapUp(.plannedLength)` is ignored until C3.
  - A fixed turn the policy holds back because the person is speaking stays pending. It is offered again `replyGrace` after each `.userPaused`, until it is spoken.
  - `keepGoing()` and stage `ended` clear a pending wrap-up.

- [ ] **Step 1: Failing tests** (scripted `speak` that records drafts; manual clock) — `theOpeningIsSpokenOnce`; `theOpeningIsSkippedIfThePersonAlreadySpoke`; `aDisclosureSpeaksTheKindsTextThenTheWindDownLine`; `presentAfterPastSpeaksThe988Line`; `aDisclosureWhileThePersonSpeaksWaitsForThePause`; `quickStoryWantsToStopSpeaksTheWindDownLine`; `quietStopsEverythingButTheDisclosure`.
- [ ] **Step 2: Run** `swift test --filter InterviewerLoop` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Interviewer: the loop offers the opening and the arc's fixed lines"`

### Task A7: App — turns on screen

**Files:**
- Modify: `ios/Lifeline/Screens/Session/SessionViewModel.swift`, `SessionScreen.swift`, `ios/Lifeline/Dependencies.swift` (`makeRecorder(onStatus:queue:interviewer:)`)
- Modify: `ios/Lifeline/Screens/SessionDetail/SessionDetailViewModel.swift`, `SessionDetailScreen.swift`
- Test: `ios/LifelineUITests/InterviewerUITests.swift` (new)

**Interfaces:**
- Consumes: `InterviewerLoop` (A6); `RecorderState.turns`, `RecorderHooks.onVoiceEvent` (A5).
- The view model builds the loop in `start()`. It forwards voice events, stored segments, extractor flags and arc effects, with the stage after each. The Listen view shows the newest turn that is not the opening, under the prompt, labeled "Lifeline". The transcript views show every turn between segments by `startMs`, labeled "Lifeline". Accessibility identifiers: `session.turn`, `transcript.turn`.

- [ ] **Step 1: Failing UI test** — `testScriptedDisclosureShowsAndStoresTheFixedText` (`-uiTesting -uiTesting-heavy`; the card shows; `session.turn` equals the spoken text for the scripted kind; Session detail shows it as a `transcript.turn`).
- [ ] **Step 2: Run** (`xcodegen generate` first) — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the new class and `LandingUITests`, `ExtractionUITests` — Expected: green.
- [ ] **Step 5: Commit** `git commit -m "Session: the interviewer's turns show where the person reads"`

---

## PR 2 — Fixed turns are spoken

### Task B1: Engine playback and the system voice

**Files:**
- Modify: `Voice/iOS/AVAudioEngineSource.swift` (`init(bufferMs:, voiceProcessing: Bool = false)`; a player node attached to the engine; `func schedule(_ buffer: AVAudioPCMBuffer) async`, which returns when the buffer has played; `func stopPlayback()`; a configuration change also stops playback)
- Create: `Voice/iOS/AVSpeechVoiceOutput.swift`, `Voice/VoicePicker.swift`
- Test: new `VoicePickerTests.swift` (the only part testable off the device)

**Interfaces:**
- Produces: `struct VoiceInfo { identifier: String; language: String; quality: Quality /* default, enhanced, premium */ }`; `enum VoicePicker { static func best(_ voices: [VoiceInfo]) -> VoiceInfo?; static func onlyCompact(_ voices: [VoiceInfo]) -> Bool }`. It prefers en-US premium, then enhanced, then default, then any `en-*`.
- Produces: `final class AVSpeechVoiceOutput: VoiceOutput { init(source: AVAudioEngineSource) }`. It renders with `AVSpeechSynthesizer.write(_:toBufferCallback:)`, converts to the player node's format and schedules on the source. `stop()` stops the synthesizer and the player.
- `setVoiceProcessingEnabled(true)` on the input node is set before `engine.start()`, only when `voiceProcessing` is true. The tap's converter already adapts to the new input format.

- [ ] **Step 1: Failing tests** — `premiumBeatsEnhancedBeatsDefault`; `aUSVoiceBeatsOtherEnglish`; `onlyCompactWhenNoEnhancedOrPremium`.
- [ ] **Step 2: Run** `swift test --filter VoicePicker` — Expected: FAIL.
- [ ] **Step 3: Implement**, then build for the device.
- [ ] **Step 4: Run** `swift test` and an app build — Expected: green; BUILD SUCCEEDED. Device check (owner): a spoken test line plays through the speaker while recording, and the m4a has no gap.
- [ ] **Step 5: Commit** `git commit -m "Voice: the system voice plays through the capture engine with voice processing"`

### Task B2: Barge-in and voice commands

**Files:**
- Create: `Voice/QuietMatcher.swift`
- Modify: `Voice/CascadeVoiceSession.swift`, `Voice/VoiceSession.swift`
- Test: `CascadeVoiceSessionTests.swift`, new `QuietMatcherTests.swift`

**Interfaces:**
- Produces: `enum VoiceCommand { quiet, keepGoing }`; `VoiceEvent.heard(VoiceCommand)`.
- Produces: `enum QuietMatcher { static func command(in partial: String) -> VoiceCommand? }`.
  - Quiet phrases: "let me talk", "shh" (any `sh+`), "quiet please", "stop talking", "no questions".
  - Keep-going phrases: "keep going", "a bit more".
  - A phrase counts only as consecutive tokens, and only in a partial of at most 4 tokens.
- Session behavior during a turn's window, widened by `padMs`:
  - A partial with `nonMatchingCount ≥ bargeInWords` calls `output.stop()`, ends the turn interrupted and is emitted.
  - Any other partial is dropped: it is not emitted, it is not a command and it does not hold the floor.
  - Outside the window, partials are emitted as today.
  - A command is emitted at most once per utterance; a final resets this.

- [ ] **Step 1: Failing tests** — `eachPhraseIsACommand`; `weHadToStopAtTheBorderIsNot`; `aCommandInsideASentenceIsIgnored`; `bargeInStopsPlaybackAndKeepsThePersonsWords` (fake output; a partial of 2 new words → `stop()` called, `.turnEnded(interrupted: true)`; the person's final words are in the next segment); `theAppsOwnWordsAreNotACommandOrABargeIn` (the turn text is "no questions for now…" → no `.heard`, no stop); `aCommandIsEmittedOncePerUtterance`.
- [ ] **Step 2: Run** `swift test --filter "QuietMatcher|Cascade"` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test` — Expected: green.
- [ ] **Step 5: Commit** `git commit -m "Voice: any speech stops the app; a few words make it quiet"`

### Task B3: App — "Lifeline speaks", Quiet, and scripted speech

**Files:**
- Modify: `ios/Lifeline/Dependencies.swift`: `makeVoiceSession` reads `speaks`; on means `AVAudioEngineSource(voiceProcessing: true)` plus `AVSpeechVoiceOutput`; off means today's session and no loop. Under `-uiTesting`, speaking is on only with `-uiTesting-speaks`.
- Modify: `Screens/Settings/SettingsScreen.swift` (toggle `settings.speaks`, `UserDefaults` key `lifeline.speaks`, default true; when `VoicePicker.onlyCompact`, the line "A more natural voice can be downloaded in iOS Settings → Accessibility → Spoken Content → Voices.")
- Modify: `Screens/Session/SessionViewModel.swift`, `SessionScreen.swift`:
  - A `session.quiet` button reads "Quiet" while the app may speak and "Ask me again" while it is quiet.
  - `.heard(.quiet)` sets quiet.
  - `.heard(.keepGoing)` calls `keepGoing()` when the wrap-up is offered.
- Modify: `Voice/ScriptedVoiceSession.swift`. `say` plays for 150 ms per word. A scripted segment that starts during a turn ends that turn interrupted.
- Test: `InterviewerUITests.swift`

- [ ] **Step 1: Failing UI tests** — `testSpeechDuringATurnMarksItInterrupted` (`-uiTesting-speaks -uiTesting-heavy -uiTesting-slow`; detail shows the turn marked interrupted, `transcript.turn.interrupted`); `testQuietStopsTurnsAndAskMeAgainBringsThemBack`; `testSpeaksOffShowsNoTurns`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `InterviewerUITests` and the full UI suite — Expected: green.
- [ ] **Step 5: Commit** `git commit -m "Settings: Lifeline speaks, on by default; Quiet is one tap away"`

---

## PR 3 — Reflections and the gate

### Task C1: The interviewer service

**Files:**
- Modify: `Extraction/ExtractorConfig.swift`: `maxAttempts: Int = 3` and `thinkingDisabled: Bool = false`, plus `static let interviewer`, which is `claude-haiku-5-5`, effort `low`, `maxTokens` 512, version `v1`, `betas` [] and `maxAttempts` 1, with thinking disabled.
- Modify: `Extraction/AnthropicMessagesClient.swift`: it reads `config.maxAttempts`, and sends `"thinking": {"type": "disabled"}` when set.
- Create: `Interviewer/InterviewerService.swift` (protocol, `InterviewerReply`, schema), `Interviewer/AnthropicInterviewerService.swift`, `Interviewer/ScriptedInterviewerService.swift`, `Interviewer/Prompts/interviewer.v1.md` (add the resource to `Package.swift`)
- Test: `AnthropicMessagesClientTests.swift`, new `InterviewerServiceTests.swift`, new `InterviewerIntegrationTests.swift` (enabled only with `ANTHROPIC_API_KEY`, like `ExtractorIntegrationTests`)

**Interfaces:**
- Produces: `struct InterviewerReply: Decodable, Equatable { kind: ReplyKind /* reflection, question, none */; text: String?; askedAboutApp: Bool; disclosure: DisclosureKind; wantsToStop: Bool; var check: SafetyCheck }`. The keys are snake_case as in the spec, and every key is required.
- Produces: `struct InterviewerRequest: Equatable { segments: [String] /* newest first */; opening: String; stage: Stage; recentTurns: [String] /* last three */ }`, plus `func userMessage() throws -> String` (JSON, sorted keys).
- Produces: `protocol InterviewerService: Sendable { func reply(to request: InterviewerRequest) async throws(ExtractionError) -> InterviewerReply }`.
- Produces: `AnthropicInterviewerService(config: .interviewer, apiKey:, transport: URLSessionTransport(timeout: 4))`.
- Produces: `ScriptedInterviewerService(disclosureOn: Set<Int>)`. It returns a reflection made of the newest segment's last four words, with the first letter capitalized. It returns `disclosure: .past` for segment indexes in the set.
- The prompt states the spec's rules: reflect more than ask; one short turn; quote the person's words; ask for one scene ("What was that like?"); never evaluate; never answer a question about the person's life; return `none` when unsure; set `asked_about_app` and leave `text` empty when asked what the app is.

- [ ] **Step 1: Failing tests** — `oneAttemptOnly` (a 500 → one request, `.server`); `thinkingDisabledIsSent`; `noFallbackForTheInterviewer` (no `fallbacks` key, no beta header); `aReplyDecodes`; `aMissingKeyIsNoKey`. Integration (owner's key): `aQuestionAboutTheirLifeIsNotAnswered`; `aPastDisclosureIsFlagged`; `aShortStoryGetsAtMost20WordsOrNone`.
- [ ] **Step 2: Run** `swift test --filter "AnthropicMessagesClient|InterviewerService"` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test` — Expected: green.
- [ ] **Step 5: Commit** `git commit -m "Interviewer: one fast call that returns a short turn and a safety check"`

### Task C2: Context and client checks

**Files:**
- Create: `Interviewer/InterviewerContext.swift`, `Interviewer/TurnChecks.swift`
- Modify: `Store/MemoryRepository.swift` (`excludedSegmentIDs(in: SessionID) -> Set<SegmentID>`: segments holding a span of a memory excluded from AI)
- Test: new `InterviewerContextTests.swift`, `TurnChecksTests.swift`, `MemoryRepositoryTests.swift`

**Interfaces:**
- Consumes: `InterviewerRequest` (C1).
- Produces: `enum InterviewerContext { static func build(segments: [Segment], excluded: Set<SegmentID>, opening: String, stage: Stage, turns: [InterviewerTurn], tokenBudget: Int = 1500) -> InterviewerRequest }`. It takes segments newest first and stops before the one that would pass the budget.
- Produces: `enum TurnChecks { static func validate(_ reply: InterviewerReply, sessionWords: [String], maxWords: Int = 20) -> CheckedTurn }`; `enum CheckedTurn: Equatable { speak(TurnKind, String), aboutApp, none, dropped(String) }`.
  - Capitalized words count unless they open a sentence or are "I" or a form of "I".
  - Digit tokens count. Spelled numbers do not.
  - Each counted word must be in `TurnText.tokens` of the session's words. Otherwise the turn is dropped.
  - Text when `kind` is `none` drops the turn.

- [ ] **Step 1: Failing tests** — `newestFirstWithinTheBudget`; `anExcludedSegmentIsLeftOut`; `nothingFromAnotherSession`; `over20WordsIsDropped`; `aNameThePersonDidNotSayIsDropped`; `aNumberThePersonDidNotSayIsDropped`; `aSecondSentenceMayStartCapitalized`; `textWithNoneIsDropped`; `askedAboutAppNeverSpeaksModelText`; `excludedSegmentIDsFollowSpans`.
- [ ] **Step 2: Run** `swift test --filter "InterviewerContext|TurnChecks|excludedSegmentIDs"` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Interviewer: this session's words only, and no detail the person did not say"`

### Task C3: The loop asks for reflections behind the gate

**Files:**
- Modify: `Interviewer/InterviewerLoop.swift`
- Test: `InterviewerLoopTests.swift`

**Interfaces:**
- Consumes: `InterviewerService` (C1), `InterviewerContext`, `TurnChecks` (C2), `TurnPolicy.segmentAwaitingReply` (A4).
- Produces: `InterviewerLoop.init(..., service: (any InterviewerService)?, context: @escaping @Sendable () throws -> (InterviewerRequest, sessionWords: [String]))`. The app reads segments and turns from the repositories.
- Behavior:
  - After each `.userPaused`, the loop waits `replyGrace`. Then, if `segmentAwaitingReply` returns a segment, it makes one call for it.
  - The reply's check goes to the policy first, as `.interviewerCheck`; a thrown error goes as `nil`.
  - A `speak` result becomes a `TurnOffer` with `requestedAt`. `aboutApp` offers `FixedTurns.aboutTheApp`.
  - `.offerWrapUp(.plannedLength)` now offers `FixedTurns.wrapUp` behind the gate. Each call logs `[interviewer] <ms> ms <kind or dropped reason>` through an injected `log`, for D1.

- [ ] **Step 1: Failing tests** — `aReflectionFollowsAClosedSegmentAfterTheGrace`; `speechDuringTheCallDropsTheReply`; `aFailedCallIsSilent`; `noKeyMeansNoCallsAndNoSpokenWrapUp` (service nil); `theWrapUpWaitsForACleanCheck`; `aboutTheAppSpeaksTheFixedLine`; `noCallInAQuickStory`; `noCallWhenQuiet`; `aDisclosureSegmentWithASlowFlagGetsNoModelTurn` (the check says `past`, the extractor's flags arrive 5 s later → nothing spoken); `twoSegmentsInsideTheGraceGetOneReflection` (about the newer one).
- [ ] **Step 2: Run** `swift test --filter InterviewerLoop` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test` — Expected: green.
- [ ] **Step 5: Commit** `git commit -m "Interviewer: a short reflection when a story lands, only after a clean check"`

### Task C4: App wiring and the reflection UI test

**Files:**
- Modify: `ios/Lifeline/Dependencies.swift` (`interviewer: (any InterviewerService)?`; live: `AnthropicInterviewerService` over the Keychain key; `-uiTesting`: `ScriptedInterviewerService`), `Screens/Session/SessionViewModel.swift`
- Test: `InterviewerUITests.swift`

- [ ] **Step 1: Failing UI tests** — `testSettleInShowsAReflectionAfterAScriptedSegment` (`-uiTesting-speaks`, settle in; a `session.turn` appears whose text is in the first scripted segment); `testTheWrapUpIsSpokenAtThePlannedLength` (`ArcConfig.uiTesting`; `session.turn` reads the wrap-up line).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full UI suite and `swift test` — Expected: green.
- [ ] **Step 5: Commit** `git commit -m "Session: settling in hears a short reflection"`

---

## PR 4 — Device run

### Task D1: The device checklist and the numbers

**Files:**
- Create: `docs/experiments/2026-10-xx-m8-device-run.md` (date of the run)
- Modify: `Arc/ArcConfig.swift` and the `EchoConfig` defaults in `Voice/EchoFilter.swift`, only where the run says so

- [ ] **Step 1:** Install on the owner's phone (see the device workflow memory). Run the spec's device checklist, items 1 to 10. For each, record pass or fail and what was heard.
- [ ] **Step 2:** Measure and record:
  - interviewer latency at p50 and p90, from `[interviewer]` log lines (target 1200 ms p50);
  - barge-in stop time;
  - the transcription quality of one 5-minute telling with voice processing on and off, as word error against a hand transcript;
  - any app words found in stored segments.
- [ ] **Step 3:** Change only the numbers the run shows are wrong. Add a `docs/DECISIONS.md` entry for each change.
- [ ] **Step 4: Run** `swift test` and the UI suite — Expected: green.
- [ ] **Step 5: Commit** `git commit -m "M8 device run: results and tuned numbers"`
