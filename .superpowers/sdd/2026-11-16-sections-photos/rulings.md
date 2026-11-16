# Rulings — plan: docs/plans/2026-11-16-sections-photos.md

Format: `Ruling: <what was decided> — <why> — <what it costs if wrong>`. Non-obvious rulings also go into docs/DECISIONS.md.

- Setup: Ruling: the worktree `../lifeline-photos` existed already, so `git worktree add` was skipped and `origin/main` was merged into it in place — the owner's command would have failed on an existing path — cost if wrong: none; the branch and path are the ones the plan names.
- Setup: Ruling: the worktree's own `ios/Config/Local.xcconfig` (placeholder copy of the example) was replaced by the one from `lifeline-cards`, as the owner's setup says — cost if wrong: none; the file is git-ignored.
- Task 2: Ruling: a repeat add of a photo whose row exists and whose stored file is missing writes the file again (same id and file name), then links — picking the photo again is the person's only way to repair a photo that does not show; the plan is silent (decision 10 only says the sweep keeps such a row) — cost if wrong: one extra file write on a rare path; remove the branch.
- Task 2: Ruling: the plan's `aWriteThatFailsStoresNothing` (photos folder at 0o500) stays as written, and two tests are added that fail after the folder setup (a foreign-key failure at the row insert; a failure at the file write) — the plan's test may throw at the backup-exclusion step and so not prove Review Focus 5 — cost if wrong: two extra tests.
