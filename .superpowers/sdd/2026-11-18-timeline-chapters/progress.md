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
Task 2: complete (commits 6a5f93b..186abb2, review clean; swift test 1036). The reviewer could not verify from the diff that Resolver.swift:216 reads the anchor range; Task 3 gives the resolver copies whose range is the anchor range, which answers it. Minor (deferred): the `setKind` doc comment still says a fact "leaves its chapter's range" (carried into Task 4, which edits that file); `aStatedRangeSurvivesAMemberThatMoves` would also pass against the removed resolver block.
Task 3: complete (commits 186abb2..ca09d51, review clean; swift test 1039). The second-pass question is ruling R2. Minor (deferred): the fact test has no upper bound; no test for an unplaced member or a chapter with no members in the runner.
Task 4: complete (commits ca09d51..0d3a959, review clean; swift test 1056). The prune after a delete is in the kit, inside `MemoryRepository.delete`'s write. Minor (deferred, for the final review to triage): (1) a chapter hint that is only punctuation can no longer be accepted; the card stays pending and shows "Could not file that" on each tap; (2) `add(_:toChapterNamed:)` is three writes (insert, tag, prune), and a kill between them leaves an empty named chapter; no comment says so; (3) undo of a removal can leave two chapters with one name when a hint made the same name inside the 6 seconds; (4) `rename` on a missing chapter returns `.renamed`; (5) the doc comment on `ChapterRepository.remove` says the foreign keys clear the tags, and the code clears them itself; (6) `add(_:to:)` returns silently when the memory or the chapter is missing.
Task 6: complete (commits 0d3a959..5ffd540, review clean; swift test 1071). Done before Task 5 so that two implementers do not edit app files at once. Minor (deferred): a range with a `likelyEnd` and no `latest` takes its end from `likelyEnd`, untested; a chapter that starts after now is a zero-width bar at the right edge, with no test and no comment (carried into Task 7: the view gives a bar a smallest width); `noChaptersIsEmpty` asserts nothing on `periods` (Task 7 hides them when `isEmpty`).
