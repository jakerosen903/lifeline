# Rulings — plan: docs/plans/2026-11-18-timeline-chapters.md

Each ruling: what was decided, why, and what it costs if it is wrong.

R1 (pre-flight, Task 4). `ChapterActions` holds the store only and owns the one write path for a tag: `add(_:to:)` and `takeOut(_:)` write the tag and then prune. `CandidateActions.assign(memory:toChapter:)` stays as a one-line forward to them, and `acceptHint` makes a `ChapterActions(store:)` and calls `add(_:toChapterNamed:)`. Why: the plan's text has each type call the other. Cost if wrong: none in behaviour; one forward.

R2 (Task 3, implementer concern). Inside one `run()`, a chapter's member span comes from the ranges in the store at the start of that run. A moment that the same run places does not widen the span until the next run. Why: before this plan the stored chapter range was refreshed only at the end of a run, so a chain settled on the next run then too; this is no regression, and `run()` stays idempotent. Cost if wrong: a moment anchored to a chapter is placed one resolver run late.

R3 (Task 7, implementer concern). The tag's accessibility label stays the chapter's name, with the hint "Opens this chapter". The plan's "Chapter: {name}" is withdrawn. Why: `SpineUITests.testAChapterTheOwnerNamedShowsAsATag` asserts the label is the name; the row's own label already says the chapter; VoiceOver reads the trait "button". An existing assertion does not change for a label the spec does not ask for. Cost if wrong: one modifier.

R4 (Task 7, implementer concern). `LifeMap.Row` gets `isOpenEnded: Bool`, so the view does not repeat the kit's "no stated end" rule. Why: one rule in one place. Cost if wrong: one field and one test.

R5 (Task 7). Two files the plan did not list are accepted: `ChapterRemovedNotice.swift` and `LifeMapAxis.swift`. Why: one responsibility per file (CLAUDE.md). The task reviewer judges their content.
