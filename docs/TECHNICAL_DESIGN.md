# Technical design (in progress)

Style: ASD-STE100. Short sentences. Active voice. "Must" for requirements. Fill each section as it is designed. Each section ends with the principle(s) it serves.

## 1. Scope

V1 is a personal timeline for one person on one iPhone. The system has an iOS app and a stateless server. The web viewer is out of scope for V1.

## 2. Components

| Component | Runs on | Responsibility | Status |
| --- | --- | --- | --- |
| VoiceSession | device | Audio capture, VAD, streaming STT, TTS, behind one interface | To design |
| Turn policy | device | Decides when the interviewer speaks; end-of-thought check | To design |
| Session controller | device | Elapsed time, stage (open / middle / wind-down), early wind-down signals | To design |
| Device memory | device | Audio files, transcripts with word timestamps, timeline store, people, curiosity list | To design |
| Context packet builder | device | Selects the slice of memory a turn needs | To design |
| Interviewer | server | Text model: reflections, acknowledgements, rare questions | To design |
| Extractor | server | Text model: candidate events, people, places, time anchors | To design |
| Resolver | device | Turns anchors into ranges; creates floating events; feeds the curiosity list | To design |
| Timeline UI | device | Chapters, fuzzy ranges, people resolution, replay, wind-down | Designed (docs/design) |

## 3. Interfaces

### 3.1 VoiceSession

Events the session sends: `speechStarted`, `transcriptPartial(text)`, `transcriptFinal(segment)`, `userPaused(ms)`.
Commands the session accepts: `say(text)`, `acknowledge()`, `interrupt()`.
A `segment` has: text, start time, end time, word timestamps, audio file reference.

The app must not know which implementation is active. Implementations: `CascadeVoiceSession` (V1), `RealtimeVoiceSession` (later).

### 3.2 Server API

`POST /turn` — input: segment text, pause length, session stage, context packet. Output: one of `none`, `acknowledge`, `say(text)`.
`POST /extract` — input: segment text with timestamps, context packet. Output: candidates with confidence.
The server must not store any request or response.

### 3.3 Context packet

Fields: people (names and aliases), chapters (titles and spans), recent memories (titles, ranges), curiosity list (open items), session stage. Size cap: TBD. The builder must select, not dump.

## 4. Data model

See `docs/OVERVIEW.md`, "6. Data model". To specify here: table definitions, the time-range representation (`earliest`, `latest`, `likely`, granularity), relative anchors as a table of typed edges, visibility per event, and the source pointer (audio file, start ms, end ms).

## 5. Turn policy

Initial values from `docs/DECISIONS.md`. To specify: the end-of-thought classifier (model, inputs, latency budget), the state machine, and how the policy is configured and tested.

## 6. Session arc and safety

From `docs/PRINCIPLES.md`, "Session arc and emotional safety". To specify: the signal detectors, the fixed-response library and its tests, and the keep / private / let-go flow including audio deletion.

## 7. Extraction and resolution

To specify after the recording study (`docs/experiments/recording-study.md`): the extractor prompt and output schema, the confidence rules, the resolver algorithm for relative anchors, and the reprocessing (idempotency) guarantees.

## 8. Phase 2 props

Photos: PhotoKit limited library access; EXIF date and location; clusters by date and location; manual "who's this?" tagging. Music: ask first; era charts; optional streaming-history upload. See `docs/PRINCIPLES.md`, "Props".

## 9. Testing

To specify: fixtures from the recording study (invented or consented transcripts only), a turn-policy simulator, extractor evaluation against hand-labeled segments, and UI tests for the wind-down flow.

## 10. Open questions

See the Open entries in `docs/DECISIONS.md`.
