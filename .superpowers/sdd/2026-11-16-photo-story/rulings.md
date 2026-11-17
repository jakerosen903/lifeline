# Rulings — plan: docs/plans/2026-11-16-photo-story.md

Format: `Ruling: <what was decided> — <why> — <what it costs if wrong>`. Non-obvious rulings also go into docs/DECISIONS.md.

- Pre-flight: Ruling: Task 5's `testTwoStoriesFromTheSameFavorite` asserts `session.photo` only — the card arrives in Task 6 — cost if wrong: none.
- Pre-flight: Ruling: the `-uiTesting-seedPhotoStory` seed holds two photo sessions; the second has no kept memory and its photo has no other home — Task 6's delete-dialog test needs one — cost if wrong: none.
