# Decision log

One entry per decision. Newest first. Status is Decided, Open, or Superseded.

## 2026-10-22 · Preserve first, organize later (review follow-up)

**Status:** Decided. Source: external design review of the V1 spec, M1 to M4 plans, design canvases and Swift code; mock-ups R1 to R9 on the design canvas.

**Decision.** The recording is the product; organization is optional. Finishing a session never waits for extraction: persist, show the landing, let sorting finish in the background with durable retries. Extracted memories are drafts until reviewed; accepting a memory approves its organization, not its survival. Principle 9 added to `docs/PRINCIPLES.md`.

**Consequences for M4 and later.** `stop` must not block on the extraction hook. The session screen gets two views: Listen (default; prompt, status, pause, finish, a small "N possible memories" count that never scrolls the screen) and Transcript & memories (the review view, opened by choice). The landing says "Your recording is saved", shows a few moments with play, and makes "Done for now" the default with review optional. Per-memory keep / private / let go is no longer required at landing; it moves to the review view and the privacy controls.

## 2026-10-22 · Session length: quick story or settle in; no automatic stop

**Status:** Decided.

**Decision.** Two equally valid ways in: "Tell a quick story" (a few minutes, one memory) and "Settle in" (longer, prompts on offer). The quick story is also the shape of a daily habit; the home screen invites "today's story" without streaks or counters. The 60-minute hard stop is replaced by a gentle wrap-up at the planned length and an explicit "keep going", unless a real recording limit forces a stop. `ArcConfig.hardStopAt` becomes a wrap-up prompt, not a stop.

## 2026-10-22 · Correction is a first-class action

**Status:** Decided.

**Decision.** Memory cards offer Keep · Change… · Dismiss. "Change…" offers the title, who was there, when it was, which part of the recording, and "just tell me" (spoken correction, later). Dismiss has Undo and leaves the recording untouched; deleting recording content is a separate, explicit action. Accepting a memory does not confirm its inferred details: each inferred value carries a visible "Check this" tag (ochre plus a symbol or word, never reduced opacity) until the person settles it. Supersedes "Add / Not quite" on `MemoryCard` and the low-confidence fade.

## 2026-10-22 · Archive structure: chapters → stories → moments; years as a lens

**Status:** Decided.

**Decision.** A session is when you recorded. A moment is a scene you described, with its original audio. A story connects related moments, possibly across sessions. A chapter is broader life context. Years and months are an optional chronological lens, shown only when they help (three stories in a year: show the stories; forty: offer seasons or months). Collections remain the thematic thread across chapters ("Family trips"); a moment can sit in its story and in a collection without being copied. Chapters may overlap. The person approves any composed story or chapter title. Every level has "Listen at this level": a playlist in the person's voice (life: chosen highlights; chapter: selected stories; story: its moments; moment: the audio). Narrated assembly comes later. Pinch-to-zoom is an enhancement; Life / Chapter / Year controls, tappable headings and a clear back path are the baseline.

**Fuzzy time, progressively disclosed.** List: "During the Boston years." Detail: "Probably 2011 to 2013." Editor: likely and possible bands with evidence. Undated stories look as valuable as dated ones.

**Consequences.** The data model gains `story` (id, title, chapter_id?) and `story_moment` (story_id, memory_id, order). "Memory" in code is the moment. The extractor's `same_as_memory_id` becomes "belongs to story"; segment reconciliation (below) feeds it.

## 2026-10-22 · Privacy controls named by effect; local-only is chosen before recording

**Status:** Decided.

**Decision.** Replace the single word "private" with four controls: Hide from timeline (keep recording and memory; remove from everyday browsing); Exclude from AI processing (no future processing or context use; cannot unsend); Share… (exact content and recipients); Delete… (the selected recording content and its derivatives, with confirmation). A session that must never leave the phone is chosen before recording ("Local only") and cannot be switched on afterwards. The copy "nothing is saved until you say so" is wrong and is removed everywhere; saving is continuous. A usable backup-and-restore path (audio included, explicitly) ships before anyone beyond the owner uses the app.

## 2026-10-22 · Pipeline changes from the review

**Status:** Decided; scheduled into M4/M5.

- Finish recording independently of extraction (see Preserve first).
- Separate audio segments from story boundaries: a silence threshold ends a segment; one story may span several segments. Accumulate or reconcile related segments before presenting several cards.
- Budget the context packet by tokens and relevance, not by fixed caps per table. Select relevant memories and people within a total budget.
- Treat pending (unreviewed) stories as context, so someone who never touches the screen still gets continuity and duplicate handling.
- Evaluate cheaper extraction configurations on consented sessions against invented details, fragmentation, missed memories and editing effort before choosing a default.
- Deletion must handle overlapping memories that reference the same audio and preserve playback offsets.

## 2026-10-22 · Readability and interaction fixes

**Status:** Decided.

Keep the palette, serif titles and the tree-ring icon. Do not fade uncertain memories. Pair ochre with a word or symbol. Reduce small uppercase labels and metadata on primary screens. Serif for titles and chosen quotes; a highly readable body face for transcripts. Chips must wrap (replace the `HStack` in `FlowChips`). Every swipe or long-press action has a visible alternative. Validate large text and VoiceOver before testing with older relatives.

## 2026-10-22 · Roadmap: minimal photo prompt pulled forward; playback tested early

**Status:** Decided.

Choose one photo and tell its story, with no clustering or face work, moves into Phase 1.5. Simple playback of an accepted story (the first payoff) ships before narrated chapter assembly.

## 2026-10-22 · Closing question after a hard session

**Status:** Decided (closes the open item).

Neutral by default ("Thank you. That's enough for today."). Never a question about the person or loss just discussed, and never framed as "something lighter".

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

## 2026-10-22 · API key lives in the Keychain, typed into Settings

The Anthropic Console key is entered in Settings and stored in the device Keychain (after first unlock, this device only). It is never in a build setting, an xcconfig, the repo or a log. The CLI reads `ANTHROPIC_API_KEY` from the environment instead.

Why: nothing secret in the build; the owner can rotate the key without a rebuild; the same code path serves a second phone later. Cost: a first-run setup step, and sessions before the key is added are recorded but not sorted (they are retried by the CLI or a later re-run).

## 2026-10-23 · Sessions are short by default; the timer is a backstop

The owner's sessions run a few minutes and that is the intended shape. A session ends when the owner taps "Let's leave it there". The 40-minute wind-down and 60-minute hard stop from the design become a quiet backstop: a one-line nudge at 55 minutes and the summary opening by itself at 60. No screen shows session length as a goal. The spec's `middle` stage is dropped; stages are open, windDown, ended.

Why: the design was written imagining long oral-history sittings; real use is lighter, and every session must still land. Revised the same day by the review's "no automatic stop": the planned length brings a wrap-up offer with an explicit "Keep going"; the only automatic landing is a real recording limit. See the M4 plan (revised).

## 2026-10-23 · Direction: a short daily activity that builds over time

The owner's picture of the product (2026-10-23): a few minutes a day, one story at a time, with the timeline growing over weeks rather than being filled in one long sitting. Not a milestone of its own yet. It shapes what follows: each session opens with one fresh question (M3, done); the summary ends with one line for next time (M4); the spoken interviewer, when it comes, asks for one scene and stops. No streaks, counters or reminders that turn it into a chore; the principles rule out pressure. Open: whether a gentle daily nudge belongs in V1 at all.

## Open · Memory kinds and domains

A later version will sub-divide memories by kind (fact, feeling, goal or intention, event, other) and by domain (relationships, health, education, travel, work, more). V1 ships one memory type and keeps the seam open: the candidate payload is JSON so a new extractor version can back-fill, no V1 code or copy assumes a memory is an event, and collection and chapter hints stay free text. Design after V1 has real sessions.

## Open · First user (closed 2026-10-21, see V1 scope)

Is the first user the person telling their own life, or an adult child interviewing a parent? Changes whose timeline a session writes to and whether "hand the phone over" is in V1. Default for now: the person's own life; design the session so handing over is a small change.

## Open · Server language (closed 2026-10-21, see No separate server in V1)

TypeScript or Python. Python is the natural home for the recording experiment and extraction prototypes; TypeScript matches the owner's web background. Decide when the server is created; the experiment can start in Python regardless.

## Open · How much the app may write

Verbatim quotes assembled into chapters, or prose the app composes in the person's style? The principles favor verbatim; replay narration may need light stitching. Decide with real transcripts in hand.

## Open · Closing question after a hard session (closed 2026-10-22, see above)

Unrelated by default, or tied gently to the memory? Decide after the recording study.
