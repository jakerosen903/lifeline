# SDD ledger — plan: docs/plans/2026-11-18-photo-on-people-pages.md

Spec: docs/specs/2026-11-18-photo-on-people-pages.md (approved 2026-11-18, parts 1-4). Base: 4389cbc.
Pre-flight: Task 6 needs a column that Task 1 owns: Task 1 text now carries it (agrees). Tasks 2 and 4 both change PhotoRepository (sequential, agrees). Tasks 3, 5 and 6 all change the card model and view (sequential). Task 7 is independent.

## Tasks
- Task 1: complete (commits 07d510d..e0b05cf, review clean). Kit 1358. Reviewer read every caller of the public `link` and `unlink`: all are owner taps or the seed.
- Task 1: minor, carried into Task 2's dispatch: the static `link(… origin: .story …)` does not refuse a declined pair itself; the rule is a comment.
- Task 1: minor (deferred): `v16FromV13` does not assert `photo_pages_done = 0` or that `photo_page_declined` exists.
- Task 1: minor (deferred): a comment that unlinking from the owner's own page records a harmless decline.
- Task 2: built at 6f8a78a (base b07c5d7), DONE_WITH_CONCERNS. Kit 1373 (one known flake).
- Task 2: Ruling: every name link counts, `detail` as well as `mention` — the spec says "each person the moment names", and a kept fact about a person in a photo story is about that person — if wrong, one filter in one query.
- Task 2: Ruling: Undo of a Keep takes back the story's page links that Keep left without a reason: after the memory is gone, a `story` link of the session's photo is removed when no memory that holds the photo names that person; an owner's link stays; no decline is recorded — the spec's rule is that the app shows and can take back its own assumption; a photo left on a page by an undone Keep is an assumption with no source — if wrong, the photo stays on a page after an Undo. Sent back to the implementer before review (correctness).
- Task 2: accepted: `aFailedKeepWritesNothing` forces the failure with a trigger after the links, because a duplicate span fails before any link exists.
- Task 2: Ruling withdrawn: there is no undo of a Keep in the kit (the implementer checked `CandidateActions.restore`, `CardHandler.undo`, `MergeActions.unmerge`, `MemoryRepository.delete`). A deleted memory leaves the photo on the people's pages, as the spec's edge case for a removed moment says; the owner takes it off with the chip. Nothing built for it. Comment commit 56d7c00.
- Task 2: complete (commits b07c5d7..56d7c00, review clean). Kit 1373. No existing test changed.
- Task 2: minor (deferred): no test where `letGo` makes the photo homeless after it removed story links (delete the memory, then let go).
- Task 2: minor (deferred): the returned order of `linkToPeoplePages` is promised in the doc and not asserted.
- Task 2: minor (deferred): `aFailedKeepWritesNothing` has no control assertion that the same card without the trigger writes the page link.
- Task 2: minor (deferred): `undoingAKeepLeavesNoLinkAndKeepsThePhoto` (PhotoRepositoryTests) is misnamed; it is a plain delete.
- Open for the owner: a kept fact about a person also places the photo; after a kept memory is deleted the chip still reads "added by this story" though no kept memory names the person.
- Task 3: built at 5aca2f1 (base 62ca0d7). Review: approved; one stated deviation.
- Task 3: Ruling: `PhotoStoryReader.removeFromPage` is not added — the app removes a photo from a page through `PhotoLibrary.remove`, which calls `unlink` (records the decline) and deletes the file; a reader method would be a second path that leaves an orphan file — the plan's Task 5 line "the chip's remove goes through `removeFromPage`" is void: the chip keeps `PhotoLibrary.remove`. Carried into Task 5's dispatch. Cost if wrong: none; one path remains.
- Task 3: process deviation recorded: tests were written after the code; the failing run was a compile error. The reviewer's mutation check found the tests fail on wrong behavior.
- Task 3: minor (deferred): `stateValue` trusts `byStory` without `isChosen` (only `PhotoStory.card` builds pages).
- Task 3: complete (commits 62ca0d7..5aca2f1, approved).
- Task 4: built at 8a22002 (base 84abc4b). Review: spec ok; one Important, plan-mandated.
- Task 4: Ruling: the move removes the first person's story link only when NO memory that holds the photo names that person now, in any session — the plan said "no memory of that session", but one photo can be the subject of two stories, and the spec forbids removing a link another story placed; `letGo` already keeps story links while another session points at the photo — cost if wrong: a photo stays on a page a little longer. The same guard applies to Undo's removal of an added link (the reviewer's Minor 1): one rule, one function.
- Task 4: accepted: `only:` on `linkToPeoplePages` (a move adds to the new person only; a plain call would backfill other people, against decision 14).
- Task 4: minor (deferred): Undo restores a story link to a page the owner hid after the move.
- Task 4: minor (deferred): a restored link goes last; a photo that was the key photo is not the key photo after Undo when the page gained another photo. Open for the owner.
- Task 4: minor (deferred): `photoPages` is `public var`; make it `public internal(set)`.
- Task 4: minor (deferred): no test pins what `only:` is for (the moved moment also names a person who lacks the photo).
- Task 4: fix round 1/5 (2 addressed, 0 open — still-named rule across sessions, same guard on Undo; commits 5ee1193..43dd1e3)
- Task 4: complete (commits 84abc4b..43dd1e3, review clean after one fix round). Kit 1394.
- Task 5: dispatched from 43dd1e3, in parallel with the Task 4 re-review (different files).
- Task 5: complete (commits f958e1e..bdd5fa1, approved). UI: PhotoCard 26/0, PeopleGuess 15/0, Landing 14/0, PhotoStory 7/0, Photos 21/0. Kit 1394. Reviewer read every changed line of existing tests: each forced by chips that start filled, none weakened or deleted.
- Task 5: accepted outside the brief: `CardHandler.onPeopleMoved` so the session's page refreshes the card after a move and its Undo (a real gap, with a UI test); the seed's hand link to Maya removed; the flag `-uiTesting-photoStoryAssumedName`.
- Task 5: Ruling: the spec's status line gains what is built at the end of the build, not per task (the dispatch said to leave it) — goes in the final fix wave.
- Task 5: minor (deferred): no UI test asserts that a page that held the photo before the story keeps the owner's link ("added") after Keep.
- Task 5: minor (deferred): the card's height changes when the last story chip is taken off (two-line story line becomes the one-line tap line), against OVERVIEW's "a choice changes the state of a control, not the layout". Open for the owner, or reserve the height.
- Task 5: minor (deferred): the device check's move ruling leaves out the Undo half; one line is not STE ("No older story must…").
- Task 5: minor (deferred): `sam` is in the seed's function-level guard; look it up inside `if assumedName`.
- Checked: the Task 1 minor (static `link` refusing a declined pair) was closed in Task 2 (`aStoryLinkToADeclinedPageWritesNothing`).
- Task 7: dispatched from bdd5fa1 while Task 5 was in review (independent files). Task 6 waits for Task 7 (one simulator, one implementer at a time).
