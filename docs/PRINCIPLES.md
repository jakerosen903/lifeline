# Grounding Principles: How the Life Timeline Interviewer Learns About People

Grounding document · October 21, 2026 · Live copy: https://claude.ai/artifact/VUpLNWEM86y4UHSbCgTHhE

## Why this review

The interviewer agent has one hard job: get a person to tell their life as stories, without it feeling like a form, while quietly collecting the facts a timeline needs (who, where, roughly when). Four fields have worked on exactly this problem for decades: oral historians, therapists, memory researchers, and memoir writers. This review pulls the techniques that transfer and ends with a map from technique to feature.

The short version: ask for scenes, not facts; use silence and reflection instead of the next question; cue memory through place, people and senses; and treat the person as the author of their story, with the app as the listener.

## Principles

This document is the project's grounding reference. Every interviewer behavior, prompt and UI decision should be checkable against these eight rules, which the rest of the document justifies.

1. **The person is the author.** The app listens, reflects and organizes; it never interprets, evaluates or corrects a life.
2. **Ask for scenes, not facts.** Baseline facts (places, people, dates) are harvested from stories, never requested as a form.
3. **Reflect more than you ask.** After any question, the next turns are reflections or silence. Never fill a pause.
4. **Follow the tangent, keep the thread.** Memory moves by association; the app goes where the person goes and files the dropped thread for later.
5. **Uncertainty is shown, never hidden.** Inferred dates, names and places are displayed as guesses until confirmed; relative questions over proposed facts; nothing unsaid is filled in.
6. **Hard chapters are doors, not destinations.** Loss, illness and regret are offered once and left alone.
7. **Many true versions.** Family accounts of the same event sit side by side; the app never adjudicates.
8. **Every session lands.** Sessions end deliberately, on time or early when things get heavy, with a summary and the person's say over what is kept.

## Oral history: the listener's craft

Oral historians have the closest job to ours: long recorded conversations with ordinary people about their lives, where the recording is the artifact. Their guidance is remarkably consistent across institutions.

**Open first, then pursue.** [Baylor's Institute for Oral History](https://www.baylor.edu/content/services/document.php/66431.pdf) tells interviewers to "ask open-ended questions first, waiting to see what unfolds," then "tailor follow-up questions to the narrator's responses. Pursue in detail." The topic outline is "a guide rather than a script."

**Silence is a technique.** Baylor: "Silence is an integral, important part of the oral history interview process." After the narrator stops, wait; they usually add more. For a voice app this is the single most important behavior: do not fill the pause.

**Follow the tangent.** "Let memory associations develop, even if you must set aside your outline for a while." One memory cues the next; interrupting to get back on topic loses the chain.

**Neutral feedback.** Nods and quiet acknowledgments, never agreement, disagreement or evaluation. Keeps the narrator's voice primary and avoids steering.

**Don't challenge memory.** If something seems inaccurate, you may raise other accounts, but "do not question the narrator's memory or honesty." Relevant for us when two family members tell the same event differently: present both, never adjudicate.

**Sessions of 60 to 90 minutes** are the practical ceiling before concentration drops, and shorter for older narrators.

**The Life Story Interview (McAdams).** Dan McAdams's protocol, used in narrative-identity research for 30 years, is the most structured version of this craft ([outline](https://web.lemoyne.edu/~hevern/psy444_24F/documents/The%20Life%20Story%20Interview%20Outline%2020241022.pdf)). Its structure maps almost directly onto our data model:

| Section | What it asks | What it gives us |
| --- | --- | --- |
| Life chapters | "How would you divide your life into chapters of a book?" (2 to 7, each titled) | Our chapters / eras, in the person's own words |
| Key scenes | High point, low point, turning point, positive and negative childhood memory, vivid adult memory, wisdom event | Dated, emotionally tagged events; the scaffolding a timeline hangs on |
| Challenges | Greatest challenge, health, loss, failure or regret | Hard chapters, approached by invitation |
| Future script | Next chapter, hopes, a "project in life" | Forward-looking entries; not just a record of the past |
| Life theme | "Is there a central theme that runs through the story?" | The autobiography's through-line, asked only once trust exists |

Two things worth copying from McAdams: asking for **chapters before scenes** (people find it easy and it gives structure for free), and asking each scene as a **specific moment** with what happened, who was there, what they were thinking and feeling, and why it matters. The research behind it ([Nautilus overview](https://nautil.us/whats-your-story-the-psychological-power-of-narrative-234338)) finds that how people narrate turning points, especially "redemption" arcs where a bad event leads somewhere good, predicts wellbeing. The app should let those arcs show without prompting them.

## Therapy: stance and listening moves

Three therapeutic traditions have the most to offer. None of this makes the app a therapist; what transfers is the *stance* (person as author, listener as curious) and a small set of listening moves that keep a person talking.

### Narrative therapy (White and Epston)

Narrative therapy treats a life as a set of stories, and the person as their author and the authority on their own life. The therapist is "decentered but influential": curious, structured, never the expert ([overview](https://www.simplypsychology.org/narrative-therapy.html)). Techniques that transfer:

- **Use the person's own language.** Chapters, people and events are named in the words the person used, never normalized ("the Boston years", not "2011–2014").
- **Unique outcomes.** Ask about moments that don't fit the dominant story ("was there a time that winter when it wasn't hard?"). For us: a lever for thin chapters.
- **Re-membering.** Identity as a club of significant people whose membership can be revised. Our People view is this made literal.
- **Therapeutic letters.** Epston wrote clients letters restating the session in their own words, to be reread. Our session summary ("Your story has its first chapter") is the same move, and should quote the person rather than paraphrase.
- **Outsider witnesses.** Others respond to a retelling with what struck them and what it evoked, never with praise, advice or interpretation. This is the right rule for family members reacting to each other's memories in Phase 3.

### Motivational interviewing (OARS)

MI is a counseling style built on four moves, [OARS](https://www.homelesshub.ca/resource/motivational-interviewing-open-questions-affirmation-reflective-listening-and-summary): **O**pen questions, **A**ffirmations, **R**eflections, **S**ummaries. Its core rule of thumb is the one we need most: *questions interrupt flow, so favor reflections.* A reflection ("so the windows were down the whole way") keeps the person talking without asking anything. Three depths, used in rotation:

| Depth | Example | When |
| --- | --- | --- |
| Repeat or rephrase | "The green station wagon." | Default; cheapest, never wrong |
| Paraphrase meaning | "Sounds like those drives were the best part of the trip." | When the person pauses |
| Reflect feeling | "You still miss him on those roads." | Rarely; only when it's clearly there |

Summaries come at transitions: "Let me see if I have this: every August, the wagon, Maya carsick, Dad saying 'almost there.' Did I miss anything?" The closing question invites correction, which is how extraction errors get fixed without a form.

### Life review and reminiscence (Butler, Haight)

Robert Butler described life review in 1963 as a natural process in later life, where the past returns and is reintegrated. Structured life review ([overview](https://www.socialworktoday.com/archive/exc_011812.shtml)) is one-to-one with a "therapeutic listener", chronological over six to eight one-hour sessions (childhood and home, then adulthood, then summing up), and has evidence for reduced depression and increased life satisfaction in older adults comparable to CBT in several studies. Transferable pieces:

- **Props.** Music, photos, aromas, objects, genograms and timelines are standard aids. Photo-triggered storytelling is well established practice, not a gimmick.
- **Historical anchors.** When general prompts fail, ask what the person was doing on the day of a major public event. It feels low-stakes ("no right answer") and yields a hard date. Useful as a resolver tactic for undated memories.
- **Family in the room.** Including relatives is a recognized variant, which supports the "interview someone else" mode.
- **Not for everyone.** Life review is not recommended for people who don't want to revisit the past. The app needs an easy "not this" and no pressure on hard chapters.

### Family therapy: genograms and timelines

Family therapists draw a genogram (a family tree annotated with relationships and events) in the first session, and it doubles as an interviewing tool: filling it in produces the baseline facts as a side effect of drawing. Our onboarding "What I'm learning" panel is a genogram built by listening rather than asking.

## Memory science: what cues recall, and what corrupts it

Autobiographical memory research tells us which prompts surface memories and which prompts invent them. Both matter for an app whose extraction will suggest dates, places and people back to the person.

**Memories cluster in youth.** The reminiscence bump is a well-replicated peak of memories from roughly ages 10 to 30 in adults over 40 ([Koppel & Berntsen](https://www.psychologicalscience.org/journals/current-directions/0963721416631955/)). The bump shifts with how you ask: requests for *important* memories produce a later, larger bump than cue words, and odor cues produce an earlier one. Two consequences: a timeline will naturally be dense in a person's teens and twenties and thin elsewhere (so thin middle-age chapters are normal, not a failure), and the *kind* of prompt shapes which era answers.

**Different cues, different memories.** A 2015 study of cue modality ([Willander et al.](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2015.01681/pdf)) and the work it reviews find consistent differences:

| Cue | What it tends to surface |
| --- | --- |
| Words and open questions | Vivid memories, bump at 10 to 30; the workhorse |
| Pictures | Rated more emotional than word- or odor-cued memories |
| Music | Bump at 10 to 20; strong for adolescence |
| Smell and taste | Earliest memories (peak before age 10), rated most pleasant, strongest "being brought back" feeling |

For the app: photos are the practical sensory cue (and carry EXIF dates), but prompts can name smells and sounds in words ("what did that kitchen smell like?"), which is what the onboarding question already does. Music is the under-used lever: a "songs from when you were 15" prompt is cheap and well supported.

**Leading questions create memories.** Loftus's work since the 1970s shows that leading questions and post-event information from a trusted source reliably alter recall; the "lost in the mall" study implanted a wholly false childhood event in about 25% of participants, and later replications report 30 to 50% ([Wellcome Collection summary](https://wellcomecollection.org/stories/lost-in-the-mall-and-other-false-memories)). This is the central risk in our design: an extractor that confidently says "Yosemite, 1998, with Dad" is a trusted source supplying post-event information. Rules that follow:

- Suggested details must look like guesses, never facts: "around 1998?", shown as uncertain (the ochre range, not a date).
- Prefer relative questions ("before or after Maya was born?") to proposed dates; they anchor to the person's own memory rather than supplying a number.
- Never fill in a detail the person didn't say. If the transcript says "the park", the event is "the park" until they name it.
- Keep the original audio as the record. Extracted text is a derivative and should be labelled as such in the UI ("what I heard").

## Writers and journalists: how to get a scene

Writers care about something the other fields don't: whether the memory comes out as a *scene*, with texture, rather than a summary. Since our replay feature plays memories back as stories, this is our quality bar.

**StoryCorps.** The largest body of recorded personal interviews in the US runs on a short, plain list of [Great Questions](https://archive.storycorps.org/great-questions-list/) grouped by relationship and life stage: "Where did you grow up?", "What were your parents like?", "What is your best memory of childhood? Worst?", "What are you proudest of in your life?", "How would you like to be remembered?" The list is framed as "merely suggestions for getting a good conversation going." Two lessons: the questions are deliberately ordinary (the magic is in the answer, not the question), and the format pairs two people who know each other, which is what makes the "interview someone else" mode work. A good starter deck for our guided sessions is already written; we don't need to invent prompts.

**Scene, not summary.** Mary Karr ([The Art of Memoir](https://supersummary.com/the-art-of-memoir/summary)) argues that memoir lives on "pulsing, lifelike episodes" over "clinical robotic discussions", and that one specific detail which sparks curiosity leads to deeper details and dramatic moments. Her framing advice is to tell it as if "to someone over lunch." For the interviewer: when a person summarizes ("we went to Yosemite every summer"), the follow-up asks for one time ("pick one of those trips. What do you remember first?"). That single move turns a collection into a memory.

**Walk the senses.** Memoir teachers use a staged sensory method ([Marion Roach Smith, citing Artis Henderson](https://marionroach.com/2014/01/how-to-access-the-details-for-writing/comment-page-1/)): start wide (the weather, the season), move through sight, smell, sound, taste, touch, then zoom in to the immediate room or car, then to the body ("were your shoulders tense?"). This matches the memory-science finding that smell and sound reach different memories than words do, and it gives the interviewer a ladder of follow-ups that never asks "what else?"

**Memory is unreliable, and that's allowed.** Karr calls memory "notoriously unreliable" and describes an implied contract with the reader: truth is expected, but subjectivity and small inaccuracies are accepted because they're unavoidable. This is the right posture for family timelines: three siblings' versions of one Christmas are three true accounts, not a conflict to resolve.

**Terkel and the journalist's ear.** Studs Terkel, whose oral histories (*Working*, *Hard Times*) defined the genre, was known for letting people talk, for showing visible interest in ordinary lives, and for the question that often opened the best material: not "what happened?" but "what was that like?" The through-line from Terkel to StoryCorps is that people tell their best stories to someone who seems to want to hear them; the interviewer's curiosity is the technique.

## Props: photos and music as memory cues

Life review practice and the cue-modality research both say the same thing: the richest memories come from a picture, a song or a smell, not a question. Two props are practical to build.

### Photos

The person picks favorite photos from key points in their life (the app never scans a whole library). Each photo is both a prompt and a source of structure:

- **As a prompt.** "Tell me about this one" is the single most reliable way to get a scene, and the follow-up ladder (who's in it, where, what happened just before and after) comes free.
- **As an anchor.** EXIF date and location, when present, give a hard point on the timeline; a scanned print still gives a rough era from the print itself ("looks like the 80s?" shown as a guess, per the uncertainty rule).
- **As a people source.** Faces that recur across photos are candidate People, resolved the same way as spoken mentions: the app asks "who's this?", the person answers, and the link holds across stories. On-device face grouping only; nothing is identified without the person naming it.
- **As a key-moment detector.** A cluster of photos from one week is a strong hint of an event worth asking about (a trip, a wedding, a move).

**What Apple's PhotoKit exposes (checked October 2026).** Per photo: creation date, GPS location, media type, dimensions, favorite and hidden flags, and the image bytes with full EXIF. Collections: user albums, shared albums, and fixed smart albums such as Favorites, Selfies and Panoramas ([PHAssetCollectionSubtype](https://developer.apple.com/documentation/photos/phassetcollectionsubtype.md)). **Not exposed:** People and faces, Places, Memories, Trips and Pets are internal to the Photos app and have no public API; the old Moments grouping was deprecated in iOS 13 ([developer forum](https://developer.apple.com/forums/thread/688345)). Consequences: dates, places and photo clusters come straight from the API; face grouping is built in-app over the photos the person chose: Vision for detection and alignment (its face-identity request, VNGenerateFaceprintRequest, is private API), a bundled Core ML face-embedding model for identity, and on-device clustering; VisionKit adds nothing for faces (it covers Live Text, data detectors, document scanning and subject lifting), though Live Text can read dates written on the back of scanned prints; trips are derived from date and location, not imported. Users can grant a limited selection instead of the full library, which matches the pick-a-few posture.

**Phasing decision (Oct 2026).** V1 uses photos for people context with no face model: the person taps "who's in this?" and names them, which links the photo to People and builds a labeled set. The face-embedding model is held for later and ships only after an evaluation against those tags, because cross-age matching (childhood prints to adult photos) is where off-the-shelf embeddings are weakest; clustering within an era rather than across a whole life is the likely first scope.

### Music

Songs are the strongest cue for the ages 10 to 20 band and are cheap to present. Three sources, from most to least available:

| Source | What it gives | How far back | Access |
| --- | --- | --- | --- |
| Ask the person | "What were you listening to the summer you were 16?" | Any era | Always; also the most personal |
| Era charts (public) | The popular songs for a given year and country, matched to the person's birth year and location | Any era | Public data; needs no account |
| Spotify extended streaming history | Every play with timestamp, track, artist, platform, country, for the lifetime of the account ([Spotify: understanding your data](https://support.spotify.com/br-en/article/understanding-your-data/)) | Account lifetime, typically 2010s onward | User requests the export from Spotify's privacy page and uploads the files; stats.fm works this way ([developer thread](https://community.spotify.com/t5/Spotify-for-Developers/How-does-stats-fm-get-lifetime-listening-history/td-p/6546400)) |
| Spotify Web API | Top tracks and artists over short, medium and long term windows; recently played, last 50 | Roughly the past year or so | OAuth; live, but no deep history |
| Apple Music (MusicKit) | Library, recently played, heavy rotation; a play-activity history is in Apple's privacy data export | Recent via API; longer via export | As far as I know, no long-range history over the API; worth verifying before committing |

The practical design: ask first, use era charts to make the asking easier ("was it more this or this?"), and treat a streaming-history upload as an optional enrichment that lets the app say "in the winter of 2014 you played this song 200 times. What was going on?" That last prompt is the music equivalent of a photo cluster: a detector for moments worth a story.

Both props follow the uncertainty rule. A song from the charts is a suggestion; a song from the person's history is a fact about listening, not about the memory, until they connect it.

## Session arc and emotional safety

Every session has a shape, and the app owns the landing. Therapy sessions and oral history interviews both end deliberately because ending on a hard memory is what stops people coming back. Sessions run 30 to 60 minutes; one speaker at a time.

| Stage | When | What the interviewer does | What it does not do |
| --- | --- | --- | --- |
| Open | First few minutes | One invitation, then listens | No second question until the person has told something |
| Middle | Until about minute 30 to 45 | Reflections, follow-ups on what was said, at most one door per session | No new door after a heavy moment |
| Wind-down | Last 10 minutes | No new doors; summary in the person's words; one light, forward-looking question; a clear "let's leave it there for today" | Never ends mid-story or on a low point |
| Early wind-down | On a signal, any time | Same landing, sooner: reflect, offer to pause ("we can leave this here and come back whenever you want") | No follow-up on the thing that hurt |

**Signals for an early wind-down.** The app does not diagnose anyone. It responds to what it can observe: the person says they are upset or want to stop, asks to change the subject, goes quiet for a long time after a heavy topic, or is audibly crying. Any of these starts the landing.

**Serious disclosures have a fixed response.** If someone discloses abuse, danger to themselves or others, or similar, the interviewer stops interviewing. It gives a short, warm, pre-written response, offers help once without insisting, and lands the session. This is scripted and tested, never improvised by the model in the moment.

**The person controls what is kept.** After an emotional session the summary asks plainly: keep this memory on the timeline, keep it private, or let it go. Recording something painful without asking would break the authorship principle at the moment it matters most. The audio is deleted if they choose to let it go.

**Voice pipeline note.** V1 runs a cascade (voice activity detection, streaming speech-to-text, the interviewer as a text model, text-to-speech) behind a single voice-session interface, so a realtime speech model can replace it later without touching extraction, the session arc or the turn policy. Turn-taking numbers live in that policy: a short silence (about 1 s) triggers a fast end-of-thought check; a complete thought gets a reply after a 1 to 2 s grace; an unfinished one gets a capped wait (6 to 8 s) and then a soft acknowledgement only. Plus a cap on interviewer words per turn and a minimum number of user turns between questions.

## Design implications

The interviewer should behave like an oral historian with a therapist's listening moves, a memory scientist's caution about suggestion, and a memoir editor's appetite for scenes. Concretely:

| Technique | Source field | Feature or rule in the app |
| --- | --- | --- |
| Chapters before scenes | McAdams | First sessions ask for a chapter ("the house you grew up in"); the timeline's chapter structure comes from the person's own titles |
| Scene types: high, low, turning point, vivid memory | McAdams | The guided-session deck; also the "turning points" filter on the timeline |
| Open question, then pursue in detail | Oral history | One prompt per session; follow-ups come only from what was said |
| Silence after the person stops | Oral history | A fast end-of-thought check decides whether a pause is the end of a thought; the interviewer never fills a pause with a question |
| Follow the tangent | Oral history | Extraction never redirects; the curiosity list records the abandoned thread for later |
| Reflections over questions (OARS) | Motivational interviewing | Interviewer's turn budget: mostly short reflections, at most one question per few turns |
| Summary with "did I miss anything?" | MI | End-of-session summary in the person's words; the correction path for extraction errors |
| Person's own language | Narrative therapy | Titles, chapter names and people names are quoted, never normalized |
| Unique outcomes | Narrative therapy | Lever for thin or heavy chapters: "was there a good day that winter?" |
| Outsider witness rules | Narrative therapy | Phase 3: family reactions limited to what struck them, never corrections or advice |
| Therapeutic letters | Narrative therapy (Epston) | Session summary and chapter narration quote the person back to themselves |
| Props: photos, music, objects | Life review | Photo-triggered storytelling; "songs from when you were 15"; EXIF dates as anchors |
| Historical anchors | Life review | Resolver tactic: "where were you when X happened?" for undated memories |
| Family in the room | Life review | Interview-someone-else mode |
| Memories cluster at ages 10 to 30 | Memory science | Thin middle chapters are expected; don't nag about them |
| Cue type shapes the era recalled | Memory science | Sensory and music prompts for childhood; "important moment" prompts for adulthood |
| Leading questions implant memories | Memory science (Loftus) | Suggested dates shown as ranges; relative questions over proposed facts; never fill in unsaid details |
| Scene, not summary | Memoir | When the person generalizes, ask for one instance |
| Walk the senses | Memoir | The follow-up ladder: wide, senses, zoom in, body |
| "What was that like?" | Journalism (Terkel) | The interviewer's default follow-up |

### Anti-patterns to avoid

- **The question-answer trap.** A sequence of questions turns storytelling into an intake form. Rule: after a question, the next two interviewer turns are reflections or silence.
- **Confident extraction.** Presenting a guessed date, place or name as fact. Everything inferred is shown as uncertain until confirmed.
- **Forcing the hard chapters.** Life review is contraindicated for people who don't want to revisit the past. Loss, illness and regret are offered as doors, never opened by the app.
- **Evaluating.** Praise, interpretation and advice all shift the person from author to subject. The interviewer notices and reflects; it doesn't judge.
- **Adjudicating family accounts.** Different versions of one event are kept side by side. The app never picks a "correct" one.
- **Over-using the person's name or past facts.** Pulling in stored details to seem attentive reads as surveillance. Use what the person said in this session; reach back only when it unlocks something ("if I knew when you moved, I could place four memories").

## Sources

- [The Life Story Interview outline (McAdams, Northwestern)](https://web.lemoyne.edu/~hevern/psy444_24F/documents/The%20Life%20Story%20Interview%20Outline%2020241022.pdf)
- [What's Your Story? The psychological power of narrative (Nautilus)](https://nautil.us/whats-your-story-the-psychological-power-of-narrative-234338)
- [Baylor Institute for Oral History, interviewing guidance](https://www.baylor.edu/content/services/document.php/66431.pdf)
- [Narrative therapy: definition, techniques, interventions (Simply Psychology)](https://www.simplypsychology.org/narrative-therapy.html)
- [Motivational interviewing: OARS (Homeless Hub)](https://www.homelesshub.ca/resource/motivational-interviewing-open-questions-affirmation-reflective-listening-and-summary)
- [Structured life review, Social Work Today](https://www.socialworktoday.com/archive/exc_011812.shtml)
- [Koppel & Berntsen, The reminiscence bump in autobiographical memory, Current Directions in Psychological Science](https://www.psychologicalscience.org/journals/current-directions/0963721416631955/)
- [Willander et al. 2015, Olfactory, visual and auditory cues and the reminiscence bump, Frontiers in Psychology](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2015.01681/pdf)
- [Lost in the mall and other false memories (Wellcome Collection)](https://wellcomecollection.org/stories/lost-in-the-mall-and-other-false-memories)
- [StoryCorps Great Questions list](https://archive.storycorps.org/great-questions-list/)
- [The Art of Memoir, Mary Karr (summary)](https://supersummary.com/the-art-of-memoir/summary)
- [How to access the details for writing memoir (Marion Roach Smith)](https://marionroach.com/2014/01/how-to-access-the-details-for-writing/comment-page-1/)

The Terkel paragraph draws on general knowledge of his published interviews rather than a page opened for this review.
