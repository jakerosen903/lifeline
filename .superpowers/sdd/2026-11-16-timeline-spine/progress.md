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
