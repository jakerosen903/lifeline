# SDD ledger — plan: docs/plans/2026-11-16-photo-story.md

Spec: docs/specs/2026-11-16-photo-story.md (approved by the owner 2026-11-16). Worktree /Users/jakerosen/dev/lifeline/lifeline-photo-story, branch photo-story, base a1638c3 (origin/main). Plan commit e1df2b9.
Owner's rules (as for S4): commit after each task; per task run only the named UI classes; whole UI suite once at the end; never push; no PR until told; no AI attribution; rulings also go to docs/DECISIONS.md.
Owner approved the v14 schema and "build it" on 2026-11-16. v14 unused on origin/main and in PR #24 (checked).

## Pre-flight scan

| Tasks | Produces / consumes | Found |
|---|---|---|
| 1 → 2 | `session.subject_photo_id`; `PhotoRepository.link(_:to:in:)` | agrees |
| 1 → 3 | `hasOtherHome`, `subjectPhoto(of:)` feed `PhotoStoryReader` | agrees |
| 1 → 4 | `SessionRecorder.start(subjectPhoto:)`, `SessionOrigin.photo` | agrees |
| 1 → 5 | `PhotoLibrary.store` | agrees |
| 3 → 4 | `TimeRange.fromPhoto` for the seed and the "from a photo" mark | agrees |
| 3 → 6 | `PhotoStoryCard`, `PhotoStoryReader` | agrees; Task 6 adds `PhotoStory.deleteSentence` to the Task 3 file |
| 4 → 5 | `startPhotoSession`, `lastWasPhoto`; Task 5 changes "Tell another" | agrees (Task 4 says so) |
| 4 → 6 | viewer-started live session for the landing test | agrees |
| 5 ↔ 6 | Task 5 `testTwoStoriesFromTheSameFavorite` mentions `photoCard` "after Task 6" | Ruling: in Task 5 it asserts `session.photo` only — the card does not exist yet — cost if wrong: none |
| 1 self | tests vs code | agrees |
| 2 self | `aRemovedPhotoStaysRemovedOnALaterRead` vs decision 4 (re-link on a later merge) | agrees: the test covers reads, decision 4 covers a later merge |
| 3 self | `offersDate` table "only earliest set, date after it → false" vs "treat a missing edge as unbounded" | agrees |
| 4 self | `testADateFromAPhotoSaysSo` needs a seed change in `UITestSeed` | listed in Files |
| 5 self | route test in kit, PhotoKit in app | agrees |
| 6 self | seed `-uiTesting-seedPhotoStory` needs a second session for the delete test | Ruling: the seed holds two photo sessions (the second has no kept memory and its photo has no other home) — the test needs it — cost if wrong: none |
| 7 self | docs only | agrees |

## Tasks
- Task 1: complete (commits 6e138c6..5b56644, review clean). Implementer a7b779d41dcdfa90d. Minor, parked for later tasks: (a) v14 data test compares counts, not row contents; (b) a Settings sweep between `store` and the session insert could remove the new photo — Task 5 note; (c) deleting a photo session leaves its homeless photo until the next sweep — Task 6 note.
- Hygiene commit 78ad9da: two nested `#require` calls in V7PeopleRulesTests un-nested so the kit tests compile on Swift 6.4.2 (same assertions).
- Known red on origin/main, not ours: `keepWritesTheCardsKind` (MemoryKindColumnTests.swift:78) fails at a1638c3; PRs #25 and an earlier one disagree once merged. Left alone; owner to be told. Kit baseline is therefore "1 known failure".
- Task 2: fix round 1/5 (2 addressed, 0 open — undo of a merge left the photo on the target; failed-keep test did not prove rollback; commits da01afa..f12ed69)
- Task 2: complete (commits 92edd5b..f12ed69, review clean). Implementer adb1ab814605bee16. Minor (deferred): `aRemovedPhotoStaysRemovedOnALaterRead` is near-vacuous until Task 3's reader; all Task 2 tests are in PhotoRepositoryTests.swift, not the files the brief named.
- Task 3: fix round 1/5 (2 addressed, 0 open — useDate was two writes; per-subject isLinked reads; commits f2fb6a5..fc0d301)
- Task 3: complete (commits 6d07c7e..fc0d301, review clean). Implementer aba42e670e6359b32. Minor (deferred): `usingTheDateIsOneWrite` calls the repository, not `useDate`; the reader's reads are not one snapshot (self-corrects on the next tick); a photo-dated memory reads as a guess on the entity page, the life strip and derived spans (`readsAsSaid` false, plan decision 6) — OWNER TO SEE; the resolver's own `updateRange` does not refresh chapters (existing behaviour, not ours).
- Task 4: fix round 1/5 (3 addressed, 0 open — session header untested; misplaced comment; three copies of the viewer start; commits 8a36a4f..53fda35)
- Task 4: complete (commits 9e98fb9..53fda35, review clean). Implementer aaa2893d63f3b5ceb. UI: PhotoStoryUITests 7/0, PhotosUITests 12/0, ShellUITests 13/0, PeopleUITests 10/0. Minor (deferred): a swap of the opening leaves the photo under a scene question (spec keeps alternates) — OWNER TO SEE; the "asks nothing" test is a 5 s time check with a one-segment script; no test for a start when the photo row is gone.
- Task 5: fix round 1/5 (3 addressed, 0 open — picker accessories hidden on every edge; a cancel still stored the photo; nil thumbnail never asked again; commits 749ba98..146a87c)
- Task 5: complete (commits c5e45bb..146a87c, review clean). Implementer a0f45b21a4386ca0b. UI: PhotoStoryStartUITests 14/0, PhotoStoryUITests 7/0, PhotosUITests 12/0, ShellUITests 13/0. Guards pass.
- Task 5: minor (deferred) — FOR THE FINAL REVIEW, fix before merge: the thumbnail continuation in `LibraryPhotoPickSource` has no resume-once guard (two final callbacks would trap; a degraded-only delivery would hang the tile's task).
- Task 5: minor (deferred): `cancel()` runs at `onDismiss`, after the dismissal animation, so a store that finishes in that gap leaves a photo until the next sweep; no test fails if the `cancel()` call is deleted; `testCancellingWhileThePhotoIsAddedStoresNothing` and `testAddAPhotoStillAsksForNoAccess` were not seen failing (they guard existing behaviour); the deleted-asset error says the file is unreadable; `file(for:)` partial file on a throw not checked.
- Not ours, for the owner: on first open the Skip button is out of reach at the largest text size (found while writing `testTheGridHoldsAtTheLargestText`, which launches with seeded people to step around it).
- Device-only (Task 7 checklist): the real prompt in each answer; limited access; an iCloud-only favorite (thumbnail and file); edited, Live and RAW+JPEG photos; the inline picker keeps its albums and search.
- Task 6: complete (commits 2b91405..edcc903, review clean). Implementer a86591f683757c99b. UI: PhotoCardUITests 11/0, PhotoStoryUITests 7/0, LandingUITests 14/0, PhotosUITests 12/0. ⚠️ resolved: `hasOtherHome` counts a memory with a span outside the session (Task 1 test `hasOtherHomeIgnoresMemoriesOnlyFromThisSession`).
- Task 6: minor (deferred): `PhotoCardViewModel.refresh` never clears `error` on success and can overwrite an action's message; no test that `deleteToday` calls the sweep; no in-flight guard on the two async removals (idempotent); unreachable "that day" fallback.
- Task 7: complete (commits 0285842..ee3bf11, review clean for the docs). Implementer a2b9c8e4ceca3ea5f.
- Task 7: FOR THE FINAL REVIEW, fix before merge: `MemoryScreen.swift:135` shows a photo-dated memory's evidence as `you said: "the photo's date, 14 June 2012"` — the person did not say it (screenshot 06 shows it).
- Task 7: minor (deferred): retake screenshot 05 scrolled so the last control shows; `testTheCardHoldsAtTheLargestText` does not assert the last control ends above the record bar; OVERVIEW Phase 2 line still says "Favorite photos as prompts"; checklist items 2, 8, 12, 14 say "say if it looks wrong" with no "must be true"; a few two-idea sentences in DECISIONS.
- Merged origin/main (7d8073b: PRs #24 and #28) at b0e76c5; no conflict; main fixed `keepWritesTheCardsKind` and the nested `#require` itself. Kit on the merge: 1053 tests; `drainGivesUpAtItsDeadline` fails 2 of 6 parallel runs (it was 10 of 10 green after S4's serialized BackupTests) — FOR THE FINAL REVIEW, fix before merge: the new file-heavy photo tests starve the pool again. App builds.
- Final review (a76cab6d7ae059cba, report final-review.md): no Critical; 7 Important (I1 card omits merged-into memories; I2 group-merge undo can drop the photo from both; I3 thumbnail continuation; I4 "you said" on a photo date; I5 dead "Tell its story" inside the landing's review; I6 one-tap delete on "Remove the photo from this story"; I7 `drainGivesUpAtItsDeadline` is flaky on origin/main too, 3 of 8); 4 must-fix Minors (M1–M4); M9 no backup round-trip test for a session-held photo.
- Fix wave: I1–I6, M1–M4, M9 dispatched. I7 not in the wave: the test is main's, flaky there too, and steadying it changes its assertion — owner's word needed.
- Final fix wave: complete (commits 36d2876..b9ae1f5: 1f01106 kit, 12ce3ea app, b9ae1f5 docs), fixer a264d3af0d183fd35. Re-review adf0c47f4a0569a80: all findings addressed, no new Critical/Important. Kit 1060 pass; UI per class: PhotoCardUITests 13/0, PhotoStoryUITests 7/0, PhotoStoryStartUITests 14/0, PhotosUITests 12/0, LandingUITests 14/0. Guards pass.
- Final fix wave: minor (left): the two "Use this date" tests find the button by its accessibility label, so the visible text is checked only by reading the code; `testKeepItLeavesThePhotoOnTheStory` checks at once, not after a wait; the "Keep it" label is not drawn on the simulator (the dialog is a popover; a tap outside cancels); a separated telling leaves the photo on the older memory, which then no longer shows on the card.
- Whole UI suite: started at b9ae1f5 (background task bdm6h4dah).
