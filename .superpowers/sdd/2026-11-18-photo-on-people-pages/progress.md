# SDD ledger — plan: docs/plans/2026-11-18-photo-on-people-pages.md

Spec: docs/specs/2026-11-18-photo-on-people-pages.md (approved 2026-11-18, parts 1-4). Base: 4389cbc.
Pre-flight: Task 6 needs a column that Task 1 owns: Task 1 text now carries it (agrees). Tasks 2 and 4 both change PhotoRepository (sequential, agrees). Tasks 3, 5 and 6 all change the card model and view (sequential). Task 7 is independent.

## Tasks
- Task 1: complete (commits 07d510d..e0b05cf, review clean). Kit 1358. Reviewer read every caller of the public `link` and `unlink`: all are owner taps or the seed.
- Task 1: minor, carried into Task 2's dispatch: the static `link(… origin: .story …)` does not refuse a declined pair itself; the rule is a comment.
- Task 1: minor (deferred): `v16FromV13` does not assert `photo_pages_done = 0` or that `photo_page_declined` exists.
- Task 1: minor (deferred): a comment that unlinking from the owner's own page records a harmless decline.
