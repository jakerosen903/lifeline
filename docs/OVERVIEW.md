# Life Timeline Overview

> Markdown export of the overview page (live copy: https://claude.ai/artifact/DrXtBmNYMmqfnjRJhTYEDP). Diagrams are inline SVG; GitHub renders them. The "under the hood" section follows ASD-STE100 style.


## An app that listens to your life and keeps it

You talk. A timeline fills in. Over months it becomes a replayable autobiography in your own voice, and later a shared story with the people who were there.

Status: design and grounding, pre-prototype. Updated October 21, 2026.

## What we are building

Most journaling tools ask you to write. Most family-history tools ask you to fill in forms. This app asks you to tell a story out loud, the way you would over lunch, and does the organizing itself. The core loop is short: **talk, extract, place, confirm, enrich**. The person tells a memory; the app pulls out what happened, who was there and roughly when; it places the memory on a timeline with honest uncertainty; it checks with a one-tap card; and it quietly notes what it would like to ask about next time.

The result is three things at once: a **journal** for revisiting fond memories, an **autobiography** you can replay chapter by chapter in your own voice, and eventually a **family record** where several people’s versions of the same Christmas sit side by side.

- **Phase 1 — Personal timeline.** Voice sessions, extraction, fuzzy time, chapters, people, replay. The whole product has to be good here.
- **Phase 2 — Props.** Favorite photos as prompts and anchors, then music from an era. Photos before music.
- **Phase 3 — Family.** Per-memory visibility, shared events with multiple perspectives, questions for each other.

## What we are learning

The design is grounded in four fields that have worked on the same problem for decades: oral history, therapy (narrative therapy, motivational interviewing, life review), autobiographical-memory research, and memoir craft. Each one changed something concrete in the product. The eight principles below are the distilled version; every screen and every line of the interviewer’s prompt should be checkable against them.

1. **The person is the author.** The app listens, reflects and organizes. It never interprets, evaluates or corrects a life.
2. **Ask for scenes, not facts.** Places, people and dates are harvested from stories, never requested as a form.
3. **Reflect more than you ask.** After any question, the next turns are reflections or silence. Never fill a pause.
4. **Follow the tangent, keep the thread.** Memory moves by association. Go where the person goes; file the dropped thread for later.
5. **Uncertainty is shown, never hidden.** Inferred dates and names look like guesses until confirmed. Nothing unsaid is filled in.
6. **Hard chapters are doors, not destinations.** Loss, illness and regret are offered once and left alone.
7. **Many true versions.** Family accounts of one event sit side by side. The app never adjudicates.
8. **Every session lands.** Sessions end deliberately, on time or early, with a summary and the person’s say over what is kept.

### Why memories cluster where they do

Memory research has a well-replicated finding called the reminiscence bump: adults recall far more from roughly ages 10 to 30 than from any later decade. The kind of cue matters too. Smells pull up the earliest memories, music peaks in the teens, and “tell me about an important moment” pulls later and larger than a cue word. Two product consequences: a thin middle-aged chapter is normal, not a failure to nag about, and the prompt should be chosen for the era we want to reach.




![reminiscence-bump](figures/reminiscence-bump.svg)



*Illustrative shape of autobiographical recall for an adult over 40 (not measured data). The timeline will naturally be dense in a person’s teens and twenties; the interviewer should expect that rather than fight it.*

### Fuzzy time is the normal case

People rarely give dates. They say “the summer after I graduated” or “when Maya was little.” So every memory carries a time *range*, not a point: a wide “possible” band and a narrower “likely” band. A collection such as *Family trips to Yosemite* can span a whole life (1996 to 2023) while each memory inside it keeps its own range. The range tightens through relative questions, never through a demand for a date.




![fuzzy-time-ranges](figures/fuzzy-time-ranges.svg)



*“The bear at the campsite” narrows from a 27-year collection span to a 3-year likely range through two relative questions. The person can stop at any step; the timeline renders whatever range is current.*

### People are resolved, not guessed

Every name mentioned becomes a pending “who’s this?” card. The person resolves it once, to a contact, to someone already in the story, or as someone new, and the link then holds across every memory. This is what keeps two Sams apart and lets “my sister” and “Maya” be one person. In Phase 2, photos use the same card: the person says who is in the picture, and that tag links the photo to a person.

### Every session has a shape

Sessions run 30 to 60 minutes, one speaker at a time. The app owns the landing. Therapy sessions and oral-history interviews both end deliberately, because ending on a hard memory is what stops people from coming back. A heavy moment triggers the same landing early.




![session-arc](figures/session-arc.svg)



*The arc every session follows. An early signal moves the ochre wind-down block to wherever the person is.*

## How it works under the hood

This section is written in Simplified Technical English (ASD-STE100 style): short sentences, one instruction per sentence, active voice, approved verbs, and “must” for requirements.

### 1. System overview

The system has four parts. The parts are the voice session, the interviewer, the extraction pipeline, and the timeline store. The voice session runs on the device. The interviewer runs on a server. The extraction pipeline runs on a server. The timeline store runs on the device.

The server does not keep data. The server receives a transcript segment with a context packet and returns a result. The device keeps the audio, the transcript, the timeline, and the people. This device memory is the only memory in the system. The device sends the part of it that a turn needs.




![data-flow](figures/data-flow.svg)



*The conversation loop (top two rows) runs in real time: streaming speech-to-text, the interviewer, text-to-speech. Device memory holds everything learned so far and gives the interviewer its context each turn. The extractor runs after each turn in the background. Audio never leaves the device; the server keeps nothing. A realtime speech model can replace VAD, speech-to-text and text-to-speech behind one interface.*

### 2. Voice session

The voice session has three stages. The stages are voice activity detection, speech-to-text, and text-to-speech. The voice session runs behind one interface. The interface sends these events: speech started, transcript partial, transcript final, and user paused. The interface accepts these commands: say, acknowledge, and interrupt.

The app must not know which voice implementation is active. Version 1 uses a cascade of the three stages. A later version can use one realtime speech model. The realtime model must send the same events and accept the same commands.

The speech-to-text stage must return word timestamps. The replay feature uses the timestamps to align the text with the audio.

The device must keep the audio file. The device must keep the transcript. The server must not keep a copy.

### 3. Turn policy

The turn policy decides when the interviewer speaks. The turn policy is a module on the device. The turn policy uses numbers. The numbers are configuration, not code.

- A short silence of about 1 second starts an end-of-thought check. A small, fast model reads the last words and the pause. The model returns one of two results: complete thought, or pause inside a thought.
- If the thought is complete, the interviewer can reply after a short grace period of about 1 to 2 seconds.
- If the pause is inside a thought, the interviewer must wait. The wait has a cap of about 6 to 8 seconds. At the cap, the interviewer gives a soft acknowledgement only.
- The end-of-thought model must run on the device or return in less than 300 milliseconds. The numbers above are initial values for testing, not fixed rules.
- The interviewer must not speak more than a set number of words in one turn.
- The interviewer must not ask a question until the person has made a minimum number of turns since the last question.
- The default reply is an acknowledgement, not a sentence. The acknowledgements are pre-rendered audio files.

### 4. Interviewer

The interviewer is a text model on the server. The interviewer receives the transcript segment, the pause length, the session stage, and a context packet. The context packet comes from device memory. The context packet has the people in the story, the chapters, the memories discussed before, and the curiosity list. The interviewer returns one of three results: no reply, an acknowledgement, or a short reply.

The conversation loop runs in real time. Speech-to-text streams while the person talks. The interviewer replies inside the turn. The extractor runs after the turn ends and does not block the conversation.

The interviewer prompt has three parts. The first part is the stance from the principles. The second part is the session arc. The third part is the curiosity list for this session. The curiosity list has people mentioned but not explained, places named without a story, and time anchors the resolver needs.

The interviewer must use the person’s words for names and chapters. The interviewer must not add a detail the person did not say. The interviewer must not evaluate what the person said.

A serious disclosure has a fixed response. The fixed response is text that the team writes and tests. The model must not improvise the response. After the fixed response, the session goes to wind-down.

### 5. Extractor and resolver

The extractor is a text model on the server. The extractor receives a transcript segment. The extractor returns candidate events, people, places, and time anchors. A time anchor is a phrase such as “the summer after I graduated.” The extractor marks each candidate with a confidence value.

The resolver is a module on the device. The resolver turns time anchors into ranges. The resolver uses events that are already placed. If the anchor refers to an event that is not placed, the resolver creates a floating event. The resolver adds a question to the curiosity list. One answer can place many floating events.

The extractor and the resolver can run again on old sessions. The pipeline must be idempotent. The raw audio and transcript are the source of truth. All other data can be derived again.

### 6. Data model

The timeline store is a local relational database. The store has six main tables. An event has a time range, not a date. An event points to the transcript segment it came from.




![data-model](figures/data-model.svg)



*Every event keeps a pointer to the audio it came from, so the recording stays the truth and the extraction stays a derivative. Collection spans are derived from members; chapters are titled by the person.*

### 7. Session arc and safety

The session controller runs on the device. The session controller tracks the elapsed time and the stage. The stages are open, middle, and wind-down. The controller starts wind-down at 30 to 45 minutes. The controller starts wind-down early when it receives a signal. The signals are: the person asks to stop, the person asks to change the subject, a long silence after a heavy topic, or audible crying.

In wind-down, the interviewer must not open a new door. The app shows a summary in the person’s words. The app asks the person what to keep. The options are: keep on the timeline, keep private, or let go. If the person selects let go, the device deletes the audio and the transcript for those events.

### 8. Phase 2 props

The person selects photos. The app does not scan the photo library. The app reads the creation date and the location from each photo. The app shows a date from metadata as a fact. The app shows a guessed era as a guess. The person tags who is in each photo. A tag links the photo to a person.

Apple’s PhotoKit does not expose people, memories, or trips. The app computes photo clusters from dates and locations. A cluster is a suggestion. A cluster is not an event until the person tells the story.

Music uses three sources. The first source is the person. The second source is public charts for the year and country. The third source is an optional upload of streaming history. A spike in plays is a suggestion, like a photo cluster.

**Before the prototype**

Two things come first. Record five to eight people telling a ten-minute story, including one older relative, and run extraction on the transcripts by hand to see where it fails. Then write down the data posture in one sentence (today: audio and timeline stay on the device, the server keeps nothing, sharing is explicit) so the technical design has a rule to follow.

### Open questions

- Cadence: is a session a weekly ritual, an occasional long sit-down, or both?
- Who is the first user: the person telling their own life, or the adult child interviewing a parent?
- How much may the app write? Verbatim quotes assembled into chapters, or prose it composes in the person’s style?
- Closing question after a hard session: something unrelated by default, or tied gently to the memory?

Companion material: the design canvas (hero screens, fuzzy-time options, onboarding, wind-down, Phase 2 props) and the grounding document (literature review and principles).
