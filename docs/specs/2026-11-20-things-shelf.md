# The Things shelf

Status: spec for step 7 (S7) of the five-sections design. Written 2026-11-20 from the five bullets under "Things" in `docs/specs/2026-11-15-five-sections.md`. The owner said to build with the builder's recommendations. Each recommendation is under "Builder's defaults the owner can overrule". Plan: `docs/plans/2026-11-20-things-shelf.md`.

Mock-up: `docs/design/Sections.html`, the fourth phone ("Things") and its notes. The mock-up was drawn before S6c. Its period names and year ranges are out of date (see "Where the spec did not fit the code").

## Problem

The Things tab shows today's entity list (`EntityListScreen` for `.thing`). Each row is a title and a span line ("in 1995", "no dates yet"). Every thing looks the same. Nothing shows a photo, the person's words, or when in the life the thing belongs. The five-sections spec asks for a shelf: tiles that show a photo or the person's words, grouped by the stretch of life they belong to.

## Terms

- **Thing:** an entity of type `thing` that is not hidden.
- **Tile:** one thing on the shelf.
- **Key photo:** the first photo of a thing's page (`PhotoRole.cover` in code). The person reads "key photo", never "cover".
- **Moment of a thing:** a told, visible memory of kind `event` or `other` that names the thing (`EntitySummary.momentRanges`).
- **Dated:** a range with an earliest and a latest date (`TimeRange.isDated`). The Timeline's spine uses the same test.
- **Placing date:** the start the spine uses for a dated range: the likely start when the likely band has both ends, else the earliest date.
- **Period:** a stretch of life named by age ("Childhood", "Teens", "Twenties") or, with no birth date, by decade ("The 1990s"). It is `LifePeriod.containing(year:birthYear:)`, the function the Timeline uses.
- **Detail:** a memory linked to an entity with the relation `detail`. It is what the person said about the thing. The entity page lists it under "What you've said about it".
- **Quote:** the person's words from one detail, cleaned by `ReadableQuote` (the audit's filler-word cleanup).

## Design

### The screen, top to bottom

1. The navigation title "Things". The toolbar keeps the tag filter (`entities.tagFilter`). It shows only when a tag exists, as today.
2. The groups, oldest period first. Each group has a heading and a grid of tiles.
3. The last group is "Not placed in time yet", when it has a tile.

The record bar and the tab bar do not change. On the shelf the bar reads "Tell a story".

### The grid

1. The grid has two columns.
2. All tiles have one height. The height is 176 points at the default text size and follows Dynamic Type.
3. At the accessibility text sizes the grid has one column. Each tile is as tall as its text needs. Nothing is cut.

### The tile with a photo

A thing has a photo on the shelf when it has a key photo.

1. The key photo fills the top of the tile, clipped to the tile's corners.
2. Under it: the title in the serif face, then the moment count.
3. The count reads "1 moment" or "3 moments". A thing with no moment shows no count line.
4. The tile shows no quote and no date.

### The tile without a photo

1. The tile has the sand fill.
2. The title is in the serif face, larger than on a photo tile.
3. Under the title: one quote, in quotation marks, in the serif italic, when a detail of the thing has words left after the cleanup.
4. At the foot: the moment count, as on a photo tile.
5. A tile with no quote and no moment shows its title only. It shows no prompt and no empty slot.

### Grouping by period

1. A thing with a dated stated span (the person used "Add dates" on its page, with both ends) goes into the period of the span's placing date. Its moments do not move it.
2. A thing with no dated stated span goes into the period of its earliest dated moment. "Earliest" is by placing date.
3. A thing shows once on the shelf. It does not repeat in a later period.
4. Every other thing goes into "Not placed in time yet". A half-open stated span places nothing, so the thing's dated moments place it, as in rule 2.

Rules 1 to 4 were changed on 2026-11-20 by ruling R5.
5. The heading of a period is the Timeline's waypoint text: "Teens · by your age" for a period by age, "The 1990s" for a decade. It is a header for VoiceOver.
6. The heading of the last group is "Not placed in time yet". It is a header for VoiceOver.
7. A period with no tile does not show.

### A guess that decides the group

1. A tile placed by its moments is placed by a guess when no dated moment in its period is settled by the person's word. Settled is `TimeRange.isSettled`: stated, confirmed, or from a photo. An inferred or derived date is the app's guess.
2. A confirmed relation ("before Graduation (2004)", `TimeRange.isConfirmedRelation`) does not clear the line. The person confirmed the relation, but its year comes from the builder's slack, so the period is the app's arithmetic. The Timeline uses the same test to show such a date as words. Changed 2026-11-20 by ruling R4.
3. The person's own hedge ("around 1998", origin `stated`) is not the app's guess. It does not give the line.
4. A tile placed by a guess shows one line in the ochre text colour: "Placed by a guess" **(invented copy)**.
5. The line is a word, not a colour alone. VoiceOver reads it in the tile's value.
6. A stated span is settled. It never gives the line.

### The flat grid

1. When no thing is placed, the shelf is one grid with no heading. It does not say "Not placed in time yet".
2. When one or more things are placed, every group has its heading.

### Order

1. Groups: in life order, by the earliest placing year of their tiles. "Not placed in time yet" is last.
2. Tiles in a period: by placing date, then by title ignoring case, then by id.
3. Tiles under "Not placed in time yet", and in the flat grid: by title ignoring case, then by id.

### A tap

1. A tap on a tile opens the thing's page (`EntityScreen`) in the Things tab's stack.
2. On the page the record bar reads "Tell a story about {title}", as on every entity page.
3. Back returns to the shelf. The shelf reads again when it appears, when the page reports a change, and when a session cover closes.

### VoiceOver

1. Each tile is one button. Its label is the title. Its value is the count, the guess line and the quote, joined by ". ". Example: "1 moment. Placed by a guess. “He clanked all night”".
2. The photo is hidden from VoiceOver. The app does not describe a photo.

### The empty state

1. With no thing: one line, "Nothing yet. They appear as you tell stories." This is the copy of the list today.
2. With a tag filter that matches nothing: "Nothing tagged “{tag}”.", as today.
3. A read error: "Could not show your things: {reason}" **(invented copy)**, in place of the grid.

### What leaves the screen

- The list rows and their span lines ("in 1995", "no dates yet").
- From the mock-up, not built: the summary "11 things you've talked about", the "By when" control, the period names "From childhood" and "From the Boston years", and the year range beside each heading.

## Data

- Reads only. No migration. No new table or column.
- The shelf reads, in a fixed number of statements however many things there are:
  - `EntityRepository.summaries(type: .thing)`: each visible thing, its moment ranges and its stated span.
  - `PhotoRepository.covers(type: .thing)`: each visible thing's key photo.
  - `ProfileRepository.ownerBirthDate()`: the birth year for the periods.
  - One new read, `EntityRepository.details(type:)`: the told, visible details of every entity of a type, oldest told first.
  - `MemoryRepository.firstTellings(kinds:)` and `SessionRepository.heavySessionIDs()`: to leave out a quote from a heavy session.
- The grouping, the order, the guess line and the quote choice are pure functions in the kit, with tests.
- The period rule is the Timeline's. `SpineLayout` exposes its placing date so that both use one rule.

## Edge cases

- **A thing with moments in two periods.** It shows once. With a dated stated span, it shows in the span's period. With no dated span, it shows in the earlier period.
- **A thing with only undated moments.** It is under "Not placed in time yet", with its count.
- **A thing with only facts.** It has no moment, so no count. It is under "Not placed in time yet", or under its stated span's period. A fact linked as a detail can give its quote.
- **A hidden thing.** It is not on the shelf. Its key photo is not read. This is as today.
- **A hidden memory as the only source of a quote.** No quote shows. The read leaves hidden and untold memories out.
- **A hidden memory as the only source of a date.** It is not a moment of the thing. The thing has no dated moment and is not placed by it.
- **A guessed date deciding the group.** The tile shows "Placed by a guess". A settled moment in the same period removes the line. A date from a confirmed relation ("before Graduation") does not remove it (ruling R4). A guess in an earlier period still decides the group, and the tile keeps the line.
- **A moment dated before the birth date.** Its period is its decade ("The 1980s"), as on the Timeline. That group comes first.
- **A half-open range** (an earliest date only). It is not dated. It does not place the thing.
- **A very long title.** At the default sizes it wraps to at most three lines and ends with "…". At the accessibility sizes it shows in full. VoiceOver always reads it in full.
- **One thing only.** One tile. With a period, it has its heading. Without one, it is a flat grid of one.
- **Many things.** The grid is lazy. The read stays a fixed number of statements.
- **A photo that fails to load.** The photo area keeps the sand fill. The title and the count stay. The tile does not change size.
- **A quote of only filler words** ("um, uh"). The cleanup leaves nothing. The next detail can give the quote. With none, no quote shows.
- **A detail from a heavy session** (a disclosure, a wish to stop). It never gives the quote, as a line from a heavy session never leads on You.
- **A long quote.** It is cut at 20 words and ends with "…". The tile shows at most four lines of it.
- **No birth date.** The periods are decades ("The 2000s"), with no "by your age".
- **The largest text size.** One column. No text is cut. Every tile is at least 44 points high.
- **VoiceOver.** One button for each tile. The headings are headers, so the rotor moves between periods.
- **A session started from the shelf.** It is not about any thing. The shelf reads again when its cover closes.

## Principles

- **P1, the person is the author.** A period is named by age or decade, never by a life event. The quote is the person's words, cleaned only of filler. The tile never names what the thing meant.
- **P5, uncertainty is shown.** A tile placed by a guess says so in words. No span or year range shows, because nothing the person said gives one for most things. A half-open or hidden date places nothing.
- **P6, hard chapters are doors.** A quote from a heavy session does not show on the shelf each time the tab opens.
- **P9, never a database to maintain.** No count of things, no "add a photo" slot, no "add a date" prompt, no empty frame. "Not placed in time yet" is a heading, not a task. It shows no count.
- **Data posture.** The shelf reads the phone's store only. It sends nothing.

## Suggested PRs

| PR | What | Needs |
| --- | --- | --- |
| S7 | The pure grouping and quote choice, the batched read, the shelf screen and tile, the UI tests, the docs | S6 (on `main`) |

One PR. The step is size M in the five-sections build order.

**Merge with S5 (search, branch `sections-search`, PR 39).** Search adds a "Search" button at `.topBarLeading` on every tab root through `SectionsScreen`. The shelf adds no item at that placement. At merge, keep both sides in `SectionsScreen.swift`, `Dependencies.swift`, `UITestSeed.swift` and `UITestHelpers.swift`. Then run `ThingsUITests` and `SearchUITests`.

## Builder's defaults the owner can overrule

Each one is decided. Each one is one rule in one place, so an overrule changes one function and its tests.

1. **A thing shows once, in one period.** With no dated stated span, it is the period of its earliest dated moment. Cost: a thing that runs through several periods (a car kept for twenty years) shows only in the first.
2. **A dated stated span places the thing, before any moment.** The bullet says "from the thing's dated moments". Without this rule, a thing whose page says "from 1996 to 2002" would sit under "Not placed in time yet", or move to the period of one guessed moment. The person's words about the thing beat the app's guess about one moment (P1). Dated moments place only a thing with no dated stated span. Cost: one rule beyond the bullet; a thing with a stated span and a settled moment outside it sits in the span's period, not the moment's. Changed 2026-11-20 by ruling R5.
3. **"A memory about the thing" is a detail link.** A mention is a moment the thing is in, not a memory about it. Cost: few tiles show a quote until extractor v7 adds detail links (the audit found 3 detail links in 37 memories).
4. **The quote is the oldest told detail that has words after the cleanup, cut at 20 words.** Cost: a later, better line does not show. The person cannot choose the line.
5. **A detail from a heavy session never gives the quote.** Cost: an ordinary line told in a heavy session never shows on the shelf.
6. **Both kinds of tile show the moment count.** The mock-up draws it on both. The bullet names it for the photo tile only. A thing with no moment shows no count. Cost: the tile without a photo is one line fuller than the bullet says.
7. **A tile placed by a guess says "Placed by a guess"** **(invented copy)**. A guess is an unsettled origin (`inferred`, `derived`) or a confirmed relation's year (R4), not the person's own "around". Cost: one more line on some tiles, and new copy. A tile placed by the person's "around 1998" shows no line; the page shows the "around".
8. **Headings are the Timeline's waypoint text, with no year range.** Cost: the mock-up's year ranges ("1994–2006") are gone. They came from spans the person did not state.
9. **Order: life order for groups; by placing date for tiles in a period; by title under "Not placed in time yet".** Cost: no "most told" order and no sort menu.
10. **The flat grid has no heading.** Cost: none known.
11. **One column at the accessibility text sizes; tiles grow to fit there.** Cost: at those sizes the tiles are not one height.
12. **A key photo that cannot load leaves a sand area under the title and count.** Cost: that tile shows no quote, though it has no visible photo.
13. **The tag filter stays.** Two existing UI tests use it on Things. Cost: one control the mock-up does not draw.
14. **No summary count, no "By when" control.** Cost: the mock-up's top line is not built.
15. **A tile is 176 points high at the default size; the title has at most 3 lines and the quote at most 4.** Cost: a long title is cut with "…" at the default sizes. VoiceOver reads it in full.

## Where the spec did not fit the code

- **"A named period is a `Chapter`".** S6c changed this. A chapter never replaces a period (`docs/specs/2026-11-16-timeline.md`, "Periods", rule 4). The shelf uses the computed periods only, as that spec says in rule 5.
- **"Nothing in the store states either" a year range.** The store can hold a stated span for a thing: "Add dates" on its page writes `entity.range`. The shelf uses it, when it is dated, to place the thing before any moment (default 2). The tile still shows no range.
- **"When a memory is about the thing".** The store has no "about" relation. It has `detail` and `mention`. The shelf uses `detail` (default 3).
- **"From the thing's dated moments".** `EntitySummary.momentRanges` also holds undated ranges. "Dated" here is `TimeRange.isDated`, the spine's test. A half-open range does not count.
- **"Reuse the Timeline's grouping".** The Timeline places a story by the span of its members and keeps a moment in a collection off the spine. The shelf places a thing by each moment's own range. The period rule, `LifePeriod.containing` on the placing year, is the same. The placing date moves into one public function in `SpineLayout`, so the two cannot drift.
- **The mock-up.** It predates S6c. "From childhood" and "From the Boston years" name periods by chapter. The year ranges, the count and "By when" are not in the five bullets. None is built.
- **The tag filter.** It is on the Things tab today and is not in the spec. It stays (default 13).

## Out of scope

- A photo on a Timeline row, and photos on Places.
- A sort menu, a search field on the shelf, a "still with you" group, a year range on a tile.
- Choosing which detail gives the quote.
- A thing on more than one period.
- Places (S8) and guessed locations (S9).
- Dark and increased-contrast colour values. They still have no PR.
