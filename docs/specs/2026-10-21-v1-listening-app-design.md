# V1 design: the listening app

Status: draft for review · 2026-10-21 · Style: ASD-STE100 where it is technical. Each section ends with the principle(s) it serves (P1 to P8 in `docs/PRINCIPLES.md`).

## 1. Intent

V1 is one iPhone and one life: the owner's. The owner opens the app, talks, and a timeline fills in. The app listens, transcribes, extracts memories, places them with honest uncertainty, and lands every session. It does not speak back yet.

The reason to build this first is calibration. The recording study was deferred (see decision in §12). The owner's own sessions replace it: real speech, real pauses, real extraction failures. So V1 must keep raw audio and transcripts as the source of truth and must be able to re-run extraction over old sessions with a new prompt. That rule shapes the data model and the pipeline more than any screen does.

**Who decided what.** The owner decided: iPhone app; listen-only for V1; no separate server for V1; Anthropic Console API as the model provider; the recording study runs after V1 exists; everything must leave the door open to the full voice interviewer. The builder (Claude) proposed the iOS internals in §5, the data model in §6, the extraction and resolution design in §7 and §8, and the milestones in §11. Those are proposals; the owner redlines them.

## 2. Goals, non-goals, anti-goals

**Goals**

1. Record a 30 to 60 minute session on an iPhone with the screen off.
2. Transcribe on-device with word timestamps. Keep the audio.
3. After each completed thought, extract candidate memories, people, places and time anchors, and show them as one-tap cards.
4. Resolve names to people once; the link holds across memories.
5. Place memories as ranges, never points. Show inferred values as guesses.
6. End every session with a summary in the owner's words and a keep / private / let go choice.
7. Show the timeline: chapters, ranges, the shelf for unplaced memories. Play a memory's own audio.
8. Re-run extraction and resolution over any past session from the command line, without the phone.

**Non-goals for V1** (designed for, not built)

- Spoken replies, acknowledgements, text-to-speech.
- The end-of-thought classifier model. V1 uses a silence threshold.
- Reflections and interviewer questions during the session.
- Photos, music, family sharing, web viewer.
- Chapter replay as narrated story (V1 plays memories one at a time).
- Detection of crying or other acoustic distress signals.
- Memory kinds and domains (fact, feeling, goal, event; relationships, health, education, travel). See §6, "Later: kinds and domains".

**Anti-goals** (V1 fails if it does these, even if it works)

- Shows an inferred date, name or place as a fact.
- Fills in a detail the owner did not say.
- Asks a form-style question for a baseline fact during a session. The optional "About you" screen at first open is the one place for typed facts (owner's decision, 2026-10-21).
- Ends a session without the landing.
- Keeps audio the owner chose to let go.
- Sends audio off the device.

## 3. The owner's experience

**First open.** A short, optional "About you" screen comes first: name, birthday, where you grew up, and a free-text box ("Anything useful for me to know?"). Every field can be skipped. Everything on it can be edited later in Settings. Then one question on screen: "Tell me about the house you grew up in." A mic button. Three alternate prompts in small type. No sign-up. (Onboard1.) The owner decided this on 2026-10-21: the start is the easy place to give context, and typed context there is welcome when it is useful.

**Session.** The owner talks. The screen shows the live transcript, large and calm. The phone can lock; recording continues. When a thought ends (a pause past the threshold), the segment goes to the extractor. Candidates arrive as cards under the transcript: "Sounds like a memory," a title in the owner's words, a fuzzy time in ochre, people chips. One tap adds it. A swipe dismisses it. Names the app does not know become "Who's this?" cards. The owner can ignore every card and keep talking; cards queue. (Main, Onboard2.)

**Landing.** At the configured time (default 40 minutes) or when the owner taps "Let's leave it there," the session ends. The app shows a summary built from the confirmed and pending memories, quoting the owner's phrases. Each memory gets keep / private / let go. Let go deletes that memory's audio span and transcript. One light forward-looking line closes the screen ("Next time, if you like: the pomegranate tree."). (Onboard3, WindDown.)

**Timeline.** Chapters as structure (the owner titles them, or they are untitled spans). Memories with ranges rendered as bands. Collections group related memories and derive a span. The shelf holds memories with neither a date nor a collection. (Timeline, FuzzyA, FuzzyC.)

**Memory.** The owner's audio for that memory, the transcript span, people and place chips, the range with its evidence ("you said: the summer after graduation"). Tapping the range offers the one relative question the resolver wants, as a card with two or three taps, never a date picker. (Event, Refine.)

**People.** The queue of unresolved mentions and the resolved list with aliases. Resolve to an existing person, a new person, or "not a person." (People.)

Serves P1, P2, P5, P8.

## 4. Architecture

```
┌──────────────────────── iPhone ────────────────────────┐
│  App (SwiftUI)                                          │
│   ├─ Session screen ── SessionController                │
│   ├─ Timeline / Memory / People screens                 │
│   └─ Composition root (wires implementations)          │
│                                                          │
│  LifelineKit (Swift package, also builds on macOS)      │
│   ├─ Voice       VoiceSession protocol, ListenOnlyVoiceSession
│   ├─ Store       SQLite (GRDB), migrations, repositories │
│   ├─ Domain      Memory, Person, TimeRange, Anchor, …    │
│   ├─ Extraction  ExtractionService protocol,            │
│   │              AnthropicExtractionService, prompts,    │
│   │              output schema, ContextPacketBuilder     │
│   ├─ Resolution  Resolver, CuriosityList                 │
│   ├─ Arc         SessionArc (stages, signals, landing),  │
│   │              FixedResponses                          │
│   └─ CLI         `lifeline` macOS executable: import,    │
│                  extract, resolve, eval                  │
└──────────────────────────────────────────────────────────┘
            │ HTTPS, text only, no audio
            ▼
   Anthropic Messages API (stateless by nature)
```

Rules:

- The App target must contain only views, view models and the composition root. All logic lives in LifelineKit so the CLI and tests can use it.
- LifelineKit must compile for iOS and macOS. Platform-specific code (speech, audio capture) sits behind protocols with `#if os(iOS)` implementations.
- The app must talk to the model only through `ExtractionService`. Swapping to a server later means one new conformer and one line in the composition root.
- No module may import the Anthropic client except `Extraction`.

Serves P5 (uncertainty is a domain type, not a UI trick) and the data posture.

## 5. iOS internals (builder's proposals; owner to redline)

| Choice | Proposal | Why | Alternative |
| --- | --- | --- | --- |
| Minimum iOS | iOS 26 | `SpeechAnalyzer` / `SpeechTranscriber` (Speech framework, iOS 26) gives on-device transcription with per-result audio time ranges and no 1-minute cap. The owner's phone runs it. | iOS 18 with `SFSpeechRecognizer` (`requiresOnDeviceRecognition`): works, but has session limits and weaker timestamps |
| Audio capture | `AVAudioEngine` input tap → two consumers: the transcriber's async input stream and an `AVAudioFile` writer (m4a, AAC, 24 kHz mono) | One tap, one source of truth, file and transcript share a clock | `AVAudioRecorder` plus a separate recognizer tap: two clocks to reconcile |
| Background | `UIBackgroundModes: audio`; `AVAudioSession` category `.record`, mode `.spokenAudio`; handle interruptions and route changes by pausing the segment and resuming | Screen-off recording is the reason the app is native | — |
| Silence detection | RMS energy threshold on the input tap, debounced; segment ends after `pauseThreshold` (default 1.8 s) of silence following at least `minSegmentSpeech` (default 3 s) of speech | Cheap, on-device, tunable; the pause distribution it logs calibrates the later end-of-thought model | Apple `VoiceActivityDetector` is not public; a Core ML VAD can replace the energy gate behind the same protocol |
| Word timestamps | `SpeechTranscriber` results with `audioTimeRange`; store per-run `AttributedString` runs as word rows with start/end ms | Replay highlighting and let-go deletion need word-level spans | — |
| Storage | SQLite via GRDB.swift. Explicit schema, migrations in code, `ValueObservation` for SwiftUI | The data model is relational with typed edges and derived spans; GRDB keeps the schema visible and the CLI can open the same file | SwiftData: faster to start, schema less explicit, awkward for the CLI and for raw SQL on ranges |
| App architecture | SwiftUI + `@Observable` view models, one per screen; dependencies injected via a `Dependencies` struct from the composition root | Small app, testable, no framework | TCA: more structure than V1 needs |
| Concurrency | Swift 6 strict concurrency. `VoiceSession` is an actor emitting an `AsyncStream<VoiceEvent>`. Extraction runs on a background task queue per session, serialized, so candidates arrive in order | Matches the event-driven interface in the technical design | — |
| Model client | `URLSession` raw HTTP to the Messages API (no official Swift SDK). `Codable` request/response types, structured outputs via `output_config.format` with the extractor JSON schema | Smallest dependency; schema-validated output | Community Swift SDKs: unvetted |
| API key | `Secrets.xcconfig` (gitignored) → `Info.plist` at build → copied into Keychain on first launch and read from there | Simple for one developer; nothing in source | — |
| Audio location | `Application Support/Lifeline/audio/<sessionID>.m4a`, excluded from iCloud backup by default (owner can enable) | Hours of audio should not surprise a backup | — |
| Deletion | Let-go cuts the audio span out of the session file (rewrite via `AVAssetExportSession` with a time-range composition) and deletes the word rows; a tombstone records that a span was removed, with no content | "Let go" must mean gone, not hidden | Keep whole-file, mark hidden: violates the anti-goal |

Serves P5, P8, and the data posture.

## 6. Data model

SQLite. All IDs are UUID strings. All times are ISO-8601 UTC. All audio offsets are integer milliseconds from the start of the session file.

| Table | Key columns | Notes |
| --- | --- | --- |
| `session` | id, started_at, ended_at, audio_path, stage_log (JSON), landing_choice_made | One per recording |
| `segment` | id, session_id, index, start_ms, end_ms, text, status (`pending`/`extracted`/`failed`) | One completed thought |
| `word` | segment_id, index, text, start_ms, end_ms | From the transcriber |
| `candidate` | id, segment_id, extractor_version, kind (`memory`/`person`/`place`/`anchor`/`flag`), payload (JSON), confidence, status (`pending`/`accepted`/`dismissed`/`superseded`) | Raw extractor output; never edited, only re-generated |
| `memory` | id, title, summary_quote, time_range (see below), visibility (`timeline`/`private`), chapter_id?, created_from_candidate_id | The confirmed thing on the timeline |
| `memory_span` | memory_id, segment_id, start_ms, end_ms, order | A memory can span several segments; the first span is the primary. `same_as_memory_id` from the extractor adds a span here (builder's call) |
| `memory_person` | memory_id, person_id, role_text | `role_text` is the owner's phrase ("my sister") |
| `memory_place` | memory_id, place_id | |
| `person` | id, display_name, notes, is_owner, birth_date?, birth_date_origin? (`stated`/`typed`) | Exactly one row has `is_owner = true`. `contact_identifier` is deferred; no Contacts framework in V1 (builder's call) |
| `profile` | id (singleton), display_name?, birth_date?, birth_place_text?, free_text?, updated_at | The "About you" screen. Typed by the owner, origin `typed`. Mirrored onto the owner's `person` row. `free_text` goes into the fixed part of the context packet (§7) |
| `alias` | person_id, text | "Maya", "my sister", "Mai" |
| `mention` | id, segment_id, text, status (`unresolved`/`resolved`/`not_a_person`), person_id? | The "who's this?" queue |
| `place` | id, name_text, lat?, lon? | Name is the owner's phrase |
| `chapter` | id, title, time_range, order | Titled by the owner; may be untitled |
| `collection` | id, title | Span is derived from members |
| `collection_memory` | collection_id, memory_id | |
| `anchor` | id, memory_id, phrase, relation (`before`/`after`/`during`/`same_year_as`/`age`/`absolute`), target_kind (`memory`/`person_birth`/`chapter`/`public_event`/`none`), target_id?, value (JSON), resolved | A typed edge from a memory to what it is relative to |
| `curiosity_item` | id, kind (`unresolved_anchor`/`unexplained_person`/`place_without_story`/`dropped_thread`), text, payoff_count, status, source_memory_id? | What the interviewer would ask next |
| `tombstone` | id, session_id, start_ms, end_ms, removed_at | A span was let go; no content |

**Time range** (embedded columns on `memory` and `chapter`): `earliest`, `latest`, `likely_start`, `likely_end` (all `YYYY-MM-DD` or null), `granularity` (`day`/`month`/`season`/`year`/`decade`/`era`), `origin` (`stated`/`inferred`/`derived`/`confirmed`), `evidence_text` (the owner's phrase that set it). A memory with all four dates null is unplaced and goes to the shelf unless it is in a collection.

**Later: kinds and domains** (owner's direction, 2026-10-21, not built in V1). A later version will sub-divide memories two ways: by *kind* (a fact, a feeling, a goal or intention, an event, or another kind) and by *domain* (relationships, health, education, travel, work, and more). V1 does not add these columns. V1 keeps the seam open in three ways. First, `candidate.payload` is JSON, so a later extractor version can emit `kind` and `domain` and a re-run can back-fill every past session. Second, nothing in V1 code or copy may assume a memory is an event; the words "memory" and "moment" are used, not "event". Third, `collection_hint` and `chapter_hint` stay free text, not an enum, so the later taxonomy can absorb them. The taxonomy itself is a later design.

**Private memories** (builder's call): visible only under a Private filter on the timeline; excluded from the context packet, from summaries sent to the model, and from any export except the owner's full backup.

**Invariants**

- `memory` must have at least one `memory_span`. Let-go deletes every span of the memory, then the memory.
- `candidate` rows are immutable. A new extractor version writes new rows; old rows become `superseded` only when the owner has not acted on them.
- Nothing in `memory`, `person` or `place` may contain text the owner did not say or type, except `title`, which the extractor proposes and the owner accepts by tapping.
- `origin = inferred` must render as a guess in every view.

Serves P1, P5, P8.

## 7. Extraction

**When.** After each segment closes. The app sends the segment text and a context packet. Requests are serialized per session so candidate ordering is stable. If a request fails, the segment stays `pending` and is retried at session end and by the CLI.

**Context packet** (built on device; selects, never dumps):

- the previous two segments' text (rolling window, about 2 minutes), for cross-segment context,
- people: names and aliases (cap 50),
- chapters: titles and ranges,
- memories from this session so far: titles and ranges (so the extractor can say "same memory as M3" instead of duplicating),
- open curiosity items (cap 10),
- session stage.

**Output schema** (structured output, strict):

```
{
  memories:  [{ ref, title, quote, segment_span: {start_word, end_word},
                people_refs: [string], place_text?: string,
                anchors: [{ phrase, relation, target_text?, value? }],
                same_as_memory_id?: string, collection_hint?: string,
                chapter_hint?: string, confidence }],
  mentions:  [{ text, kind: person|place, likely_alias_of_person_id?, confidence }],
  flags:     { serious_disclosure: bool, wants_to_stop: bool, wants_to_change_subject: bool }
}
```

Every field that carries content must be a span or a quote from the segment. `title` is the one composed field, and the prompt constrains it to the owner's own words (max 8 words, prefer a phrase from the text).

**Prompt rules** (the prompt file is `Extraction/Prompts/extractor.v1.md`, versioned; the version string is stored with each candidate):

- Extract only what is said. Never infer a year from a general fact. "I was in third grade" yields an `age` anchor, not a year.
- A summary ("we went every summer") is a `collection_hint`, not a memory, unless one instance is told. A named era ("the Boston years") is a `chapter_hint`.
- Collections and chapters are created two ways in V1 (builder's call): the owner accepts a hint card, or the owner creates one from the timeline (long-press a memory → "new chapter" / "add to collection"; a chapter's range is set from its members until the owner drags its edges). There are no auto-derived chapters. M3 includes this editing UI.
- Mark confidence honestly; the UI hides nothing below a threshold but renders low confidence more faintly.
- Return `flags.serious_disclosure` for abuse, danger to self or others, or similar. The model classifies; the app's response is fixed text (§9).

**Model call.** Model `claude-opus-5-5`, adaptive thinking with `output_config.effort: "low"` (extraction is short; raise if quality demands), structured output with the schema above, `fallbacks: "default"` with the server-side fallback beta so a refusal still returns a result, prompt caching with one breakpoint after the fixed system prompt. Max tokens 4096. The model name and effort are configuration, not code.

**Idempotency.** `(segment_id, extractor_version)` is unique. Re-running a version is a no-op; running a new version appends. Accepted memories keep their `created_from_candidate_id` and are never silently changed by a re-run; the re-run can only add new pending cards.

Serves P1, P2, P5.

## 8. Resolution

The resolver runs on device after each extraction and in the CLI. Input: anchors. Output: time ranges, floating memories, curiosity items.

Algorithm (per memory, in order):

1. **Absolute.** `absolute` anchor with a stated date, season or year → set range at the stated granularity, `origin = stated`.
2. **Age.** `age` anchor and a known birth date → range from birth + age (one-year band, or the school-year band for grade phrases), `origin = inferred`. The owner's birth date comes from the "About you" screen at first open (origin `typed`, editable in Settings) or from speech (the extractor emits a `birth` fact when the owner states it; origin `stated`). A stated date and a typed date that disagree show a "which is right?" card; the app never picks silently. No birth date → the memory floats; the resolver waits. (Owner decided 2026-10-21.)
3. **Relative to a placed memory or chapter.** `before` / `after` / `during` / `same_year_as` with a resolved target → derive the band from the target's range (after X: earliest = X.earliest, latest = X.latest + span cap for the relation). `origin = inferred`.
4. **Relative to an unplaced target.** Create a floating memory for the target if none exists (title = the phrase), link the anchor, and add a curiosity item of kind `unresolved_anchor` with `payoff_count` = number of memories that would be placed if the target were. The UI shows the payoff ("placing this would place 4 memories").
5. **Collection membership.** A memory in a collection with no range of its own renders inside the collection's derived span, still marked unplaced.

Rules:

- The resolver must never ask for a date. It may generate one relative question per anchor, phrased as a choice between things the owner said.
- A confirmed range (`origin = confirmed`) is never overwritten by the resolver.
- Re-running the resolver over all memories must produce the same result as incremental runs (pure function of anchors + confirmed ranges).

Serves P2, P4, P5.

## 9. Session arc and safety (V1 scope)

Stages: `open` → `middle` → `windDown` → `ended`. The controller holds elapsed time and the stage log.

- `windDownAt` default 40 minutes, `hardStopAt` 60 minutes. Configuration, not code. At `windDownAt` the session enters `windDown`: recording and extraction continue, a "Let's leave it there" banner appears, and no new curiosity prompts are shown. The summary screen opens when the owner taps the banner or at `hardStopAt`, whichever is first; capture stops when the summary opens (builder's call).
- **Early landing signals in V1**: the owner taps "Let's leave it there"; the extractor returns `wants_to_stop`; the extractor returns `serious_disclosure`. A `wants_to_change_subject` flag does not land the session; in V1 it only drops any pending curiosity cards from the current topic.
- **Serious disclosure**: the app stops showing new memory cards, shows one pre-written card (`Arc/FixedResponses/disclosure.md`: short, warm, one offer of help with a crisis line for the owner's locale, no insistence), and moves to wind-down. The owner approves the wording and the line before M4 (see §14). The text is a resource in the bundle with a unit test asserting it is shown verbatim. The model never writes it.
- **Wind-down screen**: summary list of this session's memories (accepted and pending), each quoting the owner, each with keep / private / let go. Default is keep; keep on a pending candidate accepts it. Let go on a pending candidate dismisses it and deletes its span. Let go on an accepted memory deletes per §5.
- **Pending cards after a session** (builder's call): any candidate still pending, including new cards from a later extractor version, appears in a "Waiting for you" section at the top of the timeline until acted on. It is the same card component as in the session. One closing line built from the top curiosity item, or a neutral line if the session was flagged heavy (decision log, Open: closing question).
- The session must not end without the wind-down screen, except on a crash; on next launch the app resumes an un-landed session straight to its wind-down with whatever was captured.

Serves P6, P8.

## 10. CLI and testing

The `lifeline` macOS executable in LifelineKit, pointing at an exported session bundle or a folder of fixture transcripts. Round trip (builder's call): the app exports a bundle (SQLite copy plus audio) through the share sheet for the CLI; nothing flows back. Reprocessing the owner's real sessions on the phone is an in-app action ("Re-run extractor" in Settings) that uses the same code; the CLI is for evaluation and prompt work.

- `lifeline import <transcript.json>`: load an invented or consented transcript as a session.
- `lifeline extract --session <id> [--version v2]`: run the extractor; print candidates as a table.
- `lifeline resolve --all`: re-run the resolver; diff against the current ranges.
- `lifeline eval <fixtures/>`: run extraction over fixture transcripts with hand-labeled expected candidates and print precision, invented-detail count and anchor coverage. This is the recording study's scoring, ready for when it runs.

Tests:

- Unit: TimeRange arithmetic, resolver (pure), context packet selection and caps, schema decoding, fixed-response verbatim, let-go span deletion on a synthetic audio file.
- Integration (macOS, needs key, opt-in): extractor over three invented fixtures, asserting no field contains text absent from the transcript.
- UI (iOS): wind-down flow reachable from every stage; resume-to-wind-down after simulated crash.

Fixtures are invented. No real person's data in the repo.

## 11. Milestones

Each milestone is usable on the owner's phone.

| # | Deliverable | Done when |
| --- | --- | --- |
| M1 | Record, transcribe, store, play back | A 30-minute screen-off session produces a session row, segments with words, and an audio file; a memory-less timeline shows the session; tapping a segment plays it |
| M2 | Extract and confirm | Cards appear during a session; tapping creates memories and people; "who's this?" works; CLI `extract` runs on an exported session |
| M3 | Place | Resolver sets ranges; timeline renders bands, collections and the shelf; the relative-question card narrows a range; curiosity items show payoff |
| M4 | Land | Timer and button wind-down; summary; keep / private / let go with real deletion; fixed disclosure response; crash-resume |
| M5 | Reprocess and tune | In-app re-run with a new extractor version adds new pending cards without touching accepted memories; export bundle opens in the CLI; `eval` runs on fixtures; first owner-driven prompt revision logged |

M1 before M2 is deliberate: the owner starts recording real sessions on day one, and every later milestone re-runs over them.

## 12. Decisions made in this design (to add to `docs/DECISIONS.md`)

1. **Recording study deferred** until after V1 is usable; the owner's own sessions calibrate the extractor first; the `eval` command keeps the study's scoring ready.
2. **V1 is listen-only.** No TTS, no interviewer turns. `VoiceSession` ships as `ListenOnlyVoiceSession`; `say`, `acknowledge`, `interrupt` are no-ops that log.
3. **No separate server in V1.** The app calls the Anthropic Messages API directly through `ExtractionService`. Supersedes the open "server language" item: when a server is needed, it is LifelineKit compiled as a Swift server executable.
4. **Model provider: Anthropic Console API**, billed by key. The Max subscription does not cover API calls. Default model `claude-opus-5-5`, configurable.
5. **First user: the owner,** telling their own life. "Hand the phone over" is not in V1.
6. **Typed context at the start is allowed.** An optional "About you" screen at first open takes name, birthday, birthplace and free text. Typed values carry origin `typed`. This is the one exception to "no form-style questions"; mid-session the rule holds.
7. **Memory kinds and domains are a later design.** V1 ships with one memory type and keeps the seam open (§6).

## 13. Left to the builder

- Exact GRDB schema DDL and migration naming.
- Energy-gate parameters and debounce; log the pause distribution to a local file for later calibration.
- The extractor prompt wording (v1), within the rules in §7.
- Card and timeline visual implementation from `docs/design/*.dc.html` (palette and type are specified there).
- How the summary screen orders memories (proposal: session order).
- Xcode project layout (one workspace, app target, LifelineKit as a local package).

## 14. Open questions for the owner

1. ~~Birth date.~~ Resolved 2026-10-21: it comes from the "About you" screen at first open. See §3, §8 and decision 6.
2. Disclosure card. When the owner says something that signals serious harm (for example, past abuse, or thoughts of self-harm), the app must show a fixed, pre-written card and must not improvise a reply (principle 6; CLAUDE.md non-negotiable 4). The builder needs two things from the owner before M4: approval of the card's words, and the crisis line the card shows, which depends on the owner's country. Proposed draft, US: "Thank you for telling me that. You can stop here, or keep going. It is your choice. If you need to talk to someone now, call or text 988 (Suicide and Crisis Lifeline, US)."

## 15. Revisions after the design review (2026-10-22)

An external review of this spec, the M1 to M4 plans, the canvases and the Swift code found one theme: the combination of confirmation cards, people resolution, date refinement and session review could make the owner feel responsible for maintaining a database. The decisions below are recorded in `docs/DECISIONS.md` (entries dated 2026-10-22) and drawn as canvases R1 to R9. They change this spec as follows.

| Section | Change |
| --- | --- |
| §2 Goals 1, 6 | Two session lengths: a quick story (a few minutes) and settling in. Goal 6 becomes: end every session with a light landing; per-memory choices are optional and can happen later. |
| §3 First open | Two equally valid ways in; the optional About You screen stays but is secondary ("Add a little context"). The first payoff is the owner's own voice played back, minutes in. |
| §3 Session | Two views. Listen (default): prompt, status, pause, finish, a small "N possible memories" count that never scrolls the screen. Transcript & memories: the review view, opened by choice. The session works with zero card taps. |
| §3 Landing | "Your recording is saved. A few moments from today. Done for now · Review these moments." No required per-memory decision. Hide and delete one tap away. Neutral closing line after a heavy session. The copy "nothing is saved until you say so" is removed. |
| §5 Deletion | Deletion must handle overlapping memories that reference the same audio and preserve playback offsets. |
| §6 Data model | Add `story` and `story_moment`. `memory` is the moment. Chapters may overlap. `visibility` becomes two flags: `hidden_from_timeline`, `excluded_from_ai`. |
| §7 Extraction | Reconcile related segments before presenting cards. Budget the context packet by tokens and relevance. Pending candidates count as context. `same_as_memory_id` becomes `story_ref`. |
| §7 UI rule | Low confidence is a "Check this" label, never reduced opacity. |
| §9 Arc | `hardStopAt` becomes a wrap-up offer with an explicit "keep going", not a stop. During a heavy moment, suppress every organizational prompt including "who's this?". The disclosure flag distinguishes narration of the past from present danger. |
| §9 Wind-down | Replaced by the light landing above. Keep / private / let go moves to the review view and the privacy controls: Hide from timeline, Exclude from AI processing, Share…, Delete…. Local-only is chosen before recording. |
| §9 Stop | `stop` must not wait for the extraction hook. Persist, show the landing, finish sorting in the background with durable retries. |
| Cards | `MemoryCard`: Keep / Change… / Dismiss (with Undo; recording untouched). Keeping does not confirm inferred details. `FlowChips` must wrap. Visible alternatives to swipe and long-press. |
| §11 Milestones | M4 absorbs the landing and correction changes. M5 adds stories, the privacy controls and backup/restore. A minimal photo prompt (one photo, one story) follows as Phase 1.5. |

Serves P1, P5, P8 and the new P9 (preserve first, organize later).
