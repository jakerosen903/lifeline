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
