# Audit data fixes: stories, chapters, extractor v7 and the second read

Status: owner's calls answered on 2026-11-16, except call 4 (`docs/DECISIONS.md`). A1 and A2 may be planned. A3 waits for call 4.

This spec covers ship-order items 2 and 3 of the UI audit (`docs/specs/2026-10-26-ui-audit.md`) and the "second read" of existing memories (audit, owner's call 3; `docs/DECISIONS.md`, "Extractor v7 changes to existing memories are suggestions"). The five-sections spec depends on this work and does not design it (`docs/specs/2026-11-15-five-sections.md`, "Out of scope"). The umbrella plan calls it track A (`docs/plans/2026-11-15-sections.md`).

## Problem

The audit found that the archive's data is thin and partly wrong:

- One story is stored three times (F14).
- Chapters are empty, untitled, or have a range taken from one memory (F2).
- Only 3 of 37 memories link to who or what they are about (F9).
- The owner's own name is stored as a person (F10).
- Titles are lower-case fragments (F8).
- The same place is stored twice, and generic phrases are stored as places (F13).

The five sections now show this data on every page. A person's page is thin because the links are missing. "Who you are" on You holds facts about other people for the same reason (PR #22, "Decisions made while building").

The causes are in three places: the code that stores stories and chapters, the extractor prompt and the code around it, and the 37 memories that v6 has already sorted.

## Terms

- **Moment:** a memory of kind `event` or `other`. It can sit on the Timeline.
- **Detail link:** the link from a fact, feeling or goal to the entity it is about.
- **Owner:** the person who uses the app. In the store, the `person` row with `is_owner = 1`.
- **Match key:** the form of a name that the app compares to decide that two names are the same.
- **Second read:** one run of extractor v7 over the segments of sessions that an earlier version sorted.
- **Suggestion:** one change that the second read offers. The person accepts it or declines it.

## What the code does today

These are facts from the code on `main` at `77d0440`. Each design rule below answers one of them.

### Stories

1. The app never looks up a story by title. Accepting a story hint on a memory that is in no story always inserts a new story with that title (`StoryActions.acceptStoryHint`). Three memories with the same hint become three stories with the same title. This matches F14.
2. Collections and chapters reuse a row with the same title. Stories do not.
3. `ExtractionQueue` keeps the ids it mints for new `story_ref` values in memory, for one session. The same story in a later session gets a new id.
4. A lone card whose `story_ref` names no stored story shows no story line, so Keep stores no story.
5. The Timeline hides a story with fewer than two visible members. Storage allows a story with one member.

### Chapters

1. "New chapter from here" always inserts a chapter with no title. It is on every memory row, including rows that the Timeline never draws inside a chapter (shelf, collection and story-member rows). Such a chapter shows as "Untitled chapter" with no memories.
2. No code deletes or renames a chapter.
3. A chapter's stored range is always computed from its members. No code stores what the person said about the chapter. One dated moment gives the chapter that moment's years.
4. A chapter hint is accepted for a memory of any kind. A fact can create a chapter. The range ignores facts, so that chapter has no dates.
5. A story has its own `chapter_id`. Assigning a memory to a chapter does not change its story's chapter. A memory in a story of two or more then shows in neither chapter.
6. The Timeline lists every chapter, empty or not, and counts empty chapters in the summary line.

### Extractor

1. The model is never told the owner's name. The packet leaves the owner out of `people`. Nothing in prompt v6 says that the speaker's own name is not a person mention.
2. `PeopleRepository.findPerson` does not exclude the owner. A spoken name that equals the owner's typed name links the owner as a person mention. A name that differs (a first name against a full name) raises "Who's this?", and "New person" creates a second person for the owner. This matches F10.
3. `about_ref` that points at a person mention from the same segment makes no detail link (`CandidateActions.aboutEntity` skips person mentions). A fact about a person who is new in that segment is never linked. This is one cause of F9.
4. `about_ref` is not validated.
5. Names are compared after lower-casing and trimming spaces only. "Ohio." and "Ohio" are two places. This matches F13.
6. No rule or code keeps a generic phrase ("a restaurant") from becoming a place.
7. A title is checked for one thing: at most 8 words.
8. The candidate row stores the extractor version. The memory row does not. The prompt schema and the validator are not versioned.
9. There are three invented transcripts and no test that scores the quality of an extraction.

### Running a version again

1. `ExtractionQueue.process` skips a segment that already has candidates for the same version. Under a new version it extracts the segment again and inserts new pending candidates. Those would show as new cards beside the kept memories.
2. No code runs an extracted segment again today.
3. The candidate row keeps the full extractor output, the quote and the word span. The segment keeps its text and word times. So a second read needs no audio and no new speech-to-text.

## Design

The work is three PRs. Each one is useful alone.

| PR | What | Depends on |
| --- | --- | --- |
| A1 | Story fixes and the empty-chapter repair | — |
| A2 | Extractor v7 for new recordings, with the code rules beside it | — |
| A3 | The second read | A2 |

### A1: stories

1. Accepting a story hint must reuse a story with the same match key (see A2, "Names") before it creates one. The memory joins that story.
2. When two or more stories share a match key, the newest telling joins the story that was created first.
3. `StoryRepository` must offer one function that merges story B into story A: it moves B's members to the end of A in their order, keeps A's title, keeps A's chapter (or takes B's when A has none), and deletes B. It must be one transaction.
4. Existing duplicates must be repaired. See owner's call 1.
5. A story with one member stays allowed in storage. The Timeline already hides it. Rule 1 lets a second memory join it later.
6. The minted `story_ref` ids stay per session. Rule 1 makes the title the link across sessions, so no stored id map is needed.

Edge cases:

- An untitled story has no match key and never matches.
- A story the person renamed matches on its new title only.
- Two stories with the same title in different chapters still match. The merged story keeps the first story's chapter.
- A kill in the middle of a merge leaves both stories as they were (one transaction).

### A1: chapters

The chapter rules moved to the Timeline spec (`docs/specs/2026-11-16-timeline.md`, "The model of a chapter", "Tags", "The life map" and "The chapter's sheet"). The owner chose a different model on 2026-11-16: a chapter is a name with stated years and said members, and the Timeline no longer groups moments under it. They ship as S6c.

A1 keeps one chapter rule, because it is a repair and needs no new screen:

1. A chapter with no title, no member and no story filed in it must be deleted. This runs once at launch for existing data and after a memory changes chapter.

### A2: names

1. One pure function gives the match key of a name: lower case, edge spaces removed, sentence punctuation and quotation marks at the ends removed, inner runs of spaces made one space. A symbol at the end stays, because it can be part of a name: "C++" and "C#" are two names. It replaces `PeopleRepository.normalize` for entity titles, story titles, chapter titles and collection titles.
2. Stored titles do not change. The person's spelling shows as they said it. Only the comparison changes.
3. Lookups by title must compare match keys.
4. Existing entities of the same type with the same match key must become one entity. See owner's call 1.

Edge cases:

- A name that is only punctuation has an empty key. An empty key never matches.
- Ideas keep their rule: they match by id only.
- "St. Louis" keeps its inner full stop. Only edge punctuation is removed.

### A2: the owner

1. The context packet must carry the owner's typed name and the owner's aliases, in a field `owner`. With no typed name the field is absent.
2. Prompt v7 must say: the speaker is the owner; the owner's name and "I" are never a person mention and never a `people_refs` entry; a fact, feeling or goal about the owner has `about_ref` `self`.
3. The code must not trust the prompt for this. After validation, a person mention or `people_refs` entry whose match key equals the owner's name or an alias is removed, and an `about_ref` that pointed at it becomes `self`.
4. The "Who's this?" card must offer "That's me". It adds the spoken name as an alias of the owner and makes no person.
5. `findPerson` must never return the owner as a person mention.

Data posture: the owner's name goes to the model provider inside the packet. The transcripts already carry it whenever the person says it. No new recipient is added. `docs/OVERVIEW.md` must say that the packet carries the name.

Edge cases:

- Another person shares the owner's first name. Rule 3 would remove them. So rule 3 applies only when the spoken text has no `relation_text` ("my cousin Jordan" stays a person).
- No owner row exists. `self` then makes no link, as today.

### A2: `about_ref`

1. An `about_ref` that points at a person mention from the same segment must make a detail link when that mention is resolved to a person: at Keep when the name is known, or when the person answers "Who's this?".
2. The validator must reject an `about_ref` that is not empty, not `self`, not an entity id in the packet and not a `ref` in the same output. The usual single retry applies. After a second failure the field is treated as empty; the memory is kept.
3. Prompt v7 must say: set `about_ref` on a fact, feeling or goal whenever the segment names the person, place or thing it is about; leave it empty when the segment does not say.

### A2: titles

1. A title names an event. Only a moment has one that the person sees.
2. For a moment, prompt v7 must ask for a title that names the moment, in sentence case, 3 to 8 words, in the person's words where it can.
3. For a fact, a feeling or a goal, prompt v7 must return an empty title. The app must not show a composed title for these kinds. The quote is the thing. This is the rule ideas already have (v6, rule 7).
4. `memory.title` cannot be empty in the store. For a fact, a feeling or a goal the code stores the start of the cleaned quote as the title: at most 8 words, cut at a word. One pure function gives it, from `ReadableQuote`. Lists that need one line for the memory (a picker, the context packet) read it.
5. Where a screen shows a fact, a feeling or a goal with a heading (its card, its own page), the heading is the cleaned quote in quotation marks, not a title.
6. The validator keeps the 8-word limit. It adds no lower limit. It accepts an empty title only for a fact, a feeling or a goal.
7. The app must not change a title's case in code. The person can rename a moment.

Example. The person says "I think we had some of our most formative experiences together" about a friend. v6 made a feeling with the title "our most formative experiences together". v7 makes a feeling about that friend with no title; the friend's page shows the sentence.

Edge cases:

- A memory that the person changes from a feeling to a moment keeps its stored title and can be renamed.
- A memory that the person changes from a moment to a feeling keeps its stored title in the store. The screens stop showing it.
- A quote of one or two words is its own title.

### A2: groups of people

A phrase can name more than one person: "our parents", "my grandparents", "the kids". Today it raises "Who's this?", which takes one answer. The answer is then saved as another name for that one person, so the next "our parents" links to that person with no question.

1. The extractor output gains one mention kind, `group`. Prompt v7 must say: a phrase that names more than one person is a `group` mention, never a `person` mention. Two names said together ("Mom and Dad") are two `person` mentions.
2. The code must not trust the prompt for this. One pure function says whether a phrase is a group: a plural kin or company word ("parents", "grandparents", "folks", "kids", "children", "siblings", "brothers", "sisters", "cousins", "aunts", "uncles", "friends"), with or without a possessive before it. A `person` mention that matches is treated as a `group`.
3. A group mention shows on the kept card as one chip: "Who are “our parents”?". It opens a list where the person can tick several people, add someone new, or choose "Leave it as said".
4. Each ticked person is linked to the memory, as a person mention is today.
5. A group phrase is never saved as a name for a person. The same phrase asks again in a later story, because who "our" means depends on the story.
6. "Leave it as said" links nobody. The phrase stays in the quote. The app does not ask about this memory again.
7. A person's page must list the other names the app has for them, each with "Remove". Removing a name changes no memory. It stops later stories from linking by that name.

Edge cases:

- A group phrase that the store already holds as a name for one person (from before this change) still resolves to that person until the name is removed. Rule 7 is the way out. A3 offers the removal (see "How a change is found").
- A group of one ("my parents" from a person who has one parent in the store): the list still shows; one tick is a valid answer.
- A group mention with no memory that carries it shows nowhere, as a person mention with no memory does today.

### A2: the Change sheet for what is not a moment

The Change sheet asks "The title", "Who was there" and "Same story" for every kind. Those questions describe a scene.

1. For a fact, a feeling or a goal the sheet shows, in this order: the quote; "About whom or what?"; "What kind"; "Who it mentions"; "Said before"; the recording rows.
2. It does not show "The title".
3. "Who it mentions" is the list that "Who was there" is for a moment. Only the heading changes.
4. "Said before" is the row that "Same story" is for a moment, with the same action. Its note reads: "This becomes a later telling of the one you pick. Its words and audio stay."
5. For a moment the sheet does not change.

### A2: generic places and casual ideas

1. Prompt v7 must say: a place with no name ("a restaurant", "somewhere up north") is `place_text` on the memory and is not a mention; a passing phrase is not an idea.
2. The code must not make a place entity from text that starts with an indefinite word ("a", "an", "some", "somewhere"). The text stays on the memory as its place text. One pure function decides this.
3. A possessive phrase ("our house", "my grandmother's kitchen") is not generic. v6 already treats a house as a thing the person had.

### A2: the prompt file, version and tests

1. `extractor.v7.md` is a new file. v1 to v6 stay.
2. v7 must keep rules 1 to 4 of v6 word for word (extract only what is said, summaries, confidence, disclosure). A test must compare them.
3. The schema changes in one way only: a mention's `kind` gains the value `group`. The new packet field needs no schema change. The decoder must stay tolerant of v6 payloads, as it is for v1 to v5.
4. `ExtractorConfig.version` becomes "v7".
5. The kit gains checks that need no network: the owner rule (A2 "the owner", rule 3), the `about_ref` rule, the match key, the generic-place function, the group-phrase function and the stored title of a fact, feeling or goal. Each is a pure function with tests.
6. The repository gains invented transcripts that hold each audit case: the owner says their own name; a fact names a new person; a place is said twice with different punctuation; a generic place; a retold story across two sessions; a feeling about a named person; a group phrase ("our parents") beside a named person.
7. `ExtractorIntegrationTests` (it runs only with a key, on the owner's Mac) must run v6 and v7 over those transcripts and print, per version: person mentions that are the owner, facts with and without `about_ref`, titles not in sentence case, facts, feelings and goals that carry a title, group phrases returned as one person, generic places. The owner reads the two columns before v7 becomes the default. This is the only measure of prompt quality; it is not a CI check.

### A3: the second read

The owner decided that v7 re-reads the existing memories and offers each change as a suggestion (`docs/DECISIONS.md`, 2026-10-26). This section designs that.

#### What it reads

1. The second read runs over every segment of every ended session whose kept memories came from a version before v7.
2. It skips a segment when every memory from it is excluded from AI. It leaves out of the packet whatever the packet already leaves out.
3. It sends the segment text and the packet to the same provider and model as a first read. It sends no audio. It adds no network host.
4. It must not run without the person. Settings shows one row: "Read my stories again". The screen says what happens in plain words: how many recordings, that their words go to the model provider again, and that nothing changes until the person says yes.
5. It runs while the app is open. It shows "Reading 3 of 22". It stops when the app closes and continues at the next segment when the person starts it again.

#### What it stores

1. v7 output for an old segment is stored as candidate rows with version "v7" and a status that the card queue never shows. The second read must never put a card in a session's queue.
2. A new table holds suggestions (a migration; see "Data"). One row is one change to one memory or entity: its kind, its target, the old value, the new value, the candidate it came from, and a status (`open`, `accepted`, `declined`).
3. A segment is done when its v7 candidates exist. This is what makes the run restartable. A kill between the candidates and the suggestions is repaired at the next start: the diff runs again for any segment that has v7 candidates and no suggestion marker.

#### How a change is found

One pure function compares a kept memory with the v7 output for its segment.

1. A v7 memory matches a kept memory when their word spans overlap by more than half of the shorter span.
2. A kept memory with no match gets no suggestion.
3. A v7 memory with no match is ignored. See owner's call 3.
4. The function offers only these kinds of suggestion:

| Kind | Offered when | Never offered when |
| --- | --- | --- |
| Title | The v7 title differs from the stored title. | The person renamed the memory (the stored title differs from its candidate's title). |
| About a person, place or thing | The memory is a fact, feeling or goal with no detail link, and v7 gives an `about_ref` that resolves to a stored entity. | The memory has a detail link. The entity is hidden. |
| About you | The memory's detail link, or its person mention, points at a person whose name is the owner's. | — |
| This person is you | A stored person's match key equals the owner's name or alias. One suggestion per person, not per memory. | The person has a relation ("my cousin"). |
| This name is a group | A stored person has another name that the group-phrase function calls a group ("our parents"). Accepting removes the name. It changes no memory. | — |

5. It never offers: a new memory, a deletion, a change of kind, a date, a change to the quote, a story or chapter change. Dates stay with the resolver and the person (`docs/DECISIONS.md`, 2026-10-23).
6. It never offers a change to a memory the person dismissed or hid.
7. An `about_ref` that names a person who is not stored makes no suggestion. The second read creates no person, place or thing.

#### How the person sees it

1. No count sits on a tab or a row. One quiet line shows on You, under the portrait: "A second read found a few things. Look?" It shows only while open suggestions exist.
2. The review screen groups suggestions by what they are about, not by memory, so that one decision covers many lines:
   - "These sound like they are about Maya." Then each quote, each with a tick that is on. One button: "Show on Maya's page".
   - "These are about you." The same shape.
   - "Jordan is you?" One line, Yes or No.
   - "Clearer titles." Each row shows the old title and the new one.
3. Each quote plays its own recording, so the person decides by ear.
4. Accepting a group is one write. A notice with Undo shows for 6 seconds.
5. "Not now" leaves the group open. "No" declines it; a declined suggestion is never offered again, by this read or a later one.
6. The screen never says how many are left (PRINCIPLES 9).
7. Accepting "This person is you" moves that person's links to the owner, adds the name as an alias of the owner, and deletes the person. It asks first, because it cannot be undone after the notice goes.

#### Sessions with a heavy moment

1. The second read classifies disclosure as a first read does. It must not show a disclosure card and must not change the stored flag of a session.
2. A suggestion from a session with a heavy moment is offered like any other. The review screen shows quotes the person already kept. It adds no words of its own about them.

#### Cost and failure

1. The run makes one model call per segment. The start screen must show the number of recordings before the person starts.
2. A failed call leaves the segment not done. The run goes on to the next segment and tries the failed ones once more at the end. The screen then says how many recordings it could not read.
3. With no key or no network the row says so and does not start.

## Data

- A2 adds no column and no migration. The tables are small, so a lookup compares match keys in Swift (`docs/plans/2026-11-16-extractor-v7.md`, decision 1). An earlier draft of this spec asked for a stored match-key column.
- A3 adds the suggestion table and a marker for a segment whose diff is done.
- S4 (Photos) plans migration v13. A3 takes the next free number after whatever is on `main` when it merges. The first PR to merge keeps its number (`docs/plans/2026-11-15-sections.md`, "Rules for the order").
- `BackupManifest` does not change. A backup made after A3 carries open suggestions inside the database file.
- The server stays absent. Nothing here stores user content outside the device.

## Principles

- **1, the person is the author.** No title, link or merge of meaning is applied without the person's yes. Stored spelling is never changed.
- **5, uncertainty is shown.** v7 keeps every v6 rule on confidence and anchors. The second read offers no dates.
- **9, never a database to maintain.** The second read asks in groups, shows no count, and asks once.
- **Safety.** Disclosure rules are copied word for word and tested. The second read never raises a disclosure card.

## Owner's calls

Each has a recommendation. The spec above assumes the recommendation. The owner took every recommendation on 2026-11-16 except two: call 4 is open, and call 7 changed to A1, then A2 after Photos merges, then A3.

1. **Repairing exact duplicates: silent or asked?** Three stories with the same title, and "Ohio." beside "Ohio", exist because of bugs, not because of anything the person chose. Recommendation: merge them once, without asking, when the match keys are equal and the type is the same; show one notice at the next launch ("Joined 2 copies of Ohio."). Cost if wrong: two things the person meant to keep apart become one, and there is no entity split today. The other choice is to put them in the A3 review screen, which delays the fix until A3.
2. **The owner's name in the packet.** Recommendation: send it. It is the only way the model can know that a spoken name is the speaker. Cost if wrong: the name reaches the provider in every call, not only when spoken.
3. **Memories that v7 finds and v6 missed.** Recommendation: ignore them in the first second read. Offering them would put the whole archive back in front of the person as cards. Cost: some told moments stay unsorted. They are still in the recording and the transcript.
4. **Does the second read change kinds?** v7 may call a kept `event` a `fact`. Recommendation: no. The person can change a kind on the memory page, and a kind change moves a memory between the Timeline and You, which is a large effect for a suggestion.
5. **Where the second read's line shows.** Recommendation: on You only. The other choice is the end of the Timeline, beside the audit's "3 dates to check".
6. **Chapter ranges.** Recommendation: a chapter shows no dates until the person states them (now in `docs/specs/2026-11-16-timeline.md`, "The model of a chapter", rule 5). The other choice shows the member span marked as a guess ("around 2017–18"). The audit's example shows why that misleads: one dated memory stood for four years.
7. **Which PR first.** Recommendation: A2, then A1, then A3. A2 stops new recordings from adding to the problem, and A3 needs it. A1 is independent and smaller.

## Out of scope

- Life periods, the single year axis and "Outside any chapter" (S6).
- Quote cleanup and "in N moments" (done in S2).
- Interviewer tuning and prompt v2 (M8 PR 4).
- A split action for entities.
- Any new memory kind or schema field in the extractor output.

## Open facts

These could not be read from the code. They need the owner's database or a device.

- Which path made the owner-named person in the owner's data: a typed name that differs from the spoken one, or "New person" on a card.
- Which path made the empty untitled chapter.
- How many segments the 22 sessions hold, which sets the cost of the second read.
