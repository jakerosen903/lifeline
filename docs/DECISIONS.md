# Decision log

One entry per decision. Newest first. Status is Decided, Open, or Superseded.

## 2026-11-16 · S6a: rulings made while building the spine

**Status:** Decided by the builder. The owner can overrule each one. Source: `docs/plans/2026-11-16-timeline-spine.md`, ledger `.superpowers/sdd/2026-11-16-timeline-spine/rulings.md`.

**Decision.**

- A gap is measured from the latest end of all the moments above it, not only from the moment directly above. Example: 2000–10, then 2003, then 2012. The gap above 2012 is 2 years, not 9.
- The margin leaves out the years only when the moment above shows the same years and the same qualifier. A guess in the same year as a stated date keeps its word "around".

**Why.** A label of "9 years" across years that an earlier moment covers states something false about the person's life. A guess whose word is hidden reads as a fact (PRINCIPLES 5).

**Consequences.** Each ruling is one line in `SpineLayout` and one test. To overrule one, change the line and its test.

## 2026-11-16 · The Timeline is a spine; a chapter is a tag, a "During" line and a bar on the life map

**Status:** Decided by the owner from mock-ups. Source: `docs/specs/2026-11-16-timeline.md`. Supersedes in part "The timeline groups moments into computed life periods" (2026-10-26) and "Archive structure: chapters → stories → moments" (2026-10-22).

**Decision.** The Timeline is one spine of moments with gaps that follow the years between them. A pinned card shows the whole life as a strip, with a frame for the years on screen and a "During" line that names the chapters over those years. A moment shows one tag when the person put it in a chapter. One sheet, the life map, shows every chapter as a bar on a year axis and is where a chapter is renamed, dated or removed.

- A chapter is not a container on the Timeline. "Outside any chapter" and the chapter sections go away.
- A tag is what the person said about a moment. The "During" line and the life map go by stated years. A date overlap never makes a tag.
- A chapter shows years only when the person stated them. The span of its members is never shown as its dates.
- Periods are always computed from age. A chapter never replaces a period.

**Why.** The owner found that most moments sat outside every chapter, that empty chapters could not be removed, and that the Timeline read as a list. Marks on every row (a band or several tags) break with many chapters, because chapters overlap. One line and one map hold any number.

**Consequences.** `chapter.range` holds stated years only. The chapters in the owner's archive show under "Not placed in time yet" until the owner says when. The chapter rules in the audit data fixes spec move to S6. S6 is specified ahead of the ship order and of the two-week watch.

## 2026-11-16 · Owner's calls on the audit data fixes

**Status:** Decided by the owner, except call 4. Source: `docs/specs/2026-11-16-audit-data-fixes.md`, "Owner's calls".

- Exact duplicates (stories with one title, "Ohio." beside "Ohio") are merged once without a question, with one notice.
- The owner's typed name goes to the model provider in the context packet.
- The second read does not offer memories that v7 finds and v6 missed.
- The second read's line shows on You only.
- A chapter shows no years until the person states them.
- Build order: A1 (stories), then A2 (extractor v7) after Photos merges, then A3 (the second read).
- **Open:** whether the second read may change a memory's kind. The owner wants to see v7's output on the whole archive first.

## 2026-11-16 · You is a portrait, and About leaves the Timeline (S3)

**Status:** Decided. Builds on the five-sections decision of 2026-11-15. Source: `docs/plans/2026-11-16-sections-you.md`, decisions 2, 4, 5, 8, 17 and 18, and the rulings made while building it.

**Decision.** You shows the name and birth line, the owner's life strip, one lead line, then "Who you are", "How it felt", "What you think" and "What you're hoping for". Every line with a recording plays only its own span.

- A fact shows on You when it has a detail link to the owner, or none. A fact detailed only to someone else shows on that page. A fact about only a hidden person or thing follows it and does not show on You. The app never names a hidden entity in "about". The app does not guess who a fact is about.
- A feeling says "about {title}" from its first non-owner detail link, else its first mention link. With no link, no line shows. Feelings and facts show no date. A goal shows "said in {month}" or "said in {month} {year}", the month its session started.
- The lead comes from facts, feelings and goals with own words and a recording. It changes each time You appears, stays across a refresh, never repeats in its part, and stays while a tag chip other than "All" is selected.
- Hide and Delete... move to a long-press menu on each line. Hide shows "Hidden." with Undo for 6 seconds, because a long-press Hide is easy to trigger by mistake. Delete asks first.
- A feeling's quote opens its memory page, and "about" is a separate link, so one kind of line behaves one way.
- A play error shows in ink with a red icon, to keep 4.5:1 contrast. A missing file reads "Could not play this: the recording could not be found."
- The About list leaves the Timeline. The summary keeps "and N things about your life".
- No migration. The portrait reads in batches, reads nothing until it is on screen, and refreshes when a session closes.

**Rulings from the final review (2026-11-16).** Each ruling has its cost.

- **A line from a heavy session never leads.** A line whose first telling is in a session with a disclosure or a wish to stop is not in the lead pool. It still shows in its part, with its play control. The app reads the heavy sessions in one batch, as the landing reads one session. Why: a disclosure must not show at title size with a play button each time the person opens a tab (PRINCIPLES, session arc and safety). Cost: the check is per session, so an ordinary line from a heavy session never leads either.
- **One slot for Undo and errors.** "Hidden." with Undo, a play error, and a failed hide, delete or undo show in one slot pinned at the bottom of You, above the record bar. It replaces "under the lead". One message shows at a time, and a newer one replaces the older. Undo stays in the slot while its 6 seconds last, also when an error replaces "Hidden.". A play tap clears only an old error. It never ends Undo. A second hide, or a delete that works, can replace an open Undo. VoiceOver announces each message when it appears, also when the same text appears again. The error for a page that could not be read keeps its own place. Why: an Undo the person cannot see is no safety net. Cost: one more floating element above the record bar while it shows.
- **A stale play error goes.** The slot clears when You disappears and when a new lead is picked. Cost: none.
- **Playback stops when its line leaves the page.** Hide, Delete and a tag chip that filters the line out each stop it. Cost: none.
- **Sort order.** Facts, feelings and goals sort by when they were told (the session start), then by the start of the span, then by id. A line with no recording sorts after the others, by id. Why: one stable answer. Cost: two lines told in the same second sort by the span start, not by meaning.
- **Chips come from listed facts only.** A tag only on a hidden, floating or unlisted memory makes no chip. Why: a chip must never lead to an empty part. Cost: none.
- **"said in" uses the Gregorian calendar in English.** Only the time zone comes from the device. Why: the copy is English, and a Buddhist-calendar year in English copy reads as wrong. Cost: a person whose device uses another calendar sees Gregorian years.
- **The owner is never an "about" target.** A feeling linked to the owner and to the lake reads "about The lake". Why: "about you" on your own page says nothing. Cost: none.
- **Timeline count and tag menu.** "N things about your life" counts visible facts, feelings and goals. The tag filter and "Show hidden memories" do not change it. While a tag filter is on, the summary leaves out the "and N things" part. The tag menu offers only the tags that at least one moment carries. With a filter on and no moment that matches, the empty state shows. A Timeline tag filter turns itself off when no moment carries its tag any more. Why: Timeline must not claim content that it does not show. Cost: a tag used only on facts cannot filter the Timeline; it is a chip on You.
- **Screens built before the owner answered.** The screen tasks were built on the plan's defaults before the owner answered the plan's open questions (dates under feelings, when the lead changes, the strip as the link to the owner's page, hidden lines one way, facts about others staying on You until extractor v7). Cost: rework of the affected views and tests if the owner overrules a default.

**Why.** About held 62% of everything on one screen (audit F9), and the owner is a person too (F10). A portrait in the person's own words and voice serves P1 and P2. Showing only what the person said, with no guessed link, serves P5.

**Costs.** Most facts about other people stay on You until extractor v7 re-reads the archive and adds detail links. A fact about a hidden entity shows nowhere until the entity shows again. The lead changes less often while a person filters. No dark palette exists yet.

**Cost of Hide (read this before you hide a line).** Hide on You has no way back after its 6-second Undo, or after the person leaves the You root. No screen shows a hidden fact, feeling or goal again. "Show hidden memories" on Timeline shows only hidden moments. It does not show hidden facts, feelings or goals. A hidden fact, feeling or goal cannot be deleted, because no screen shows it. Lines hidden before this change are in the same state. A way back is a follow-up for the owner to place.

## 2026-11-15 · Five sections: Timeline, People, Places, Things, You

**Status:** Decided. Supersedes owner's call 4 of the UI audit of 2026-10-26 (a tab bar of Timeline, People, Sessions, Settings). Source: the owner's approval of `docs/specs/2026-11-15-five-sections.md`.

**Decision.** The app has five tabs and search. Timeline stays home. People is a grid of faces, Places is a map, Things is a shelf, and You is a portrait in the person's own words. Sessions is a labeled button on Timeline. Settings is a labeled button on You. The record bar sits above the tabs on every tab and names the page the person is on.

- The tabs ship first with the current lists inside them. Each section gets its own shape in a later step, when its data exists.
- A session started from a page records that page as its subject and opens with a question about it. The app links nothing the person did not say.
- A computed life period is named by age only ("Childhood", "Teens", "Twenties"). Any other name comes from the person.
- The person picks photos one at a time with the system picker. The app keeps a copy in its own folder, includes it in backup export, and keeps it out of the phone's cloud backup, as it does audio.
- The app may show an Apple map and send the place searches the person types to Apple. Lookups the app starts itself stay off.

**Why.** After a month of use, one screen carried everything and six unlabeled icons led away from it (audit F7, F9). Each kind of thing in a life needs its own way of being seen, and every one of them must lead back to telling (P1, P2). No screen may ask the person to complete a record (P9), and no inferred span, location or name may show as fact (P5).

## 2026-11-15 · A kept card's close can be undone

**Status:** Decided by the owner. Source: the review of PR #18 (`CardHandler.close`); `docs/specs/2026-10-26-cards-follow-ups.md`, rules 9 and 11.

When a kept card closes, the follow-ups nobody answered are dismissed. A card closes on "Done" and also when the person acts on another memory card, so follow-ups could go with no tap on them. The app now shows "{n} suggestions dismissed." with Undo for 6 seconds whenever a close dismissed something. Undo makes the follow-ups pending again and brings the card back.

Closes inside one 6-second window add up: one Undo takes all of them back. The close writes its dismissals in one transaction, and Undo writes its restores in one transaction, so a failure or a kill leaves every follow-up of that write as it was (PRINCIPLES 4).

**Why.** Unanswered follow-ups must not pile up in "Waiting for you": that backlog is what the UI audit removed. So the close still dismisses them. But a dismissal the person did not choose must be one they can take back (PRINCIPLES 9).

**Not chosen.** Leaving unanswered follow-ups pending: one leftover card for each kept memory. Keeping the silent dismissal: no way back.

## 2026-10-26 · Filler words are hidden in quotes on lists and pages

**Status:** Decided by the owner. Source: `docs/specs/2026-10-26-ui-audit.md`, call 1 and finding F12.

Quotes on lists, entity pages and About hide filler words ("um", "uh", "like", "you know") and repeated words. The stored transcript does not change. The memory page and the audio keep every word (PRINCIPLES 1).

## 2026-10-26 · The timeline groups moments into computed life periods

**Status:** Decided by the owner. Source: `docs/specs/2026-10-26-ui-audit.md`, call 2 and findings F2–F3.

The timeline reads life periods from the dates and the owner's age, for example "Growing up · 2004–2012". Each computed period shows as a guess (PRINCIPLES 5). A chapter the person names replaces the period it covers. "Outside any chapter" goes away.

## 2026-10-26 · Extractor v7 changes to existing memories are suggestions

**Status:** Decided by the owner. Source: `docs/specs/2026-10-26-ui-audit.md`, call 3.

Extractor v7 re-reads the existing memories. Each change it finds (a new title, a link to a person, "about you" in place of the owner's name) is a suggestion the person approves. No change is applied silently (PRINCIPLES 9).

## 2026-10-26 · A labeled tab bar replaces the floating icons

**Status:** Decided by the owner. Source: `docs/specs/2026-10-26-ui-audit.md`, call 4 and finding F7.

The app's top level is a tab bar with labels: Timeline, People, Sessions, Settings. The six unlabeled floating icons go away.

## 2026-10-26 · Follow-ups stay on the memory card

**Status:** Decided by the owner after a month of use. Source: `docs/specs/2026-10-26-ui-audit.md`, finding F1.

A follow-up (a domain tag, a story hint, a collection hint, an entity) never appears as its own card. After Keep, the memory card stays and shows its follow-ups as optional chips. A separate card read as random because nothing tied it to its memory (PRINCIPLES 9).

## 2026-10-25 · The interviewer speaks briefly, never over the person, and never improvises on safety (M8)

The app speaks its fixed lines and short model reflections in a settle-in session. A quick story stays nearly silent. Any speech from the person stops the app at once. The app's own words are kept apart from the person's in the transcript and never become a memory.

- A spoken turn waits for the safety check in the interviewer's own reply, and for the extractor's flags when they come first. Only the extractor moves the arc. This holds for every turn after the opening, bank questions included.
- The next question after a quiet spell stays on screen. It is not spoken.
- The model is `claude-haiku-5-5`. Echo cancellation runs on capture, and the recording sound changes with it; speech is not limited to headphones.
- The disclosure card does not change. The app speaks the 988 line only for present danger.
- The "About the app" line says that the person's words go to Anthropic as text.
- No "mm" acknowledgements in V1. The voice is the best installed system voice. "Lifeline speaks" is on by default.

Why: P1, P2, P3, P6, P8 and P9. See `docs/specs/2026-10-25-m8-interviewer.md`.

## 2026-10-25 · Memory kinds and domains: moments on the timeline, everything else by what it is about (M7)

**Status:** Decided. Closes "Open · Memory kinds and domains". Source: the owner's answers to the M7 spec, `docs/specs/2026-10-24-m7-elements.md`.

**Decision.** A memory has a kind: `event` and `other` are moments; `fact`, `feeling` and `goal` are not. Non-moments leave the timeline's shelf and chapters and are never asked "when?". The resolver still stores their ranges and the timeline hides them. The archive gains four entity kinds with pages: People, Places, Things, Ideas. Possessions, buildings, vehicles and objects are Things. Non-moments become details of an entity, or of the person ("About you"). People become entities with one link table for every kind; no parallel path for people. An entity page shows its details first and its moments below. The app never asks for a date on a Thing or a Place; the person can add one. An idea's title is the person's own words or "An idea you mentioned on {date}". Curiosity about entities asks for a scene, never for a date or an evaluation. Domains are free-text tags with no fixed list.

**Why.** Much of what a person says is not a moment. Forcing it onto the timeline fills the shelf with things that never get a date and makes the app ask the wrong question (Principle 2). A composed idea title or "Do you still think that?" interprets and evaluates a life (Principle 1).

**Consequences.** M7 ships as two PRs: PR A (kind column, migration v9, About section, "What is this?") first, then PR B (entities, migration v10, prompt v6). The person split is the largest task of PR B. `place`, `memory_place` and `memory_person` stay one release and are read nowhere; v10 drops them.

## 2026-10-24 · Copies of the archive stay out of the phone's cloud backup

**Status:** Decided. Source: Claude review of #9 (Backup.swift).

**Decision.** Every `.lifeline` file the app writes is excluded from the phone's cloud backup: an export, a safety copy before a restore, and the replaced archive zipped at launch. The audio folder is already excluded, so a copy must not send the same audio and transcripts out by another path.

**Why.** Data posture (V1): content leaves the device only when the person shares it. A copy in Files is on the device. The person moves it off the phone by sharing the file, which is an explicit act.

**Consequence.** A copy left in Files does not protect against a lost phone until the person shares it to iCloud Drive or another place. The export screen must say so.

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

## 2026-10-23 · M4 ships the landing, correction and durable sorting; the rest of the review waits for M5

What M4 ships from the 2026-10-22 review: finishing never waits for sorting (a launch-time worker picks up anything left pending); the Listen and Transcript & memories views; Keep / Change… / Dismiss with Undo and "Check this" tags; the light landing with Done for now as the default, Hide today and Delete today's recording; the disclosure flag with past and present kinds, a fixed card, and every organizational prompt (who's this included) suppressed in a heavy moment; visibility as two flags, `hidden_from_timeline` and `excluded_from_ai`; pause and resume; two ways in at first open and on the timeline.

Numbers chosen here, all configuration: a quick story has no time element; settling in is planned at 30 minutes with a 10-minute grace between wrap-up offers and the next question offered after 6 seconds of quiet; the recording limit of 3 hours is the one automatic landing.

Waits for M5: span-level deletion with offsets preserved (M4 deletes whole sessions and single memories); the privacy screen with Share and Local-only; stories and `story_moment`; reconciliation of related segments and the token-budgeted context packet; backup and restore; "Which part of the recording" and "Just tell me" on the Change sheet, shown disabled so the shape of correction is visible.

Added 2026-10-23 after the M4.1 device run: **duplicates among memories already kept.** M4.1 only compares a new card with one earlier memory, so three tellings of the same moment can sit on the timeline. M5 adds a pass over existing memories: the matcher ranks pairs, the extractor is asked in one batch which pairs tell the same moment, and each agreed pair becomes an "Are these the same?" card in Waiting for you with Play on each, Same story and Keep separate. A retelling that matches more than one memory names them all ("Same as X and 1 more?") and Same story merges the group into the oldest with one receipt, so Undo takes the whole thing back.

Why: the review's "preserve first, organize later" changes the landing and the session more than the data model; shipping those first lets the owner feel the new shape before the model grows. Cost: a memory told across two sessions goes with the first one deleted until span deletion lands.

## 2026-10-23 · V1 is one person's app: "protect" waits, backup does not

**Status:** Decided (owner).

The owner is the only user of V1. The privacy screen (Share…, Local-only before recording), span-level deletion with offsets preserved, the two disabled rows on the Change sheet and the in-app extractor re-run are not needed for V1 and wait until someone else uses the app. Hide from timeline, Exclude from AI processing and Delete (session or memory) already exist and stay.

One item is kept out of that list: a plain backup. Every recording and its derivatives live only on the phone, so a lost phone is a lost archive, which breaks "preserve first" for one user as much as for many. A one-tap export of the database and the audio to Files or iCloud Drive, with a restore path, is scheduled as a small task after M5, not as a milestone.

M5 is "organize" (`docs/specs/2026-10-23-m5-organize.md`); there is no M6 "protect" in V1.

## 2026-10-23 · Same story is offered, never applied; dates are stated, never inferred by the app

On the second day of the M4 build a story told in two recordings became two memories: the extractor's `same_as_memory_id` was never acted on and the packet only carried the current session's memories. A memory with no anchor had no way to get a date. M4.1 adds the moves the person can make and a suggestion they confirm.

**Decision.** Retrieval by on-device sentence embeddings (Apple's NaturalLanguage, cosine over `title. quote`) finds the nearest earlier memories across all recordings; they ride in the extractor's packet marked `related`. The extractor decides whether a segment retells one of them; a strong on-device match alone is also enough to put "Same as X?" on the card. The person decides: Keep stays the default and primary; "Same story" is one tap and undoable for six seconds. A merge is one memory with several audio spans (the V1 spec's `memory_span`); stories in M5 can group memories without undoing it. Merging into a resolver stand-in makes it real: the telling becomes its first span and `created_from_candidate_id` is set, so a memory with a nil candidate is only ever a stand-in. Undo is offered for six seconds and is refused if the target changed in any way since the merge; both merge and undo are single transactions. "Tell me when" writes a year, an around-year, a between, or an age with origin `stated`, shown as said; the resolver and the relative questions treat a stated range as settled. A memory excluded from AI is never embedded or suggested; a hidden one is never suggested on a card.

**Consequences.** Migration v7 (`memory_embedding`, span `title_text` and `candidate_id`); extractor prompt v4; deleting a recording removes only its spans, and a memory with a telling elsewhere survives; the Change sheet gains "Same as another memory…" and "Tell me when"; shelf rows show "Add a date" and "Add to a collection" inline. Thresholds (retrieve 0.55, suggest 0.80) are starting points to tune on the owner's recordings. Embeddings for earlier memories are backfilled in a detached launch task before the sorting worker runs, per model, not on the main actor. "Between two years" displays in the app's year-span style ("1996–99"). Spec: `docs/specs/2026-10-23-m4.1-same-story-and-when.md`.

## 2026-10-23 · Steady: sorting is visible and restartable, a copy is a file the person owns, a telling can be trimmed

After M5 the landing said sorting was still going on and the timeline said nothing; the phone held the only copy of everything; the Change sheet promised two corrections it could not do.

**Decision.** One quiet line on the timeline says what is still being sorted ("Still sorting 2 moments from today's recording…"), that the duplicate pass is checking for repeats, that sorting stopped ("Not sorting right now", Try again), or that a key is missing (the line opens Settings). The worker can start again: a saved key, the foreground, Try again. Hidden recordings count; deleted ones do not. "Your copy" in Settings exports one `.lifeline` file (a zip: the database copied through GRDB's backup API after a checkpoint, the audio, the pause log, a manifest; never the key) and restores one: the app writes a safety copy of what is on the phone to Files first, stages the copy, and applies it at the next launch before the database opens; a copy with a newer schema is refused, an older one migrates on open. "Which part of the recording" moves a telling's start and end to word boundaries within its segment, one part at a time for a telling told across a pause, and rewrites the card's span so Separate agrees later; Undo stays until the sheet closes. "Just tell me" waits for the interviewer. Two tests that flaked on the clock and on a timestamp tie are deterministic.

**Consequences.** ZIPFoundation 0.9.19 is the kit's second dependency (owner's call 0 in the spec; AppleArchive and a hand-written zip were the alternatives). `SortingReporter` is one more thing the composition root owns. Under `-uiTesting` the export skips the system share sheet, which a UI test cannot drive, and keeps the file in Documents. A restore never merges.

## 2026-10-23 · One moment, one story: pairs are asked, groups merge on one tap, stories ride on Keep in view

After M4.1 the owner had three memories of one friendship and a card that could name only one of them. M5 makes the same moment told any number of times one memory, a telling split by a pause one card, and related moments one story, without the app ever merging or grouping on its own.

**Decision.** A duplicate pass, after the embedding backfill at launch and a couple of seconds after every Keep, sends each memory's nearest few (cosine, `pairTop` 3, floor 0.55 only for a calibrated model) to a second structured prompt, the reconciler, in one batch of up to 20. Its `same_moment` and `same_story` verdicts become "Are these the same?" / "Sounds like one story" cards with Play on both sides; `different` is stored `separate` and never asked again, and so is Keep separate. Same story on a pair folds the newer memory into the older with one Undo. A card whose extractor names several memories (`same_as_memory_ids`, prompt v5) says "Same as X and n more?" and merges them oldest-first under one receipt, after the person checks the list. A segment that carries on a pending card (`continues_candidate_id`) grows that card ("+ 1 segment") instead of making another; Keep writes one memory whose later spans record what they continue (`continues_order`), and a continuation that arrives after the card was answered is an ordinary card. Stories are rows the person can rename, split, move into and take out of; the extractor proposes membership as a line on the card ("Part of: X", "Not part of it" one tap away) and a title as a hint card; Keep includes what the card showed. A story ref the model invents is minted into an id when stored, and a story with one visible member is not a group. Separate this telling turns a later telling back into its own memory, continuations and the anchors only it named along; a date the anchors gave goes with it, a date the person typed stays. The extractor's packet gains the session's pending cards and stories and a 6000-token ceiling (characters ÷ 4) that drops whole entries from the least relevant section first, never the profile text, never a section's first entry.

**Consequences.** Migration v8 (`story`, `story_moment` unique on memory, `duplicate_pair` cascading with its memories, `memory_span.continues_order`); prompts `extractor.v5.md` and `reconciler.v1.md`; a merged pair's row goes with the folded memory, so undo writes it back open; a resolver stand-in never outranks a real memory of the same session when a group is ordered; under `-uiTesting` the pass also writes its log next to the test database. The timeline's "Waiting for you" identifier moved to the section header: a List lays the card stack out as rows and an identifier on the stack replaced every card's own. Thresholds and the budget are starting points; the owner's device run decides them.

## 2026-10-23 · Quick story and settle in differ in shape, not in length

The owner's words: one is answering a prompt, the other is more of a conversation. A quick story is one prompt, finished when the person is done, with nothing about time on screen however long it runs. Settling in offers the next question when the room goes quiet after a story, and a gentle wrap-up with "Keep going" at the planned length. Nobody is stopped for talking longer than expected. Supersedes the entry below where they differ.

## 2026-10-23 · Sessions are short by default; the timer is a backstop

The owner's sessions run a few minutes and that is the intended shape. A session ends when the owner taps "Let's leave it there". The 40-minute wind-down and 60-minute hard stop from the design become a quiet backstop: a one-line nudge at 55 minutes and the summary opening by itself at 60. No screen shows session length as a goal. The spec's `middle` stage is dropped; stages are open, windDown, ended.

Why: the design was written imagining long oral-history sittings; real use is lighter, and every session must still land. Revised the same day by the review's "no automatic stop": the planned length brings a wrap-up offer with an explicit "Keep going"; the only automatic landing is a real recording limit. See the M4 plan (revised).

## 2026-10-23 · Direction: a short daily activity that builds over time

The owner's picture of the product (2026-10-23): a few minutes a day, one story at a time, with the timeline growing over weeks rather than being filled in one long sitting. Not a milestone of its own yet. It shapes what follows: each session opens with one fresh question (M3, done); the summary ends with one line for next time (M4); the spoken interviewer, when it comes, asks for one scene and stops. No streaks, counters or reminders that turn it into a chore; the principles rule out pressure. Open: whether a gentle daily nudge belongs in V1 at all.

## Open · Memory kinds and domains (closed 2026-10-25, see M7 above)

A later version will sub-divide memories by kind (fact, feeling, goal or intention, event, other) and by domain (relationships, health, education, travel, work, more). V1 ships one memory type and keeps the seam open: the candidate payload is JSON so a new extractor version can back-fill, no V1 code or copy assumes a memory is an event, and collection and chapter hints stay free text. Design after V1 has real sessions.

## Open · First user (closed 2026-10-21, see V1 scope)

Is the first user the person telling their own life, or an adult child interviewing a parent? Changes whose timeline a session writes to and whether "hand the phone over" is in V1. Default for now: the person's own life; design the session so handing over is a small change.

## Open · Server language (closed 2026-10-21, see No separate server in V1)

TypeScript or Python. Python is the natural home for the recording experiment and extraction prototypes; TypeScript matches the owner's web background. Decide when the server is created; the experiment can start in Python regardless.

## Open · How much the app may write

Verbatim quotes assembled into chapters, or prose the app composes in the person's style? The principles favor verbatim; replay narration may need light stitching. Decide with real transcripts in hand.

## Open · Closing question after a hard session (closed 2026-10-22, see above)

Unrelated by default, or tied gently to the memory? Decide after the recording study.
