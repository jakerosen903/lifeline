# M8 — Interviewer: the app speaks, and never over the person

Status: draft for the owner's redline, 2026-10-25. Follows M7 (`docs/specs/2026-10-24-m7-elements.md`). Spec, not plan. It starts from the owner's draft plan (`~/dev/lifeline/m8-interviewer-plan-draft.md`, 2026-10-25) and fixes what the review of that draft found. Points from the owner's draft are marked **(owner's draft)**. Calls the owner did not make are marked **(my call)**. Calls only the owner can make are listed at the end.

## Scope, and what this spec is not

V1 listens. `ListenOnlyVoiceSession.say`, `acknowledge` and `interrupt` only log (`Voice/ListenOnlyVoiceSession.swift`). M8 makes them real behind the same `VoiceSession` interface. The app speaks the opening prompt, short reflections on what the person said, the next question after a quiet, the wrap-up offer and the fixed lines. The person can always talk over it. It never talks over the person.

Not in M8: replay narration (M9), photos (Phase 2), an end-of-thought classifier model (the segmenter's pause stays), crying or distress detection from the audio, a cloud voice, a third session kind, handing the phone to someone else.

Extraction, placement, stories, entities and the landing do not change, with one exception: words the app spoke must not reach the extractor as the person's words (Goal 3).

## Why now

The owner's sessions are short and the app gives nothing back while they talk. The principles describe an oral historian who reflects, waits and asks for one scene. M7 gives that interviewer things to point at ("tell me about the car"). Every M1 to M7 interface kept this seam open; M8 uses it.

## Goals

1. **The app speaks, briefly.** One voiced opening. In settling in: a short reflection after a closed story, and the next question after a quiet. At most 20 words per turn.
2. **The person always wins.** Speech from the person stops the app's voice at once. The app never starts a turn while the person is speaking. The person can make it quiet for the rest of the session, by voice or by one tap.
3. **The app's voice never becomes the person's words.** What the app says is stored as the app's turn, never transcribed into a segment, never extracted into a memory.
4. **Safety stays scripted.** A disclosure gets the fixed text, spoken as written. No model turn is spoken about a segment before that segment's flags are back and clean.
5. **A quick story stays nearly silent.** One voiced opening. After that, only the disclosure text and the early wind-down line, when the arc calls for them.

## Non-goals and anti-goals

- No question-answer rhythm. After a question, the next two interviewer turns must be reflections or silence (PRINCIPLES, anti-patterns).
- No filling a pause. Silence is the default decision of the turn policy. A failed or slow model call means silence, not a fallback sentence.
- No evaluation, praise or advice. A reflection repeats or gathers the person's words; it never interprets them (principle 1).
- No detail the person did not say. A name, place or number in a model turn must appear in this session's words, or the turn is not spoken (non-negotiable 3).
- No reaching back into the archive to seem attentive. The model sees this session's words only (PRINCIPLES, "over-using past facts"). Earlier material enters only as a question from the existing bank and curiosity list.
- A failure of M8 is the person stopping mid-story because the app spoke, or a memory made from the app's own sentence.

## The interviewer's turns

Every spoken turn is one of these kinds. Only two kinds come from the model.

| Kind | Source | When | Session kind |
| --- | --- | --- | --- |
| Opening | Fixed: `OpeningChooser` (M3, M7) | Once, when capture is running | Both |
| Reflection | Model | After a closed segment, see Turn policy | Settling in |
| Follow-up question | Model, in place of a reflection ("What was that like?"), never two turns after a question | After a closed segment, see Turn policy | Settling in |
| Wrap-up offer | Fixed: "We can leave it here, or carry on." **(my call: wording; it must not contain a phrase the voice matcher hears)** | `ArcEffect.offerWrapUp` with the reason `plannedLength` or the grace | Settling in |
| Early wind-down | Fixed: "We can leave this here and come back whenever you want." (PRINCIPLES, arc table) | `ArcEffect.offerWrapUp` with the reason `wantsToStop`, or after the disclosure text | Both |
| Disclosure | Fixed: `FixedResponses` text, exactly as the card shows it | `ArcEffect.showDisclosureCard` | Both |
| About the app | Fixed, see Safety | The model flags that the person asked what the app is | Settling in |

Acknowledgements ("mm") are not in the first M8 build **(my call)**. The principles allow a soft acknowledgement only after a capped wait on an unfinished thought, and a synthetic "mm" can sound like a second person in the room. They come in the last PR, behind the device check, if the owner wants them (owner's call 4).

The closing line is not spoken **(my call)**. The landing opens after capture stops, so a spoken closing would need a second audio path that is not recorded, and `Landing.closingLine` can change while sorting finishes (a late heavy flag). It stays on screen, as today.

`TurnPolicy` must know the arc's reason for an effect, not only the effect: `SessionArc` returns `offerWrapUp` both at the planned length and for `wantsToStop`.

Every turn is shown on the Listen view as it is spoken, as the opening prompt is today. The person can read what the app said.

## Turn policy

`TurnPolicy` must be a pure type: events and a clock in, one decision out (`speak(turn)`, `stayQuiet`). It holds no audio and no network. The session view model feeds it and acts on its decision. The numbers live in `ArcConfig` and are starting points for the device run.

Inputs: `speechStarted`, `transcriptPartial`, `segmentClosed` (counted only when the stored segment has words of the person's; a segment emptied by Goal 3 counts for nothing), the safety check for a segment (see the gate below), the arc's stage and effects, the quiet flag, the app's own playback start and end.

Rules, in precedence order:

1. While the person is speaking (a `speechStarted` without a closed segment after it, or a partial in the last 1 s), the decision is `stayQuiet`.
2. A disclosure or a heavy moment ends all model turns for the rest of the session. Only fixed turns are spoken after that.
3. The quiet flag ends all turns except the disclosure text and the early wind-down line.
4. **The gate.** Every spoken turn after the opening waits for a clean safety check of the latest closed segment, bank questions included (owner's decision B). The check is part of the interviewer's own call (owner's decision A): `disclosure: none | past | present` and `wants_to_stop`. A turn is spoken only if that check is clean and the extractor's flags for the segment, when they have arrived, are clean too. A failed or missing check is not clean. The extractor stays the only input to the arc: an interviewer check that is not clean silences the turn but does not wind the session down.
5. A model turn is dropped if new speech started after it was requested.
6. Never two interviewer turns without a closed segment between them, except a fixed turn that follows a disclosure.
7. After a question, the next two interviewer turns must not be questions.
8. A reflection is offered `replyGrace` (1.5 s) after a segment closes **(PRINCIPLES: 1 to 2 s)**. The model may answer "none"; most closed segments should get silence.
9. The next question after `nextPromptAfterQuiet` (6 s) stays on screen only, as today (owner's decision C). It is never spoken: PRINCIPLES says the interviewer never fills a pause with a question, and without an end-of-thought check a 6 s quiet cannot be told from a person thinking. The spoken interviewer is the opening, reflections, and the fixed lines.
10. In `windDown`, only the wrap-up offer and fixed turns are spoken.

## The model turn

- One Messages API call per candidate turn, from the phone, through the extractor's client and key. Structured output: `{ kind: "reflection" | "question" | "none", text: string?, asked_about_app: bool, disclosure: "none" | "past" | "present", wants_to_stop: bool }`.
- Context: this session's closed segments, newest first, within a 1500-token budget (characters ÷ 4, as the packet does); the opening prompt; the stage; the last three interviewer turns. Nothing from earlier sessions. A segment whose words belong to a memory the person excluded from AI is left out of the context.
- Prompt `Prompts/interviewer.v1.md` **(owner's draft)**, with the rules: reflect more than ask; one short turn; quote the person's words; ask for one scene, not a fact ("What was that like?" is the default follow-up); never evaluate; never answer a question about the person's life; return `none` when unsure.
- Checks on the client before a turn is spoken. A turn that fails one is dropped, never repaired **(my call: truncating can change the meaning)**:
  - At most 20 words.
  - Every capitalized word that is not the first word, and every number, appears in this session's words.
  - No text when `kind` is `none`.
- Model: `claude-haiku-5-5` by default for latency, configurable like the extractor's model (owner's call 3). The latency target is 1200 ms p50 from request to text. This is a guess to measure on the device, not a fact.
- No key, no network, or a refused call: model turns are silent. Fixed turns and bank questions still play. A session never fails because the interviewer cannot speak.

## Goal 3 — The app's voice stays out of the person's words

Capture and playback share the speaker and the mic (`.playAndRecord`, `.defaultToSpeaker`). Without countermeasures the transcriber hears the app.

1. **Echo cancellation.** Playback must run through the same `AVAudioEngine` as capture, with voice processing enabled on the input node while the app can speak **(my call)**. This gives the system the playback signal to cancel. It changes the recorded sound; the device run must check transcription quality (owner's call 2).
2. **Interviewer turns are stored.** A new table `interviewer_turn (id, session_id, kind, source: fixed | model, text, start_ms, end_ms, interrupted)` on the session's file clock, in migration v11 **(my call: M7 claims v10 for dropping the old people and place tables)**. It is part of the archive and the backup.
3. **The app's words are removed from segments.** A run of transcribed words that falls inside a turn's playback window (plus 300 ms) and matches that turn's text (60% of its tokens in order) is not part of a segment **(my call: thresholds)**. Words inside the window that do not match are the person's, for example a barge-in, and stay.
4. **The audio file keeps everything.** Preserve first: the recording is not edited. Playback of a memory may include the app's voice if the person's telling and the app's turn overlap.
5. **The transcript shows both voices.** The Transcript & memories view shows the app's turns between segments, marked as Lifeline's. A memory's span never starts or ends inside an interviewer turn.

## Goal 2 — The person always wins

- **Barge-in.** The segmenter's energy gate cannot tell the person from the app: it fires only from idle, and the app's own voice would open a segment and reset the pause timer. While the app speaks, energy must not open a segment or reset the pause timer **(my call)**. Barge-in is a transcriber partial with two or more words that do not match the turn's text; it calls `interrupt()`. Playback must stop within 500 ms of the first such partial **(my call: replaces the draft's 150 ms, which an energy gate could meet only if echo cancellation is perfect)**. The turn is stored with `interrupted = true` and is never repeated.
- **Quiet, by voice.** An on-device matcher over live partials hears "let me talk", "shh", "quiet please", "stop talking", "no questions". It sets the quiet flag at once. It ignores partials inside a playback window plus 300 ms that match the turn's text, so the app never hears its own words as a request **(my call)**. It does not go through the extractor **(my call: an extractor flag would need a prompt bump after M7's v6 and would arrive only after the 1.8 s pause plus an API call)**.
- **Quiet, by tap.** The Listen view has a visible control: "Quiet" while the app may speak, "Ask me again" while it is quiet (the visible-alternative rule, 2026-10-22).
- **No stop words.** The owner's draft adds "stop" and "cancel" as stop words. They are dropped **(my call)**: any speech already interrupts, and "we had to stop at the border" must not change the session.
- **Pause, interruption, finish.** Pause, an audio interruption (a phone call) and finish all stop playback. A stopped turn is not resumed.

## Goal 4 — Safety

- **Disclosure.** On `ArcEffect.showDisclosureCard` the app stops any playback and speaks the `FixedResponses` text exactly, then the early wind-down line. The spoken string must be the card's string (a test compares them, like the M4 `FixedResponses` test). Today one text serves both the past and the present kind, and it reads the 988 line aloud for both (owner's call 5).
- **The flags gate.** Rule 4 of the turn policy is the guard against an improvised reply to a disclosure. A test must show that a scripted disclosure segment followed by a slow flag gets no model turn.
- **About the app.** When the model sets `asked_about_app`, the app speaks a fixed line and no model text. The draft's line ("I don't send your voice anywhere") is not true as written: the person's words go to Anthropic as text. Proposed **(owner's call 1)**: "I'm Lifeline. I keep your recording on this phone. Your words go to Anthropic's model as text, so I can sort them and ask the next question."

## Voice

- `TTS` protocol in the kit. `AVSpeechTTS` in the app renders with `AVSpeechSynthesizer.write(_:toBufferCallback:)` into a player node on the capture engine (needed for echo cancellation and for barge-in). On-device. No audio leaves the phone, so the V1 data posture holds **(owner's draft)**.
- Voice: the best installed en-US enhanced or premium voice, chosen at first use. If only a compact voice is installed, Settings says that a better voice can be downloaded in iOS Settings **(my call)**. Rate and pitch are the builder's. The persona has no name in V1 copy **(owner's draft)**.
- A cloud voice is a change to the data posture. It needs its own decision before anyone else uses the app **(owner's draft)**.
- The app speaks with the screen locked, as it records with the screen locked. Bluetooth headsets (HFP) keep working.
- Settings has "Lifeline speaks" (on by default) **(my call)**. Off gives exactly today's listen-only session.

## Session kinds

No new session kind **(owner's draft)**. The interviewer is a property of the kind:

- **Quick story:** the voiced opening; the disclosure text and the early wind-down line if the arc calls for them. Nothing else.
- **Settling in:** everything in the turn table. "Keep going" is accepted by tap, and by voice ("keep going", "a bit more") through the same on-device matcher as quiet.

## Relation to M7

The core of M8 (voice, turn policy, echo handling, safety, quiet) does not depend on M7. The follow-up question comes from `OpeningChooser`, which M7 changes (entity scene questions, ordering). M8's question source must go through `OpeningChooser` only, so entity questions reach the interviewer without M8 changes. The M8 branch must start from `main` after M7's PR B merges **(my call)**.

## Ship order

Four PRs, each usable on the phone. The app can be interrupted from the first PR that speaks.

1. **PR 1 — The interviewer's turns, silent.** `TurnPolicy`, `interviewer_turn` and its migration, the removal of the app's words from segments (against scripted turns), turns shown on the Listen view as text. No audio out.
2. **PR 2 — Fixed turns are spoken.** `TTS`, `AVSpeechTTS`, the player node, echo cancellation, barge-in, the quiet controls, "Lifeline speaks". Spoken: opening, wrap-up, disclosure, early wind-down. No model, so no gate yet: these lines open the session or follow the arc.
3. **PR 3 — Reflections and follow-ups.** The interviewer prompt, the model turn, the client checks, the flags gate, "About the app".
4. **PR 4 — Device run and acknowledgements.** The checklist below; numbers redlined into `ArcConfig`; acknowledgements only if the owner wants them.

## Edge cases

1. The person speaks while a model call is in flight: the reply is dropped (rule 5).
2. The flags never return (no network mid-session): model turns stay silent (rule 4); fixed turns still play.
3. The model returns a name the person did not say: the client check drops it.
4. The model answers a question the person asked about their own life: the prompt forbids it; the 20-word cap and `none` keep it rare. A test with a scripted question about the past expects `none` from the scripted service.
5. A crash mid-turn: the turn row has no `end_ms`; the crash-resume landing ignores it. The audio file keeps what was played.
6. A route change (AirPods in or out) mid-turn: playback stops and the turn is not repeated **(my call)**.
7. Volume at zero: turns are still stored and shown.
8. A long telling with no 1.8 s pause: no turn is offered; the recording limit is the only stop.
9. Two segments close within `replyGrace`: one reflection at most, about the newer one.

## Tests the plan must carry

- Kit, `TurnPolicy`: quiet while speaking; no two turns without a closed segment; no question after a question for two turns; no turn after a heavy flag from either check; no turn before the interviewer's check returns; a failed check is silent; an unclean interviewer check silences the turn and does not move the arc; the 6 s next question is never spoken; quick story speaks only the opening, the disclosure text and the early wind-down line; a segment emptied by Goal 3 triggers nothing; the arc's reason picks the wrap-up or the early wind-down line; quiet flag; windDown speaks only fixed turns.
- Kit, segments: a run matching a turn's text inside its window is removed; a non-matching run inside the window stays; a matching run outside the window stays.
- Kit, model turn: each client check drops its case; `none` speaks nothing; a refused call is silent; the packet holds this session only and leaves out words of a memory excluded from AI.
- Kit, fixed text: the spoken disclosure string equals the card's string; "About the app" is never model text.
- Kit, quiet matcher: each phrase sets quiet; "we had to stop at the border" does not; the app's own words inside a playback window do not.
- Migration: `interviewer_turn` on a populated M7 database; the table is in the backup and survives a restore.
- UI (scripted voice and TTS): a settle-in session shows a reflection after a scripted segment; speech during a scripted turn marks it interrupted; "Quiet" stops turns and "Ask me again" brings them back; a scripted disclosure shows and logs the fixed text.

## Device checklist

1. Settle in. The opening is spoken within about 1 s of capture starting.
2. Tell a short story and stop. A short reflection or silence follows; never a question straight away.
3. Say nothing for 10 s. The next question appears on screen at about 6 s and is not spoken.
4. Speak while the app is speaking. It stops at once.
5. Say "shh". It stays quiet until you tap "Ask me again".
6. Open Transcript & memories. The app's turns are marked as Lifeline's; no memory card quotes the app.
7. Quick story. One spoken opening, then quiet to the landing.
8. A scripted disclosure phrase. The spoken text matches the card word for word.
9. Settle in past the planned length. The wrap-up offer is spoken once; "keep going" by voice continues.
10. Lock the screen during a settle-in. Turns are still spoken and recorded.

## Left to the builder

- The look of a spoken turn on the Listen view and in the transcript.
- Speech rate and pitch.
- The quiet matcher's exact phrase list beyond the ones above.
- How the follow-up question picks between the model's question and the bank's.

## Owner's calls

Decided 2026-10-25:

A. The safety check comes from the interviewer's own call. The extractor's flags also block a turn when they arrive first. Only the extractor moves the arc.
B. The gate holds back every spoken turn after the opening, bank questions included.
C. The 6 s next question stays on screen only.

Still open:

1. **About the app.** Approve or rewrite the fixed line, which must say that words go to Anthropic as text.
2. **Echo cancellation.** Voice processing on capture changes how the recording sounds. Accept it, or allow speech only with headphones.
3. **Model for the interviewer.** `claude-haiku-5-5` for speed (recommended) or the extractor's `claude-opus-5-5`.
4. **Acknowledgements.** Leave "mm" out of V1 (recommended), or try them in PR 4.
5. **Disclosure, spoken.** Speak the full card text, including the 988 line, for both the past and the present kind; or speak the 988 line only for present danger and keep it on the card for both.
6. **Voice.** Accept the best installed system voice, or pick one by name on the device.
7. **"Lifeline speaks" default.** On (recommended) or off.

Serves P1, P2, P3, P6, P8 and P9.
