# SDD ledger — plan: docs/plans/2026-11-18-photo-card-key-photo.md

Spec: docs/specs/2026-11-18-photo-card-key-photo.md (approved by the owner 2026-11-18). Worktree /Users/jakerosen/dev/lifeline/lifeline-photo-card, branch photo-card, cut from photo-story (PR #29, open). Plan commit 2a8ddcc. The owner said "Yes, build it" on 2026-11-18.
Owner's rules (as for S4 and the photo story): commit after each task; per task run only the named UI classes; whole UI suite once at the end; never push; no PR until told; no AI attribution; rulings also go to docs/DECISIONS.md.

## Pre-flight scan

| Tasks | Produces / consumes | Found |
|---|---|---|
| 1 -> 2 | `PhotoDateChange` feeds `PhotoDatePart.state` | agrees |
| 1 -> 4 | `useDate(_:for:)`, `undoDate(_:)` used by the view model; Task 1 changes one call in `PhotoCardViewModel` so the app builds | agrees |
| 2 -> 4 | `pageGroups`, `dateOffer`, `momentsLine`, `PhotoDatePart`; old fields live until Task 4 removes them | agrees (decision 1) |
| 3 -> 5 | `reorder`, `setCover` as move to front, `PhotoOrder.moving` | agrees |
| 2 <-> 4 | `PhotoStoryTests.swift` changed by both; Task 4 lists its own changes | agrees |
| 1 self | tests vs code; `undoOfAGuessWithNoAnchorLeavesItUnplaced` pins decision 2 | agrees |
| 2 self | `offersDate` rows that flip to true vs the PR #29 review fix (said dates never offered) | agrees: the said-date test stays and gains `.photo` |
| 2 self | a kit task runs `PhotoCardUITests` once | intended: the old view must still pass |
| 3 self | `setCover` of a photo the page does not hold writes nothing vs "renumber on every change" | agrees: stated in the task |
| 4 self | `testAKeptMomentHoldsThePhoto` changes to keep both cards (decision 9) | open for the owner; listed in the hand-over of the plan |
| 5 self | drag gesture vs tap vs sideways scroll | three tests pin it |
| 6 self | docs only | agrees |

Spec addition after the plan was drafted: Undo cannot bring back a guess with no anchor (commit 2a8ddcc). The plan already pins it.

## Tasks
- Task 1: complete (commits cd7fa00..1c27358, review clean). Minor, parked: (a) the same memory passed twice to `useDate` gives two equal changes (harmless; note for Task 4's caller); (b) if the resolver throws after the range write, the caller gets no Undo handle — Task 4 note; (c) no test pins the order of the returned changes.
