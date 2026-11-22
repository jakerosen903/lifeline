# Five sections: Timeline, People, Places, Things, You

Status: approved by the owner, 2026-11-15, with every recommendation under "Owner's calls" accepted. Spec, not plan. Plan: `docs/plans/2026-11-15-sections.md`. Mock-ups: `docs/design/Sections.html` (eight phone screens; sample content is invented). Points the owner decided are marked **(owner)**. Calls the owner did not make are marked **(my call)**. Calls only the owner can make are listed at the end.

This spec builds on the UI audit of 2026-10-26 (`docs/specs/2026-10-26-ui-audit.md` on branch `ui-audit`, not yet on `main`). It keeps the audit's findings and its data fixes. It replaces the audit's navigation call.

## Scope, and what this spec is not

The app gets five sections, each with a view shaped to its data: Timeline, People, Places, Things, You. Every section links to the others. Timeline stays the home screen and the most important one. **(owner)**

Not in this spec:

- Extractor v7, the chapter bug fixes and the card follow-ups. The audit specifies them and they get their own plan. This spec depends on them and does not design them. The re-read of existing memories (audit, owner's call 3) needs its own spec section before it is planned.
- Replay and narrated playback (M9, canvases R5, R8, R9).
- Automatic photo suggestions and face grouping. This spec only keeps them possible.
- Family sharing, a web viewer, an iPad layout.

## Why

The owner used the app for a month. The audit found that one screen carries everything: the timeline, a flat "About" list and six unlabeled icons. People, places and things have pages, but nothing invites the person to look at their life through them. The owner wants each kind of thing to have its own home, and wants the homes to show connections and change over time.

## Goals

1. **Five labeled sections.** A tab bar with Timeline, People, Places, Things and You, plus search. **(owner)**
2. **Each section has its own shape.** Timeline is a spine. People is a grid of faces. **(owner)** Places is a map. **(owner)** Things is a shelf. **(owner)** You is a portrait in the person's own words and voice. **(owner: a tab of its own)**
3. **One thread through all of them.** Every moment names who and where. Every page lists what it is often with. The same life strip shows "when" everywhere.
4. **Telling stays one tap away.** The record bar is on every tab and names the page the person is on.
5. **Every screen is honest with thin data.** A section with little in it shows less. It never shows an empty frame or a task.

## Non-goals and anti-goals

- No screen may ask the person to complete a record. No "add photo" slot, no "introduce" queue, no count of places the app could not find (PRINCIPLES 9).
- No inferred span, location, home or "still have it" may show as fact (PRINCIPLES 5, non-negotiable 3).
- No tab for Ideas alone. Ideas are one part of You.
- The sections must not push telling aside. If stories told per week drop after the tabs ship, the design failed.

## Constraints and hard limits

- **Data.** The audit found 3 detail links in 37 memories, about 11 dated moments, and duplicate and generic places. Life strips, "Often with", period shelves and the map need links, dates and clean entities. They look thin until extractor v7 re-reads the archive.
- **Places cannot be looked up from personal names.** A geocoder returns a confident wrong answer for "Grandma's kitchen". Only the person can place it.
- **A map sends data to Apple.** Map tiles, search and geocoding all go to Apple. This is a new recipient beside Anthropic.
- **No public API groups faces by identity.** PhotoKit gives date and location only. Vision gives face rectangles only.
- **The store has no location and no photo today.** The `place.lat` and `place.lon` columns from migration v1 are dead and must stay dead.
- **Backup.** `Store/Backup.swift` exports only `audio/*.m4a`. Photos would be lost on export until it changes. `BackupManifest` is strict `Codable`; a new field must be optional.
- **Tests.** `origin/main` has 57 UI tests. `home.start`, `timeline.sessions`, `home.sessionRow` and `home.settings` appear in most of them.

## Approaches

Three ways to give the archive more than one screen were compared. Four reviewers (product, HIG, feasibility, a dissenter) read the first mock-up.

| Approach | What it is | Trade-off |
| --- | --- | --- |
| A. A tab for each section | Timeline, People, Places, Things, You, each with its own view | The richest. Places and Things are thin today. Needs location and photo storage. |
| B. Timeline, People, Listen | Places and things are filter chips on the timeline; a Listen tab holds replay | Fits the data today. Gives up the map and the shelf as places to go. Listen depends on M9. |
| C. Timeline and "Your world" | One browse tab with a People / Places / Things switch, plain lists | The cheapest proof. Every kind gets the same list, which is the problem the owner named. |

**Chosen: A, built in the order below.** **(owner, 2026-11-15)** The owner asked for sections with distinct shapes. The reviews changed the order and the sparse-data rules, not the direction. Each section ships in its simple form first and gains its rich form when its data exists.

## Design

### Shell

- The root is a tab view with five tabs: Timeline, People, Places, Things, You. Each tab has a symbol and a label.
- Search is the trailing search tab. It matches the titles of memories, people, places, things and ideas, and the text of memories. It does not use embeddings. It is its own build step. **(my call)** Changed 2026-11-19: search is a Search button on every tab's top bar; see DECISIONS.
- The record bar is the tab view's bottom accessory. It shows on every tab and on pushed pages.
  - On a tab it reads "Tell a story". On an entity page it reads "Tell a story about {title}". On You it reads "Tell a story about yourself".
  - A session started from a page stores that entity as its subject. The opening line is the entity's scene question from the curiosity list, or "Tell me about {title}." when there is none. The app does not link the session's memories to the subject; the extractor links only what the person says. **(my call; see Owner's calls)**
  - The whole bar is the tap target. "Start" begins a quick story. A long press or the bar's menu offers "Settle in". **(my call)**
  - A start error shows on the bar, on every tab.
- Timeline's toolbar has a labeled "Sessions" button **(owner)** and one overflow menu. The menu holds "Show hidden memories" and the tag filter until the Timeline step replaces them.
- The "Who's this?" queue (`PeopleScreen`) opens from the People tab's overflow menu as "Names you mentioned". It shows no count. **(my call)**
- The session cover and its view model move from the timeline to the app root. The launch resume and the scene-phase check read the root.

### The life strip

A thin axis from the person's birth year to now, with one mark for each dated moment linked to the subject.

- It shows marks only. It shows a span bar only when the person stated the span (`Entity.range` is not `.unplaced`).
- A sentence under it says the same thing in words: "In 12 moments, most between 1999 and 2003".
- It is one accessibility element. Its label is that sentence.
- Its height follows Dynamic Type.
- It is hidden when the subject has fewer than two dated moments. The sentence alone remains.
- It appears on entity pages and at the top of Timeline. It does not appear on rows or tiles.
- With no birth date in the profile, the axis starts at the earliest dated moment.

### Life periods

Timeline, the Things shelf and the Places menu all group by life period.

- A named period is a `Chapter` the person titled. No new table.
- The years no chapter covers are split into computed periods by the person's age: "Childhood" (0 to 12), "Teens" (13 to 19), then "Twenties", "Thirties" and so on. These names state an age, which follows from the birth date. They never name a life event such as "College". **(my call; see Owner's calls)**
- A computed period shows "by age" beside its years. The person can name it; that creates a chapter over the same years.
- With no birth date, computed periods are decades: "The 2000s".
- A computed period with no dated moment does not show.
- `LifePeriods` is a pure function in `Domain/` over the birth date, the chapters and the dated moments. It stores nothing.

### Timeline

The timeline keeps its vertical spine and its ochre thread. This spec adopts the audit's timeline direction and adds to it.

- One whole-life strip at the top shows where the story is thick and thin. A frame on it marks the years on screen.
- Moments group into life periods (see "Life periods").
- The date sits above each title. An uncertain date reads "around 1999".
- Each moment shows the people and the place linked to it. A tap opens that page.
- A story shows as one card with its moment count.
- A moment shows a photo when one is linked to it.
- "Not placed in time yet" is one band at the end. It opens the undated memories. Rows inside carry no buttons; actions stay in the row menu.
- One quiet line at the end reads "3 dates to check".
- No year scrubber on the edge.

### People

- A grid of faces, three columns, falling to two columns and then a list at accessibility text sizes. **(owner: grid)**
- A tile is a rounded square. It holds the person's photo, or the first letter of their name on one of three quiet tints. The tint is chosen from the entity's id, so it never changes.
- The name and the person's own words for them ("my sister") always show under the tile.
- A sort menu offers "Most told", "First in your story" and "By name".
- No tile carries an add-photo mark. Unresolved mentions do not show here; they stay on cards.
- The owner is never a tile (audit F10).

### Places

- The section opens on a map when three or more places have a location. Otherwise it opens on the list. **(my call)**
- The map has two controls: a menu of life periods, and "List".
- A pin shows a place the person located. Its label shows the place's title and its moment count. Overlapping pins cluster.
- A place the app located by lookup shows as a dashed area with the words "about here?" on an opaque label. It becomes a pin only when the person confirms it.
- Tapping a pin selects it and shows one card with the title, moment count and how the location was set. Tapping the card opens the place's page.
- The list shows every place, located or not, with no count of unlocated ones. It is the VoiceOver route through the section.
- The Apple logo and legal link stay visible.
- No line joins homes. The app does not know which places were homes.

**How a place gets a location:**

1. The person opens a place's page and chooses "Put on the map" from its menu. They search or drop a pin. Origin: `confirmed`.
2. The app may look up one place at a time, only when the person opens the Places map, only for a place not excluded from AI, and only after the owner's call on Apple as a recipient. Origin: `guessed`, with a radius from the result's region. **(my call: off until the owner's call)**

### Things

- A shelf of tiles in two columns, all one height.
- A tile with a photo shows the photo, the title and the moment count.
- A tile without a photo shows the title in the serif face, and one quote when a memory is about the thing. The quote passes the audit's filler-word cleanup.
- Tiles group by life period, from the thing's dated moments. Things with no dated moment sit under "Not placed in time yet". With no periods, the shelf is one flat grid.
- No year range and no "still with you" group. Nothing in the store states either.

### Entity page (person, place, thing)

One layout for all three, in this order:

1. Title and the person's own words. A photo header shows only when a photo exists.
2. The life strip and its sentence.
3. "What you've said about her" (or him, them, it): the detail memories.
4. "Often with": the people, places and things that share two or more moments with this one, with counts. Hidden when none qualify.
5. Photos, shown only when one exists.
6. Moments in order.

"Add a photo" and "Put on the map" live in the page's menu. A place's page shows a small map when it has a location.

### You

The fifth tab. It holds what the person said about themselves, which is the largest part of the archive (audit F9). It reads as a portrait, not a list.

- **Header.** The person's name and birth line. Photos of the person sit on their life strip at their years. With no photo, the strip shows alone.
- **A lead line.** One detail in large type, with a control that plays it. The line is chosen from the details at random each time the tab opens.
- **Four parts**, each drawn its own way. A part with nothing in it does not show.
  - "Who you are": memories of kind `fact` about the owner. Chips filter by domain tag.
  - "How it felt": kind `feeling`. Each one names what it is about and links there.
  - "What you think": the idea entities, in the person's exact words.
  - "What you're hoping for": kind `goal`.
- **Every line plays.** A play control plays the span of the recording where the person said it, through the existing `SegmentPlayer`. A line with no audio span shows no control.
- Quotes pass the audit's filler-word cleanup. The audio is never changed.
- "Settings" is a labeled toolbar button.
- The "About" section leaves Timeline.

### Photos

- The person chooses "Add a photo" from the menu of a person, place, thing or memory page, or of You. The system picker opens. The app asks for no library permission.
- The app stores a downscaled copy in `<root>/Lifeline/photos/`. It also stores the asset identifier when the picker gives one, for the later automatic path.
- The app reads the photo's date and location from its metadata and stores both with origin `exif`. The photos step only stores them. It shows the date under the photo as "taken {date}" and changes no memory, entity or location. A later spec decides where they are offered as suggestions.
- A photo links to a person, place, thing or memory. One photo per subject can be its cover.
- Backup export must include `photos/`. The manifest's photo count is an optional field.
- Later, without schema change: library clusters by date and location that only suggest (canvas Photo3), and manual face naming (canvas Photo2).

### Data

Three migrations, one for each step that needs it:

- v12 (shell): `session.subject_entity_id NULL` and `session.started_from` (`tab` or `page`).
- v13 (photos): the two photo tables below.
- v14 (places): `entity_location`.

Tables:

- `entity_location(entity_id PK, lat, lon, radius_m NULL, origin, query_text, resolved_name)`. `origin` is `confirmed` or `guessed`.
- `photo(id, file_name, asset_local_id NULL, taken_at NULL, taken_origin, lat NULL, lon NULL, sha256)`.
- `photo_link(photo_id, element_kind, element_id, role, sort_order)`. `role` is `cover` or `attached`.

Queries, in `EntityRepository`:

- `coOccurrences(of:)`: one self-join on `moment_entity`, returning entities and shared-moment counts.
- `strips(type:)`: one batched query for the marks of every entity of a type. It replaces the per-row `derivedSpan` calls.

A pure `LifeStrip` type in `Domain/` turns a birth year, the current year and a list of ranges into mark positions and the sentence. It has its own tests.

### Appearance and accessibility

- Secondary text must reach 4.5:1. `Theme.stone` (#A89A85, 2.43:1 on linen) is for hairlines only. Add a text grey of #6D6153 (5.9:1). This also fixes the shipped screens.
- Metadata uses the footnote text style or larger. No fixed sizes under 11 points.
- Every control is at least 44 by 44 points.
- Nothing is told by colour alone: uncertainty has a word, the selected pin has an outline.
- Every colour gets a dark value and an increased-contrast value. Bars, the accessory and sheets use system materials. The dark map style and the photo header's scrim are defined in the plan's first step.

## Build order

Each step is one PR with its own tests. Steps 1 and 2 run side by side. **(owner, 2026-11-15)**

| Step | What | Size | Needs |
| --- | --- | --- | --- |
| 1 | Merge `cards-b`; audit bugs; extractor v7 with the owner-is-self rule. Planned from the audit spec, in its own plan. | L | — |
| 2 | Shell: five tabs, record bar with subject, Sessions button, text grey, UI-test helpers, v12. People, Places and Things show the current entity lists. You shows the owner's page, the ideas list and Settings. The "About" section stays on Timeline until step 4. | M | `cards-b` merged |
| 3 | Repository queries and `LifeStrip`; entity page, including the audit's item 5 (details on pages, quote cleanup, "in N moments"); People grid | M | 2 |
| 4 | You as a portrait: four parts, play controls, lead line | M | 3 |
| 5 | Photos: v13, picker, cover, backup export | M | 3 |
| 6 | `LifePeriods`; Timeline with one axis, periods and the undated band | L | 1 |
| 7 | Things shelf | M | 1, 6 |
| 8 | Search | M | 2 |
| 9 | Places: v14, list, map, pins the person sets | M | owner's call 1 |
| 10 | Guessed locations as "about here?" | M | 9 |

## What to watch after step 3

For two weeks of the owner's use, read from the sessions table: stories told per week against the month before, and sessions started from a page against sessions started from a tab. The app logs nothing else. The owner reports which tabs they open.

## Decisions to log when this spec is approved

- The tab bar is Timeline, People, Places, Things, You and search. This supersedes owner's call 4 of the UI audit (Timeline, People, Sessions, Settings).
- Photos are copied into the app's folder and included in backup export.

## Owner's calls

All five were decided on 2026-11-15 as recommended.

1. **Apple as a recipient.** May the app show an Apple map and send place searches to Apple? Without this, Places is a list. Recommendation: yes for the map and for searches the person types; guessed lookups stay off until you have used step 9.
2. **Life period names.** The audit's examples included "College", which names something the person did not say. Recommendation: computed periods are named by age only ("Childhood", "Teens", "Twenties"), and any other name comes from you.
3. **Photos and the phone's cloud backup.** Audio copies stay out of it (decision of 2026-10-24). Recommendation: treat photos the same way.
4. **The record bar's second kind.** Recommendation: "Start" is a quick story; "Settle in" is in the bar's menu.

5. **"Tell a story about Maya".** Recommendation: the session records Maya as its subject and opens with a scene question about her. It does not link what you say to Maya unless you name her.

## Left to the builder

- Symbol choices for the five tabs.
- Where a dated moment with an uncertain range sits on the life strip.
- How a merge of two entities treats their locations and photos.
- Whether the search tab's results group by kind or rank together.
- The exact downscale size for stored photos.
- How to hide or keep the bottom accessory while a sheet is up, and its hittability in UI tests when the tab bar minimizes.
