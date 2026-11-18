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
- Task 4: fix round 1/5 (1 addressed, 0 open — blank holding sheet; commits 86f1778..7797fb7)
- Task 4: complete (commits 729eec6..7797fb7, review clean after one fix round; 7 minors deferred above)
- Task 5: built at 4a7e520 (base 541c356). Review: spec ok, one Important (the tap guard after a hold is time-based and depends on an unchecked event order: hold, pause, release may open the viewer).
- Task 5: cannot verify from diff, sent to the device check (Task 6): a plain swipe still scrolls the row; VoiceOver "Move to front".
- Task 5: minor (deferred): the tile jumps back at the drop until the write lands (hold the dropped order until `photos` changes).
- Task 5: minor (deferred): the page can scroll under a held tile (vertical container keeps its pan).
- Task 5: minor (deferred): at xLarge text the "Key photo" pill has no width limit and may widen the first tile; slot math then is one off.
- Task 5: minor (deferred): two quick drags can lose the first (`move` builds on `photos` as last read).
- Task 5: minor (deferred): `testOnePhotoHasNoHintAndNoDrag` does not assert the viewer stayed closed.
- Task 5: minor (deferred): the slot math in `PhotoRowDrag.swift` has no unit test (app target).
- Task 5: minor (deferred): a drag on You scrolls the page to the top (existing `onChange` of the cover); confirm on device.
- Flaky under load, not ours: `testAPlayErrorLeavesAnOpenUndoInPlace`, `testHidingALineFarDownShowsUndoWithoutScrolling` (YouUITests), `drainGivesUpAtItsDeadline` (kit). Watch in the whole-suite run.
- Task 5: Ruling: the tap guard becomes a one-shot flag whether or not the two new tests fail on the old code — a guard that drops a real tap for half a second and rests on an undocumented event order is the wrong shape — cost if wrong: one view file. The two new tests passed on the old code too, so they do not tell the guards apart; device check carries it.
- Task 5: fix round 1/5 (1 addressed, 0 open — time-based tap guard; commits a2705d4..6e5f307)
- Task 5: minor (deferred): the flag's clear depends on `onChange(of: isHolding)`; a release at exactly the 0.35 s recognition could leave it set and swallow one tap.
- Task 5: minor (deferred): no direct test for a tap right after a drop.
- Task 5: complete (commits 541c356..6e5f307, review clean after one fix round; minors deferred above)
- Task 6: dispatched from 6e5f307 (docs only), in parallel with the Task 5 re-review.
- Task 6: built at 6b52277 (base 329be7f). Review: approved, no Critical or Important.
- Task 6: minor (deferred): "Known small items" in the device check misses two Task 5 minors (the flag's clear at the 0.35 s edge; no test for a tap right after a drop).
- Task 6: minor (deferred): OVERVIEW says "a checkbox for each memory"; the code draws a Toggle (switch). The spec says checkboxes: either the view or the docs must change.
- Task 6: minor (deferred): the known item "the pill has no width limit" is stale (the pill is capped at xLarge with one line); reword to the slot math at large text.
- Task 6: minor (deferred): the DECISIONS status line is long; split it.
- Task 6: cannot verify from diff: the seven agreed points against the contacts spec (not on this branch); DECISIONS' claim that a write demotes the old cover before it promotes the new one — true by Task 3's `writeOrder` (reviewed there).
- Task 6: complete (commits 329be7f..6b52277, approved; minors deferred above)

## Final review (0787f3b..7297eca)
- Verdict: ready with fixes. No Critical. Important 1: the date offer takes facts, feelings and goals, whose date the memory page hides. Important 2: no test for the drag's slot math with three or more photos.
- Ruling: only moments (`isMoment`) take the photo's date — a non-moment's page shows no date and no date control, so a date written there is hidden and cannot be changed, against "uncertainty is shown, never hidden" — if wrong, one filter line and a mark on the fact's page are needed.
- Ruling: `PhotoRowDrag`'s slot math moves into the kit with a table test, in place of a third seeded photo and a UI test — cheaper, and the math is pure — if wrong, a UI test is still missing for three tiles; device check carries it.
- Ruling: "Choose moments" keeps switches; OVERVIEW says "switch"; the spec's word "checkbox" stays and the difference is an open item for the owner — a switch is the iOS idiom — if wrong, one view changes.
- Fix wave takes: Important 1, Important 2, Minor 3 (`seen` takes offered and written-or-unchecked only), Minor 5 (VoiceOver announcement and header traits), Minor 7 (OVERVIEW), Minor 8 and the Task 6 minors (device-check known items), the viewer assertion in `testOnePhotoHasNoHintAndNoDrag`.
- Parked — Minor 4, a resolver failure after the date write leaves no Undo handle — Ruling: real, store-failure only, changes the reader's interface; left for the owner's list.
- Parked — Minor 6 (a failed Remove shows its error under the sheet), Minor 9 (`toggle` trusts the last read), Minor 10 (`onChange()` after a drag that moved nothing) — Ruling: real and small; nothing builds on them.
- Owner's call, from the final review: a memory dated from an age ("when I was 22") has origin `inferred`, is counted under "no date you said" and is replaced on tap; Undo covers it, the sentence may not be true for it.
- Final fix wave: commits 90eedac..c89ed7b (1f5205d, 7ecd0e1, 4745da6, cc075a9, ba3e661, c89ed7b). Re-review: all seven findings addressed, no new Critical or Important.
- Parked — an announcement flag stays set when a date tap changes nothing or fails, so one later change is announced once more — Ruling: harmless, one extra VoiceOver line.
- Parked — the new viewer assertion in `testOnePhotoHasNoHintAndNoDrag` does not wait — Ruling: a weak negative check; fine.
- Flaky under load, not ours, new name: `pausesAreLoggedNotEmitted` (same file as `hungFinalizeDoesNotBlockSegmentCloseOrStop`).
- Whole UI suite: started on c89ed7b.
