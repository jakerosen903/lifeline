# Backup: safety-copy folder is injected, names are reserved

Status: in progress, 2026-10-25. Follows `2026-10-23-m6-steady.md` (safety copies, item 5).

## Problem

1. `Backup.stage` and `Backup.applyPendingRestore` take `safetyCopyDirectory: URL? = nil`. A nil folder resolves to the user's Documents folder. Three tests in `BackupTests` omit the folder. On macOS, `swift test` therefore writes `Lifeline-before-restore-<stamp>.lifeline` into the real `~/Documents`. The files accumulate.
2. Two stages in the same second pick the same name. `freeName` checks that a name is free but does not take it. Both exports then write the same `.<name>.partial` file. One export removes or moves the other's partial file. The second move fails with `NSCocoaErrorDomain` code 4. The failure is a race, so a rerun passes.

## Design

1. `stage` and `applyPendingRestore` must take `safetyCopyDirectory: URL` with no default. Each caller must say where safety copies go. The app passes `Backup.safetyCopyDirectory()` (Documents). Each test passes its own temporary folder.
2. `freeName` must reserve the name. It creates an empty placeholder with an exclusive create (`Data.WritingOptions.withoutOverwriting`, which is `O_EXCL`). A name that another writer took first is skipped. The function throws when the folder cannot take a file.
3. `export` must write to a partial file with a unique name (`.<name>.<UUID>.partial`). Two exports to one folder never share a partial file.
4. `export` must put the finished file in place with one atomic `rename(2)`. The rename replaces the placeholder. No window exists in which the name is free.
5. When a stage or a launch-time save fails after the reservation, the empty placeholder must be removed. A failed export also removes its partial file.

## Edge cases

1. Documents cannot be resolved at launch: `Dependencies.live()` throws, as it does when `AudioLocation.defaultRoot()` fails. Both folders come from the same `FileManager` call, so one fails only when the other does.
2. A crash between the reservation and the rename leaves an empty `.lifeline` file. The name stays taken; no data is lost. The person can delete it.
3. A crash during the export leaves a hidden partial file. It has a unique name, so the next export does not remove it. This is accepted: it was already possible for a full disk.

## Tests

1. Every test in `BackupTests` passes its own folder from `docs()`.
2. A new test stages many restores in parallel into one folder. Each must get a distinct safety copy, and no partial or placeholder files must remain.
3. Several full `swift test` runs must pass with no new files in `~/Documents`.
