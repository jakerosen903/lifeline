# Rulings — plan: docs/plans/2026-11-16-sections-photos.md

Format: `Ruling: <what was decided> — <why> — <what it costs if wrong>`. Non-obvious rulings also go into docs/DECISIONS.md.

- Setup: Ruling: the worktree `../lifeline-photos` existed already, so `git worktree add` was skipped and `origin/main` was merged into it in place — the owner's command would have failed on an existing path — cost if wrong: none; the branch and path are the ones the plan names.
- Setup: Ruling: the worktree's own `ios/Config/Local.xcconfig` (placeholder copy of the example) was replaced by the one from `lifeline-cards`, as the owner's setup says — cost if wrong: none; the file is git-ignored.
