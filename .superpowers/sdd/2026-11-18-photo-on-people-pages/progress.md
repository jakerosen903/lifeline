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
