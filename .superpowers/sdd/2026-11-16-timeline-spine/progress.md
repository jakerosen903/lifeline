# SDD ledger — plan: docs/plans/2026-11-16-timeline-spine.md
Spec: docs/specs/2026-11-16-timeline.md. Worktree ../lifeline-timeline, branch sections-timeline, from origin/main 77d0440 with origin/claude/bold-ramanujan-c0uver merged (fast-forward to b5369da; docs only).
Execution: subagent-driven. Rulings are in rulings.md, beside this file.
Simulator: "Lifeline Timeline", iPhone 17 Pro, iOS 26.3, id 4AE32EAA-9F5F-424C-8AD3-BA150C9B2ADC. The first device landed on iOS 27.2 (simctl's default); it was deleted and made again on 26.3, which CLAUDE.md requires.
Baseline: swift test, 862 tests. Run 1: 1 issue, test name not captured (output was cut to its tail). Run 2, full log: 862 passed, 0 issues. Treated as a flake under the parallel run; earlier ledgers name SessionRecorderTests and BackupTests as the known ones.
Owner stop: before Task 4, report on the plan's 12 decisions and wait for the answer.

Pre-flight (one row for each task, one for each pair that shares a file or an interface):
| Tasks | Produces against consumes | Found |
| --- | --- | --- |
| 1 | LifePeriod tests against its rules | Agree. Birth 1990: 2002 is age 12, 2003 is age 13, 2089 is age 99. |
| 2 | SpineLayout tests against its rules and TimeRange | Agree. Three points the text leaves open: rulings R1, R2, R3. |
| 3 | TimelineSummary.text against its four expectations | Agree. The app does not compile from Task 3 to Task 5; the plan says so. |
| 4 | View model against Task 6's seed | Agree. Task 4 names the check `everyPlacedLooseMomentIsOnTheSpine` and `everyPlacedMomentIsOnTheSpine`; Task 6 names `testEveryPlacedMomentIsOnTheSpine`. One test; Task 6's name is used. |
| 5 | Views against Global Constraints | `timeline.tag` must be its own element (Task 6 counts it) and the row's label must hold the chapter (decision 12). The tag must sit outside the element that ignores its children. Carried into Task 5's dispatch. |
| 6 | Seed against SpineLayout | Agree. Gaps are 1, 1, 2, 3, 2 years: one label, "3 years". Periods: Childhood (1999 to 2001), Teens (2003 to 2008). `testAtTheLargestTextTheDateSitsAboveTheTitle` asserts the label, which holds "2008–10" at every size; the plan mandates it. Left for the reviewer. |
| 7 | Docs | README "when it merges": ruled at Task 7. |
| 1 → 2 | LifePeriod.containing(year:birthYear:) | Agree. |
| 2 → 4 | SpineLayout.stops(for:birthYear:), Stop | Agree. The view model filters to `isDated` first. |
| 3 → 4 | TimelineSummary.text without `chapters` | Agree. |
| 4 → 5 | SpineRow, MemoryRow.chapterTitle; no `axis`, no `newChapter` | Agree. May need one commit; the plan allows it. |
| 5 → 6 | Identifiers timeline.period, timeline.gap, timeline.tag | Agree. |
| 4, 6 and Photos | Dependencies.swift, UITestSeed.swift | Edits stay small and at the end of each block (owner's rule). |
Task 1: complete (commits 83503e9..6bb546b, review clean; swift test 867). Minor, carried to the final review: the decade uses Double division where integer floor division would do; no test at age -1; a test pins "The -10s" for a negative year.
Note: ExtractionQueueTests.drainGivesUpAtItsDeadline failed once in Task 2's full run and passed on rerun; not touched by this plan. It is the likely baseline flake.
Task 2: complete (commits 6bb546b..3299af8, review clean; swift test 884). Rulings R1, R2, R3 applied. Minor, carried to the final review: the literal "around" is written twice in SpineLayout; no test for a "probably" range beside the margin qualifier.
Task 3: complete (commits 7700dbf..b932cfd, review clean; swift test 884). The app target does not compile from here until Tasks 4 and 5.
Tasks 1 to 3 done. Stopped for the owner: the report on the 12 decisions. R1 and R2 are also in docs/DECISIONS.md.
Owner answered the decisions stop: change 4 and 8, keep the rest (rulings R4, R5). Task 2b (kit amendment for R4 and R5) comes before Task 4.
Task 2b: complete (commits d019170..852aa7f, review clean; swift test 890). Rulings R4 and R5 in SpineLayout. Minor, carried to the final review: the showsYears expression is long; no test for a relation under a relation.
Tasks 4+5: one commit, cf724d7 (the app does not compile between them; R6), then fix round 1, b2f33b7 (R7 to R10 and tidying). Review of cf724d7: approved, minors only. Task 4 check: left to Task 6 UI test testEveryPlacedMomentIsOnTheSpine (no kit function fell out naturally). App builds; swift test 890; ShellUITests 13 of 13.
Tasks 4+5 edge cases: no dated moment, no spine section; one moment, a mark and a zero-height line; an open story, the line runs beside its members with no marks (also when it is last, R7); a long title wraps and the mark stays at the first line; a long chapter name truncates on one line; accessibility sizes, the margin closes and the date sits above the title.
Tasks 4+5 not yet seen on screen: a story stop, a capsule, a relation row, and the whole spine at the largest text size. Task 6 and Task 7 cover them.
Tasks 4+5: fix round 1/5 (9 addressed, 0 open; commits cf724d7..b2f33b7). Re-review approved. Minor (deferred): confirm on screen that a folded story adds no stray row.
Task 6: implemented, 4778e5b. RED on scratch/spine-before (77d0440 plus the seed): 5 of 7 new tests failed for the right reason (gap label, waypoints, "Untitled chapter", the tag in the label, "New chapter from here"); testEveryPlacedMomentIsOnTheSpine and testAtTheLargestTextTheDateSitsAboveTheTitle pass there too (R11, R12). GREEN: Spine 7/7, SameStory 5/5, Organize 6/6, Steady 6/6, Timeline 8/9.
Task 6 found a regression from Tasks 4+5: TimelineUITests.testMemoryScreenPlaysAndShowsEvidence fails; a tap on an open story's member row does not open the memory. Tasks 4+5 fix round 2 is open for it.
Task 6 review: needs fixes. Important: labelsOnTheWholeTimeline removes duplicates by label, so the three "once" tests cannot see a duplicate. Minor (deferred): SpineUITests repeats the row query that memoryRow holds.
Tasks 4+5: fix round 2/5 implemented, 234c3ee (root cause: opened members landed under the bars; R13, R14). Timeline 9/9, Spine 7/7, SameStory 5/5, Shell 13/13; swift test 890. Re-review pending.
Tasks 4+5: fix round 2/5 (1 addressed, 1 open — the finding is addressed by the scroll and the wrapping tag; open, Important: members laid out in one list cell put several context menus in one cell; commits 4778e5b..234c3ee). Minor to fix in round 3: Reduce Motion on the scroll; a stale comment. Minor (deferred, for the device check): a story that is the last stop may not scroll clear of the record bar; the scroll target on the shelf; the jump when the members were already visible.
Task 6: fix round 1/5 (1 addressed, 0 open; commits 234c3ee..965b656). Re-review approved. The "once" checks count each element by label and absolute position. Spine 7/7.
Task 6: complete (commits b9778ee..4778e5b and 234c3ee..965b656, review clean). Minor (deferred): the 20-point merge tolerance in SightingLog is not tied to a measured height; `if !firstScreen` after the loop is dead code; no mutation run shows the three tests failing on a real duplicate.
Tasks 4+5: fix round 3/5 implemented, d3fb3dd (R16; Reduce Motion; the comment). Organize 6/6, SameStory 5/5, Shell 13/13, Spine 7/7, Timeline 9/9; swift test 890. Re-review pending.
Task 7: docs committed, c4dc6c0 (overview, decision log, After S6a, device checklist with the screenshot table, README status). Screenshots and the one full UI run are the controller's.
Final review (b5369da..b396be6): ready to merge with fixes. No Critical. Important: (1) an inferred range over two calendar years loses "around" (R17); (2) a gap label next to a relation comes from the slack (R18); (3) spec "The spine" rule 5, the place and the tap on a person, is not built and was not recorded. One fix wave dispatched. Deferred minors triaged by the reviewer: none must be fixed; the fix wave takes the "should fix" ones.
