# Rulings — plan: docs/plans/2026-11-18-timeline-chapters.md

Each ruling: what was decided, why, and what it costs if it is wrong.

R1 (pre-flight, Task 4). `ChapterActions` holds the store only and owns the one write path for a tag: `add(_:to:)` and `takeOut(_:)` write the tag and then prune. `CandidateActions.assign(memory:toChapter:)` stays as a one-line forward to them, and `acceptHint` makes a `ChapterActions(store:)` and calls `add(_:toChapterNamed:)`. Why: the plan's text has each type call the other. Cost if wrong: none in behaviour; one forward.

R2 (Task 3, implementer concern). Inside one `run()`, a chapter's member span comes from the ranges in the store at the start of that run. A moment that the same run places does not widen the span until the next run. Why: before this plan the stored chapter range was refreshed only at the end of a run, so a chain settled on the next run then too; this is no regression, and `run()` stays idempotent. Cost if wrong: a moment anchored to a chapter is placed one resolver run late.

R3 (Task 7, implementer concern). The tag's accessibility label stays the chapter's name, with the hint "Opens this chapter". The plan's "Chapter: {name}" is withdrawn. Why: `SpineUITests.testAChapterTheOwnerNamedShowsAsATag` asserts the label is the name; the row's own label already says the chapter; VoiceOver reads the trait "button". An existing assertion does not change for a label the spec does not ask for. Cost if wrong: one modifier.

R4 (Task 7, implementer concern). `LifeMap.Row` gets `isOpenEnded: Bool`, so the view does not repeat the kit's "no stated end" rule. Why: one rule in one place. Cost if wrong: one field and one test.

R5 (Task 7). Two files the plan did not list are accepted: `ChapterRemovedNotice.swift` and `LifeMapAxis.swift`. Why: one responsibility per file (CLAUDE.md). The task reviewer judges their content.

R6 (Task 9). Task 9's docs are written now. The one full UI run and the screenshots are made by the controller after the final review's fix wave, on the final code (as ruling R19 of the spine plan). The screenshots are "after" only, except the Timeline: the sheets and the life map did not exist before, so a "before" of them shows nothing. Cost if wrong: a second screenshot pass.

R7 (final review, I4). The words "Untitled chapter" show nowhere. For a chapter with no name the remove question is "Remove this chapter?" and the notice is "Removed a chapter with no name." The controller's Task 7 direction (the mock-up's `Removed “Untitled chapter”.`) is withdrawn. Why: the Global Constraint says "Untitled chapter" must not show on the Timeline, and the notice sits on the Timeline; `Removed “No name yet”.` would quote a name the person never gave. Cost if wrong: two strings.

R8 (final review, I2 and M1). The prune of empty chapters with no name is added to `SessionRepository.deleteSession`. It is not added to `MemoryRepository.fold`: a merge can be undone, and a prune there would lose the tag when the merge is undone. The launch prune takes that case. A snapshot restore sets `chapter_id` to null when its chapter is gone. Cost if wrong: an empty "No name yet" row can stay on the life map after a merge until the next launch.

R9 (final review, M6, M8, M9, M10, M11). Not fixed in this PR; recorded in the plan's "After S6c": no unit guard for "a second removal replaces the first" (the app target has no unit tests); the 6-second Undo is short under VoiceOver; no sheet can state a chapter with no end, so life map rule 4 is built but cannot be reached; `LifeMapAxis.visibleYears` has no test; the memory screen reads a chapter's raw title.

R10 (merge of main, photo story #29). Photo story's "Use this date" also wrote the range of the memory's chapter, and two of its tests asserted that. The spec rule of S6c wins: a chapter's range holds stated years only. `MemoryRepository.updateRange(_:_:ifCurrently:)` loses `refreshingChapter` and changes only the memory; the two tests now assert that the chapter's range does not change; one sentence in photo story's decision entry is corrected. `Chapter.statedYears` names its two origins, so the new `photo` origin does not count as stated, as in the prune's SQL. Why: the owner decided the chapter model on 2026-11-16; photo story was built against the older rule. Cost if wrong: one line in `updateRange` and two assertions.
