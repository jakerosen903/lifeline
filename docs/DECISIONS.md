# Decision log

One entry per decision. Newest first. Status is Decided, Open, or Superseded.

## 2026-10-21 · Platform: iOS native app + stateless server; web viewer deferred

**Status:** Decided.

**Decision.** The capture app is native iOS (Swift/SwiftUI). The interviewer and extractor run as a stateless server. A read-only web viewer for replay and sharing is deferred to Phase 3.

**Why.** Long sessions (30 to 60 minutes) happen with the screen off; iOS Safari and PWAs suspend audio capture in that state. On-device speech-to-text with word timestamps exists on iOS and does not in the browser. Hours of audio in browser storage is fragile (quotas, Safari eviction). Phase 2 props (PhotoKit, Vision, Core ML) are native only. Web wins for viewing and sharing, which is Phase 3's surface.

**Alternatives considered.** Web app or PWA (fails on background recording and storage). React Native/Expo with native modules (saves some Swift but still needs native audio and speech plumbing; adds a layer between us and the parts that matter most).

**Consequences.** V1 is iPhone only. The server is platform-agnostic, so extraction and resolver work can start in Python against voice memos before any Swift exists.

## 2026-10-21 · Voice pipeline: cascade behind a `VoiceSession` interface

**Status:** Decided.

**Decision.** V1 uses VAD → streaming STT → text-model interviewer → TTS. A `VoiceSession` interface (events: speechStarted, transcriptPartial, transcriptFinal, userPaused; commands: say, acknowledge, interrupt) hides the implementation so a realtime speech model can replace the cascade later.

**Why.** Cheaper per minute; the transcript is a first-class artifact we need anyway; turn-taking logic stays in our code. What we give up (prosody awareness, low-latency backchannels, barge-in) is the case for the later swap.

**Turn policy (initial values, for testing).** A ~1 s silence triggers a fast end-of-thought check. Complete thought: reply after a 1 to 2 s grace. Unfinished: wait up to 6 to 8 s, then a soft acknowledgement only. The classifier runs on-device or under ~300 ms.

## 2026-10-21 · Data posture (V1)

**Status:** Decided for V1; revisit before any release beyond family.

**Decision.** Audio, transcripts, timeline and people stay on the device. The server is stateless: it receives a transcript segment plus a context packet and returns a result, and persists nothing. Sharing is explicit. A memory the person chooses to "let go" is deleted with its audio.

**Open for later.** On-device vs server LLM; end-to-end encryption for shared bundles; ownership after death.

## 2026-10-21 · Photos in V1: manual tagging, no face model

**Status:** Decided.

**Decision.** The person picks favorite photos; the app reads EXIF date and location and derives clusters; the person names who is in each photo ("who's this?"). No face embedding model in V1.

**Why.** PhotoKit does not expose People, Memories or Trips. Apple's face-identity request is private API. Cross-age face matching (childhood prints to adult photos) is where off-the-shelf embeddings are weakest. Manual tags build the labeled set needed to evaluate a model later.

## 2026-10-21 · Phase order

**Status:** Decided.

Phase 1 personal timeline → Phase 2 props (photos, then music) → Phase 3 family sharing.

## 2026-10-21 · V1 scope: listen-only app, no server, recording study deferred

**Status:** Decided. Design: `docs/specs/2026-10-21-v1-listening-app-design.md`.

**Decision.** V1 is a listen-only iPhone app. It records, transcribes on the device, extracts candidate memories, places them as ranges, and lands every session. It does not speak. `VoiceSession` ships as `ListenOnlyVoiceSession`; `say`, `acknowledge` and `interrupt` are no-ops that log. The first user is the owner, telling their own life. "Hand the phone over" is not in V1.

**Why.** The owner wants to record real sessions on their own phone as soon as possible. Real sessions calibrate the extractor better than a study does. Every interface keeps the full voice interviewer reachable.

**Consequences.** The recording study (`docs/experiments/recording-study.md`) runs after V1 is usable. The `eval` command keeps its scoring ready. Closes "Open · First user".

## 2026-10-21 · No separate server in V1; LifelineKit is the later server

**Status:** Decided. Supersedes "Open · Server language".

**Decision.** The app calls the Anthropic Messages API directly through an `ExtractionService` protocol. Domain, store, extraction, resolution and session-arc code live in a Swift package, `LifelineKit`, that compiles for iOS and macOS. A `lifeline` macOS CLI runs extraction and resolution over exported sessions. When a server is needed, it is LifelineKit compiled as a Swift server executable, and the app switches to a `RemoteExtractionService` conformer.

**Why.** One language, one package, no second runtime to keep in step. Switching to a server later is one conformer and one line in the composition root. The data posture holds: audio never leaves the device; only transcript segments and a context packet go to the model.

## 2026-10-21 · Model provider: Anthropic Console API

**Status:** Decided.

**Decision.** Extraction calls the Anthropic Messages API with an API key, billed to the Console. Default model `claude-opus-5-5`, adaptive thinking at low effort, structured output. Model and effort are configuration.

**Why.** A Claude Max subscription does not cover API calls. The Agent SDK bridge was rejected as too heavy for one extraction call per segment.

## 2026-10-21 · Typed context at the start is allowed

**Status:** Decided.

**Decision.** An optional "About you" screen at first open takes name, birthday, birthplace and free text. Every field can be skipped. Everything is editable in Settings. Typed values carry origin `typed`. The free text goes into the fixed part of the extractor's context packet.

**Why.** The start is the easy place to give context, and the owner wants that to be easy when the context is useful. A birth date lets age anchors resolve from the first session.

**Consequences.** This is the one exception to "no form-style questions for baseline facts". In a session the rule holds. A stated date that disagrees with a typed date shows a "which is right?" card; the app never picks silently.

## 2026-10-21 · Disclosure card text (V1)

**Status:** Decided for V1; the owner may revise the words at any time.

**Decision.** On a `serious_disclosure` flag the app shows this fixed card and nothing improvised: "Thank you for telling me that. You can stop here, or keep going. It is your choice. If you need to talk to someone now, call or text 988 (Suicide and Crisis Lifeline, US)." The crisis line is a locale-keyed configuration value; V1 ships the US line only.

## Open · Memory kinds and domains

A later version will sub-divide memories by kind (fact, feeling, goal or intention, event, other) and by domain (relationships, health, education, travel, work, more). V1 ships one memory type and keeps the seam open: the candidate payload is JSON so a new extractor version can back-fill, no V1 code or copy assumes a memory is an event, and collection and chapter hints stay free text. Design after V1 has real sessions.

## Open · First user (closed 2026-10-21, see V1 scope)

Is the first user the person telling their own life, or an adult child interviewing a parent? Changes whose timeline a session writes to and whether "hand the phone over" is in V1. Default for now: the person's own life; design the session so handing over is a small change.

## Open · Server language (closed 2026-10-21, see No separate server in V1)

TypeScript or Python. Python is the natural home for the recording experiment and extraction prototypes; TypeScript matches the owner's web background. Decide when the server is created; the experiment can start in Python regardless.

## Open · How much the app may write

Verbatim quotes assembled into chapters, or prose the app composes in the person's style? The principles favor verbatim; replay narration may need light stitching. Decide with real transcripts in hand.

## Open · Closing question after a hard session

Unrelated by default, or tied gently to the memory? Decide after the recording study.
