# Rulings — plan: docs/plans/2026-11-18-timeline-chapters.md

Each ruling: what was decided, why, and what it costs if it is wrong.

R1 (pre-flight, Task 4). `ChapterActions` holds the store only and owns the one write path for a tag: `add(_:to:)` and `takeOut(_:)` write the tag and then prune. `CandidateActions.assign(memory:toChapter:)` stays as a one-line forward to them, and `acceptHint` makes a `ChapterActions(store:)` and calls `add(_:toChapterNamed:)`. Why: the plan's text has each type call the other. Cost if wrong: none in behaviour; one forward.
