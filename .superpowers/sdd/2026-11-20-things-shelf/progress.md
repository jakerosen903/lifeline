# SDD ledger — plan: docs/plans/2026-11-20-things-shelf.md

Spec: docs/specs/2026-11-20-things-shelf.md (written 2026-11-20 from the five bullets of docs/specs/2026-11-15-five-sections.md, 'Things'). Worktree /Users/jakerosen/dev/lifeline/lifeline-things, branch sections-things, base origin/main aab2aa0. Simulator "Lifeline Things" 1F1457A7-1ED7-4149-A2BB-C0C2A9E76435 (iOS 26.3).

Owner, 2026-11-20: "And continue" after search was pushed. The sections plan says S7 to S9 wait for two weeks of the owner's use after S2; the build goes ahead on that instruction and the owner was told. Nothing is pushed without the owner's word.

## Pre-flight
The spec and the plan were written together against aab2aa0 on 2026-11-20, so there is no drift to scan. The spec's 15 builder's defaults are decided and listed for the owner.

## Tasks
Task 1: built (a94d657..bd23cdf); review: kit correct, Timeline rule unchanged; one Important: SpineUITests not run (the controller's dispatch said to skip UI tests; the controller runs SpineUITests after Task 2 commits). Minors for the final wave: `headingText` must start with `name` (make the rest its own property or pin it with a test); tests for a half-open stated span and for an id tie inside a period; the repeated force unwraps of placingDate. `interruptionClosesOpenSegment` joins the known timing tests. Check at Task 3: "Add dates" writes a thing's range with a settled origin.
Task 2: complete (commits bd23cdf..58b7675, review clean). Carried into Task 3's dispatch: the read must leave out hidden and untold details, first tellings must include facts, heavy ids come from heavySessionIDs(); and ruling R2 (a detail with no first telling is not chosen). Minors for the final wave: tests for an id tie, a quote of exactly 20 words, and every detail heavy.
Task 1: complete (commits a94d657..bd23cdf). The controller ran SpineUITests at 58b7675: Executed 7 tests, with 0 failures. The review's one Important is closed.
Task 3: complete (commits 96d2583..29b6d0f; review found one Important, the heavy-session wiring untested; fix round 1 29b6d0f; re-review clean). "Add dates" writes origin .stated (EntityRepository.setStatedSpan), so a stated span never reads as a guess. Minors for the final wave: an untold mention moment in the momentRanges test. Standing rule for Tasks 4 and 5: the shelf never uses summary.span (it can come from hidden memories); it places by entity.range and momentRanges only.
Task 4: built (29b6d0f..364b707); review: screen, tile, view model and seed match the spec; 2 Important (the failing test, ruled R3; a vacuous photo assertion); fix round 1 sent to the implementer with the Minors (the PersonLink accessibility form, the piano's stated span asserted, x in the de-duplication key).
Task 4 fix round 1: 59cde48. ThingsUITests: Executed 15 tests, with 0 failures; Entities 2, Kinds 1, Shell 13 pass. Scoped re-review dispatched.
