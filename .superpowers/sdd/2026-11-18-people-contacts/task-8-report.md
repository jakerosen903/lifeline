# Task 8 report: the person's page

- `PersonChipLine.confirmLabel(name:)` (kit, tested): first word of the name, "person" when empty.
- `assumedOutline()` shared modifier (People/AssumedOutline.swift), used by PersonChip and the page row.
- `EntityViewModel`: `guessed`, `confirm`, `personSheetDone`, `undoPersonMove`, `personMove`. Guards: person, not owner.
- `EntityScreen`: guessed rows become outlined cards with the "Assumed" line, "Yes, this {name}" and "Someone else…"; the sheet and notice slot as in MemoryScreen.
- Rulings R32, R33. Kit suite: only known timing flakes (drainGivesUpAtItsDeadline, interruptionClosesOpenSegment) under load.
