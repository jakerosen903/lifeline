# SDD ledger — plan: docs/plans/2026-11-18-timeline-card.md
Spec: docs/specs/2026-11-16-timeline.md. Worktree ../lifeline-strip, branch sections-strip, from origin/main 2632875 (S6c merged). Plan commits 62b1344, 216bdfc.
Execution: subagent-driven (owner, 2026-11-18). Rulings are in rulings.md, beside this file.
Simulator: "Lifeline Timeline", iPhone 17 Pro, iOS 26.3, id 4AE32EAA-9F5F-424C-8AD3-BA150C9B2ADC.
Baseline: swift test, 1158 tests. The run had 4 issues, all in timing tests (CascadeVoiceSessionTests.interruptionClosesOpenSegment, ExtractionQueueTests.drainGivesUpAtItsDeadline); the Mac's load average was above 100 from other sessions' simulator runs. The same suite passed clean on this code as main's merge into sections-chapters.
Owner's standing rules: no push and no PR until the owner says; no AI attribution; commit after each task.

Pre-flight:
| Tasks | Produces against consumes | Found |
| --- | --- | --- |
| 1 | Tests against yearSpan and MarkPlacement | Agree. 2008 with birth 1990 and now 2026: 18/37. |
| 2 | TimelineCard tests against its arithmetic | Agree. Frame 1999 to 2003: 9/37 to 14/37. The plan does not say how many names the spoken text holds for more than three chapters: two names and "and N more", from the spec's example. |
| 3 | LifeStripAxis against LifeStripView | Agree. The entity page must not change; EntityPageUITests is the guard. |
| 4 | The card against Tasks 1 to 3 and S6c's life map state | Agree. `onScrollVisibilityChange` in a List is not proven; the plan names the fallback. |
| 5 | UI tests against the spine seed | Agree. The seed may have no story on the spine; the plan says to add one at the end of `writeSpine`. That changes a seed other classes use (Spine, Chapters): ruling R1. |
| 6 | Docs | Agree. The full run and screenshots are the controller's, after the final review (as R6 of the chapters plan). |
| 1 → 2, 4 | yearSpan, marks: .start | Agree. |
| 2 → 4, 5 | TimelineCard, spokenText | Agree. |
| 3 → 4 | LifeStripAxis(strip:frame:) | Agree. |
