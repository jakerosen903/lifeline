# SDD ledger — plan: docs/plans/2026-11-18-timeline-chapters.md
Spec: docs/specs/2026-11-16-timeline.md. Worktree ../lifeline-chapters, branch sections-chapters, from origin/main 05573d8. Plan commit 64ba23f.
Execution: subagent-driven (owner, 2026-11-18). Rulings are in rulings.md, beside this file.
Simulator: "Lifeline Timeline", iPhone 17 Pro, iOS 26.3, id 4AE32EAA-9F5F-424C-8AD3-BA150C9B2ADC.
Baseline: swift test, 1022 tests, 0 issues.
Owner's standing rules: no push and no PR until the owner says; no AI attribution; commit after each task.

Pre-flight:
| Tasks | Produces against consumes | Found |
| --- | --- | --- |
| 1 | Tests against the three members | Agree. The display text of 1998 to 2001 is to be read from TimeRange, as the plan says. |
| 2 | Tests against the removals | Agree. Six existing tests assert the old rule; the plan names them and says to invert, not delete. |
| 3 | Tests against input(...) | Agree. The copies must be made on each call, as the plan says. |
| 4 | ChapterActions against CandidateActions | The plan has ChapterActions call CandidateActions.assign and acceptHint call ChapterActions: a circle. Ruling R1. |
| 5 | Menu and sheet against Task 4 | Agree. |
| 6 | LifeMap tests against its arithmetic | Agree. Birth 1990, now 2026: 37 units; 2008 to 2012 is 18/37 to 23/37. |
| 7 | Views against identifiers Task 8 reads | Agree. SpineUITests may query the tag by element type; the plan allows a change of type only. |
| 8 | UI tests against the spine seed | Agree. The seed for "no chapters" is to be checked by the implementer. |
| 9 | Docs | Agree. |
| 1 → 2, 3, 6 | statedYears, anchorRange, name | Agree. |
| 2 → 4 | deleteEmptyUntitled keeps stated years | Agree. |
| 4 → 5, 7 | ChapterActions, ChapterReceipt | Agree. |
| 6 → 7 | LifeMap, summary(of:) | Agree. |
| 5, 7 | TimelineScreen, TimelineViewModel, MemoryRowView | Both edit them, in sequence. No conflict. |
Task 1: complete (commits 5944fcc..6a5f93b, review clean; swift test 1029). Minor (deferred): the derived and inferred cases rely on `.year` being placed; `name` has no test with a newline.
