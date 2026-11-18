# Rulings — plan: docs/plans/2026-11-18-timeline-card.md

Each ruling: what was decided, why, and what it costs if it is wrong.

R1 (pre-flight, Task 5). `writeSpine` is not changed. `SpineUITests` and `ChaptersUITests` count rows, gaps and tags on that seed, and a new story would move them. `testOpeningAStoryMovesTheFrameWithoutAScroll` uses the seed that already has a story on the Timeline (`launchWith…` for SameStoryUITests) if one has a dated story; if none has, the test is left out and the device checklist covers it. Cost if wrong: Review Focus 1's story case has only a kit guard.

R2 (pre-flight, Task 6). The docs are written in Task 6. The one full UI run and the screenshots are made by the controller after the final review's fix wave, on the final code.
