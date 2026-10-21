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

## Open · First user

Is the first user the person telling their own life, or an adult child interviewing a parent? Changes whose timeline a session writes to and whether "hand the phone over" is in V1. Default for now: the person's own life; design the session so handing over is a small change.

## Open · Server language

TypeScript or Python. Python is the natural home for the recording experiment and extraction prototypes; TypeScript matches the owner's web background. Decide when the server is created; the experiment can start in Python regardless.

## Open · How much the app may write

Verbatim quotes assembled into chapters, or prose the app composes in the person's style? The principles favor verbatim; replay narration may need light stitching. Decide with real transcripts in hand.

## Open · Closing question after a hard session

Unrelated by default, or tied gently to the memory? Decide after the recording study.
