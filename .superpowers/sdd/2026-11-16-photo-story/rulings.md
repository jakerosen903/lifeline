# Rulings — plan: docs/plans/2026-11-16-photo-story.md

Format: `Ruling: <what was decided> — <why> — <what it costs if wrong>`. Non-obvious rulings also go into docs/DECISIONS.md.

- Pre-flight: Ruling: Task 5's `testTwoStoriesFromTheSameFavorite` asserts `session.photo` only — the card arrives in Task 6 — cost if wrong: none.
- Pre-flight: Ruling: the `-uiTesting-seedPhotoStory` seed holds two photo sessions; the second has no kept memory and its photo has no other home — Task 6's delete-dialog test needs one — cost if wrong: none.
- Task 1: Ruling: the controller un-nested two `#require` calls in `V7PeopleRulesTests.swift` in its own commit — the kit test target does not compile on this Mac's Swift 6.4.2 without it, so no task could run tests; the assertions are the same — cost if wrong: none; revert the commit.
- Task 1: Ruling: `v13OnAPopulatedV12Database` now migrates `upTo: "v13"` — its `select *` comparison on `session` would otherwise see the v14 column; the reviewer judged the assertions of equal strength — cost if wrong: none.
- Task 1: Ruling: `keepWritesTheCardsKind` fails on `origin/main` (a1638c3) and is left as it is — it is outside this plan — cost if wrong: CI on this branch's PR shows the same failure until main is fixed.
- Task 2: Ruling: Undo of a merge takes back the photo link that the merge added, and never a link the target held before — the plan was silent; without it an undone merge leaves a photo on a memory the telling no longer belongs to — cost if wrong: remove `MergeReceipt.addedPhoto`. Goes into DECISIONS.
- Task 3: Ruling: "Use this date" changes the memory and its chapter's range in one write, then runs the resolver, as the existing "when" control does — the plan said only `updateRange`; a memory placed relative to this one must be re-placed at once — cost if wrong: one resolver run per tap.
- Task 3: Ruling: `PhotoCaption.longDate` is public and shared by the caption and the evidence text — one formatter, not two — cost if wrong: none.
- Task 3: Ruling: left as the plan says, for the owner to see: a date taken from a photo shows as a plain day on the memory page, and as a guess ("around 2019") where the app sums dates up (entity page span, life strip) — plan decision 6 makes it settled but not "as said" — cost if wrong: one line in `readsAsSaid`.
- Task 4: Ruling: the running session's header reads "You chose a story about a photo" — the session screen's own pattern ("You chose a quick story"); the record bar is under the session cover, so the plan's "on the bar" name has no place to show; "A story about a photo" is the Sessions list name — cost if wrong: one string. Pinned by a UI test.
- Task 4: Ruling: the Sessions list names a photo story from `startedFrom == .photo`, not from the photo row — it needs no read and stays true after the photo is removed from the story — cost if wrong: none.
- Task 4: Ruling: `testAPhotoSessionAsksNothingAfterItsOpening` waits for the first `session.segment`, not "2 possible memories" — the `-uiTesting-followUps` script has one segment; the no-turn assertions are unchanged and one was added — cost if wrong: none.
