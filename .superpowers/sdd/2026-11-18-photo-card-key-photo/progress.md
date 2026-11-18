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
- Task 2: complete (commits 7160b19..5152416, review clean). Minor, parked: the date filter runs twice until Task 4 removes `dateOffers`; `StoryDateOffer` and `PhotoDatePart.Offer` have no public init (Task 4 note if the app needs one). Kit suite under load tripped two timing tests besides the known flake; both passed on reruns; not ours.
- Task 3: complete (commits b452937..c4bbb9a, review clean). Test setup change accepted: `aPhotoPutBackOnAPageComesBackLast` links the photo to a second page so its row survives the unlink; assertions as briefed. Reviewer's ⚠️ checked by the controller: `removeLink` gives a removed cover to the lowest `sort_order`, which after `writeOrder` is the next photo shown; no gap. Minor, parked: repeated row comparisons in tests.
- Task 4: built at 05108bb (base 729eec6). Review: spec ok, one Important (holding sheet goes blank after its last Remove).
- Task 4: Ruling: the date control stays a full-width capsule with "Choose moments" / "Undo" on a row under it; PH1/PH2 draw a hugging pill with the link beside it — the brief pins the frame of `dateUsed` to `useDate` and Undo to Choose moments' place, and the spec's rule is that the card keeps one layout after a choice; a hugging pill changes width with its text — if wrong, one view file changes (`PhotoCardDate.swift`) and the kit gives both state texts. Open for the owner in the final report.
- Task 4: accepted outside the file list: `SessionDetailViewModel` reloads its rows through `PhotoCardViewModel.onAction` (reviewer confirmed the stale date on the memory page without it); `openMemory` helper swipes the row above `home.start` (no assertion changed).
- Task 4: minor (deferred): the card is read twice after each action on the session page (`onAction` plus inner refresh).
- Task 4: minor (deferred): `useDate(for:)` puts the card's current offer in `seen`, not the set the sheet captured when it opened.
- Task 4: minor (deferred): `useDate(for:)` returns silently when the offer went away while the sheet was open.
- Task 4: minor (deferred): `keepsTallest` resets on a text-size change only, not on a width change.
- Task 4: minor (deferred): the seed's function-level guard now needs "Alder Street"; with the guess flag and no birth date the picnic is skipped silently.
- Task 4: minor (deferred): the sheet's "Remove" buttons are not checked at the largest text.
- Task 4: minor (deferred): `openMemory`'s swipe loop has no upper bound.
- Flaky, not ours: `drainGivesUpAtItsDeadline` failed in two kit runs while the simulator was busy.
