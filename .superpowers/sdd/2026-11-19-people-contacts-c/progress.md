# SDD ledger — plan: docs/plans/2026-11-19-people-contacts-c.md

Branch `people-contacts-c`, cut from the tip of `people-contacts-d` (5bf37b2). Spec: `docs/specs/2026-11-18-people-contacts.md`, "Merging two people".
The owner said "Yes, build both" (PC-d, then PC-c) on 2026-11-19, without a review of each plan decision.

## Pre-flight scan

| Tasks | Produces against consumes | Found |
| --- | --- | --- |
| 1 | The branch | The base already has `main`'s photo order and `v16`. The task is done by cutting the branch. `PhotoRepository.writeOrder` is still `private`. Ruling C1. |
| 2 and 3 | `PersonMergeReceipt` public fields (2); the row copies (3) | Task 2 may leave the copies empty. Agree. |
| 2 | Step 9 failure test drops `domain_tag` | The plan's transaction-failure test needs a step that throws; dropping a table is the plan's way. Agree. |
| 2 and PC-d | Links carry `person_handle` | `update or ignore` moves the row with its handle. A memory both persons link keeps the stayer's row and handle. Ruling C2. |
| 3 | Undo list against the owned tables | `photo_page_declined` is a real table on this base; the plan's "when it exists" guard stays, since the kit can open an older database copy in tests. Agree. |
| 4 and 5 | `PersonMoveUndo.offer`; `PersonMergeViewModel.ask` | Agree. |
| 4 and 6 | `PersonMergeSheet(picker:)`; the grid's slot | Agree. |
| 5 | Changes a PC-b UI test | The plan names the renamed test. Agree. |
| 6 | The drag test may not run on the simulator | The plan says what to do. |
| 7 | Seeds | `launchWithPeople` has Maya, Dad, Sam, Lena; `-uiTesting-seedContactLink` links Lena. Agree. |
| 8 | Docs | Agree. |

## Progress

- Task 1: complete (the branch `people-contacts-c` exists at cef70ed; no merge of `main` was needed).
- Task 2: complete (commits 1b31d68..c565e19, review clean). Rulings C3 to C5. Carried to Task 3 by ruling C4: three small rules of the merge (the stayer's stale decline rows, and the role text of a dropped link).
- Task 2: minor (deferred): the `tableExists` guard for `photo_page_declined` is never false in a test on this base; no full kit run has been clean of the two timing flakes (`CascadeVoiceSessionTests.hungFinalizeDoesNotBlockSegmentCloseOrStop`, `ExtractionQueueTests.drainGivesUpAtItsDeadline`).
- Task 4: complete (commit 04263f3, review clean, subject to `PeopleGuessUITests` and `PeopleContactsUITests`, which are built and not run). Ruling C6.
- Task 4: minor (deferred): no test of `PersonMoveUndo.offer` with a stale-throwing closure. Carried to Task 5: the confirm blanks for a frame while the sheet closes; a picker row with no leaving person does nothing.
- Task 3: fix round 1/5 (2 addressed, 0 open — the stayer's decline of its held contact goes from either side; Undo gives back the legacy `memory_person` rows; commits 730f52a..3418877)
- Task 3: complete (commits 568dc0f..3418877, review clean after one fix round). Ruling C7.
- Task 3: minor (deferred): a delete the staleness checks do not cover makes Undo fail with a database error, not `.stale`; the transaction rolls back and the app shows the failed-Undo line.
- Task 5: complete (commit 13bb264, review clean). `PeopleContactsUITests` 15 of 15. `PeopleGuessUITests` 13 of 16: two older tests need a scroll because the merge row makes the page longer (`testAMoveThatRemovesAGuessedPersonKeepsThePageForUndo`, `testWithoutUndoTheEmptiedPageClosesWhenTheNoticeEnds`), carried to Task 7; `testTwoPeopleWithOneNameGetTwoChips` (PC-d's test) fails after Keep and is checked on the PC-d branch alone. Ruling C8.
- Task 5: minor (deferred), carried to Task 7: no UI test for the forced "Merge" itself nor for two different contacts in the forced case.
- Task 6: complete (commit 9c32c94, review clean). Built, not seen on screen; `PeopleUITests` and the drag test still need a run (Task 7). Ruling C9.
- Task 6: minor (deferred, for the final review and the device check): the drop ring also shows on the dragged tile itself and for text from another app; a dragged tile gives plain text "lifeline-person:{id}" to another app; the grid's animation ignores Reduce Motion for row changes; `tileFrames` is written on every layout; a second drop inside the 0.25 s motion.
- Task 7: implemented (commits f233d1a, 5d02819), in review. UI on the simulator: `PeopleMergeUITests` 9 of 9 (the drag test runs and is kept), `PeopleContactsUITests` 15 of 15, `PeopleUITests` 10 of 10, `EntityPageUITests` 8 of 8 after a test-only scroll repair, `PeopleGuessUITests` 15 of 16 (the one failure was PC-d's two-Robyns test, since corrected on PC-d as a test defect, commit a7e6a61, merged in at 4733ea7). No app defect found.
- Open for the owner (older behaviour, R34, not from this plan): a held page (its person is gone and the notice is up) cannot scroll, because the whole list is disabled.
- Task 7: complete (commits 4088763..5d02819, review clean). Ruling C10.
- Task 7: minor (deferred): the picker test compares a set, so a duplicate row would pass; a negative `reveal` in the Undo test can pass for a wrong reason; the Cancel and refusal tests do not look at the other person's page; three test helpers are copied between files; the Priya helper's short slow drags are tuned to this simulator.
- Task 8 (docs): complete (commit 8f89344).
- Final whole-branch review (a7e6a61..8f89344): ready with fixes. No Critical; no data-loss path and no new path to the model found. Important I1 (handles in a merge untested, C2's cost understated), I2 (a refused Undo of a merge shows a line that does not apply). Minor M1 to M8. One fix wave dispatched (`fix-wave-brief.md`): I1 (tests and docs), I2, M1, M2, M4, M6, M7, M8. Parked by ruling: the behaviour behind I1 (C11), M3, M5.
- Final review fix wave: complete (commits ca85780..291bcfb, nine commits). Scoped re-review: every finding addressed (I1 tests and docs, I2, M1, M2, M4, M6, M7, M8, C16), no new Critical or Important. UI after the wave: `PeopleMergeUITests` 10 of 10, `PeopleContactsUITests` 15 of 15, `PeopleGuessUITests` 16 of 16. Kit: 1744 tests; failures were the timing flake `drainGivesUpAtItsDeadline` and the guard `noKitSourceReadsTheOldLinkTables`, since fixed by C16 (59 focused tests pass). No full kit run after C16 yet.
- Parked — the grid's "a drop does nothing while Undo shows" UI test depends on a second drag landing inside 6 seconds; on a slow machine it fails on "no confirm opens", which reads like a regression of C14 — Ruling C17: accepted; whoever sees it fail must rerun it alone first.
- Parked — Undo re-inserts a left curiosity item whole; if its source or target memory is deleted inside the 6 seconds the insert fails and Undo shows the failed line — Ruling C17: same class as the known limit for deletes the staleness checks do not cover.
- Parked — the behaviour behind I1 (C11), M3, M5, and the ledger's deferred minors as triaged in `final-review.md`.
- Open: the device check is not run; the whole UI suite has not run on this branch.
