# Rulings — plan: docs/plans/2026-11-16-photo-story.md

Format: `Ruling: <what was decided> — <why> — <what it costs if wrong>`. Non-obvious rulings also go into docs/DECISIONS.md.

- Pre-flight: Ruling: Task 5's `testTwoStoriesFromTheSameFavorite` asserts `session.photo` only — the card arrives in Task 6 — cost if wrong: none.
- Pre-flight: Ruling: the `-uiTesting-seedPhotoStory` seed holds two photo sessions; the second has no kept memory and its photo has no other home — Task 6's delete-dialog test needs one — cost if wrong: none.
- Task 1: Ruling: the controller un-nested two `#require` calls in `V7PeopleRulesTests.swift` in its own commit — the kit test target does not compile on this Mac's Swift 6.4.2 without it, so no task could run tests; the assertions are the same — cost if wrong: none; revert the commit.
- Task 1: Ruling: `v13OnAPopulatedV12Database` now migrates `upTo: "v13"` — its `select *` comparison on `session` would otherwise see the v14 column; the reviewer judged the assertions of equal strength — cost if wrong: none.
- Task 1: Ruling: `keepWritesTheCardsKind` fails on `origin/main` (a1638c3) and is left as it is — it is outside this plan — cost if wrong: CI on this branch's PR shows the same failure until main is fixed.
- Task 2: Ruling: Undo of a merge takes back the photo link that the merge added, and never a link the target held before — the plan was silent; without it an undone merge leaves a photo on a memory the telling no longer belongs to — cost if wrong: remove `MergeReceipt.addedPhoto`. Goes into DECISIONS.
