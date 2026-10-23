# Design screens

Sources exported from the Design canvas (live, editable copy: https://claude.ai/artifact/6vReaCCBrkFqzSkMk6JfRN). Each `.dc.html` is one artboard; `canvas.json` is the layout index with notes. Phone frames are 390×844. Palette: linen `#F6F0E4`, ink `#332A23`, olive `#5F7046` (actions), ochre `#C8893F` (time and uncertainty). Type: Fraunces for memory titles, Inter for UI.

## Phase 1 hero flow

| File | Screen | What it shows |
| --- | --- | --- |
| Main.dc.html | Session | Live transcript, "Sounds like a memory" card with fuzzy time and people, one-tap add |
| Timeline.dc.html | Timeline | Chapters as structure, approximate dates rendered honestly, a floating memory waiting for an anchor |
| Event.dc.html | Memory detail | Audio in the person's voice, narrative, people and place chips, "ask Maya" hook |
| Replay.dc.html | Chapter replay | Plays a chapter's memories as a story; "then and now" prompt |
| People.dc.html | People | "Who's this?" queue; resolve a mention to a contact or an existing person; aliases |

## Fuzzy time options

| File | Option | Model |
| --- | --- | --- |
| FuzzyA.dc.html | Collections | Undated memories attach to a named collection with a derived span |
| FuzzyB.dc.html | Ranges | Likely and possible bands on a true year axis; relative questions narrow them |
| FuzzyC.dc.html | Shelf | Undated memories on a "somewhere in childhood" shelf grouped by theme |
| Refine.dc.html | Refine a range | A collection spanning a whole life; one memory's range tightened by relative questions, a photo, or a known year |

Decision: the data model is B (every event has a range, plus optional collection membership). The default view is A, with C's shelf as fallback for memories with neither date nor collection.

## Onboarding and session arc

| File | Screen | What it shows |
| --- | --- | --- |
| Onboard1.dc.html | First open | One question, mic, three alternate prompts; no form |
| Onboard2.dc.html | What I'm learning | Baseline facts appearing as spoken; "later" items seed the curiosity list |
| Onboard3.dc.html | Doors left open | Session summary; one invitation (tell it now / later / skip); anchor questions show their payoff |
| WindDown.dc.html | Wind-down | Early landing after a heavy session; keep / private / let go; one light question |

## Phase 2 props

| File | Screen | What it shows |
| --- | --- | --- |
| Photo1.dc.html | Pick favorites | A few chosen photos; EXIF dates as facts, guessed eras as ochre |
| Photo2.dc.html | Tell me about this one | Photo as prompt; "who's this?" tap-to-name (V1: manual; later: on-device grouping) |
| Photo3.dc.html | Photo cluster nudge | 23 photos in one week shown as a suggestion, not an event |
| Music1.dc.html | Songs from an era | Era charts for the year the person was 16; a pick leads into a story prompt |
| Music2.dc.html | A song on repeat | A play spike from an optional streaming-history upload beside nearby timeline events |

Sample content (names, places, dates) is invented.

## App icon

`icon/lifeline-icon.svg` (light) and `icon/lifeline-icon-dark.svg` are the sources; `ios/Assets.xcassets/AppIcon.appiconset/` holds the 1024 px light, dark and tinted PNGs with a `Contents.json` Xcode reads directly. The mark: five tree rings, the years of a life read in cross-section, with a soft split through them the way rings open around a knot, and one ochre ring for a year that mattered. Same palette as the screens. Chosen 2026-10-22 over a rising-line mark, a radial waveform and a constellation.
