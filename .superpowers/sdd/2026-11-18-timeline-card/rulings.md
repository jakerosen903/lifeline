# Rulings — plan: docs/plans/2026-11-18-timeline-card.md

Each ruling: what was decided, why, and what it costs if it is wrong.

R1 (pre-flight, Task 5). `writeSpine` is not changed. `SpineUITests` and `ChaptersUITests` count rows, gaps and tags on that seed, and a new story would move them. `testOpeningAStoryMovesTheFrameWithoutAScroll` uses the seed that already has a story on the Timeline (`launchWith…` for SameStoryUITests) if one has a dated story; if none has, the test is left out and the device checklist covers it. Cost if wrong: Review Focus 1's story case has only a kit guard.

R2 (pre-flight, Task 6). The docs are written in Task 6. The one full UI run and the screenshots are made by the controller after the final review's fix wave, on the final code.

R3 (Task 4, implementer finding). A spine row is "on screen" when at least half of its frame is inside the List's own frame (`onGeometryChange`), and `onDisappear` clears it. The plan's `onScrollVisibilityChange` fired `true` and never `false` in this List, and its fallback (`onAppear`/`onDisappear`) counts a row hidden under the pinned card as visible, so the frame never moved. Why: the List's frame is the area below the card and above the record bar, which is what "on screen" means to a person. Cost if wrong: one modifier on the row; the kit does not change.

R4 (Task 4, implementer finding). `DuringLine` picks how many names fit with `ViewThatFits(in: .vertical)` against a box one line tall (two at accessibility sizes). The plan's horizontal form cannot allow a second line, because a horizontal fit measures one line's width. Cost if wrong: layout only.

R5 (Task 5, pre-dispatch). `testTheCardStaysWhileTheListScrolls` does not compare the card's `minY` with its launch value: the large title collapses on a scroll and the card moves up with it (176 to 124 points), which is "under the title" as the spec says. The test asserts that after the scroll the card is hittable, its top is not lower than at launch, and its bottom is above the top of the first hittable spine row. Cost if wrong: one assertion.

R6 (Task 5, implementer finding; replaces the last clause of R5). Rows scroll under the pinned card, so a row can be hittable while its top is above the card's bottom. `testTheCardStaysWhileTheListScrolls` asserts that the card is hittable, that its top is not lower than at launch, and that the middle of the first hittable spine row is below the card's bottom. Cost if wrong: one assertion.
