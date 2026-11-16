# SDD ledger — plan: docs/plans/2026-11-16-sections-photos.md
Spec: docs/specs/2026-11-15-five-sections.md. Worktree /Users/jakerosen/dev/lifeline/lifeline-photos, branch sections-photos.
Execution: subagent-driven-development. Rulings: see rulings.md beside this file.
Setup: plan commit 5c6c90d; merged origin/main (77d0440) as f0eb114 (merge, no rebase). Local.xcconfig copied from lifeline-cards (git-ignored). xcodegen generate run.
Migration number: v12 is the last on origin/main at 77d0440; no remote branch registers v13. S4 takes v13.
Owner gates before Task 1: (a) yes on the exact v13 schema (plan decision 2); (b) v13 free — confirmed above.

Pre-flight (one row per shared file or interface, one row per task):
- T1→T2: PhotoRepository, Photo, PhotoSubject, PhotoTakenAt produced in T1; T2 consumes insert/link/unlink/deleteUnlinked/fileNames. Signatures agree. OK.
- T1→T5: covers(type:) produced in T1, read in EntitiesViewModel in T5. OK.
- T2→T3: PhotoLocation.directoryName/directory(under:), PhotoLibrary, GeneratedPhoto consumed by Backup and BackupTests. OK.
- T2→T4: PhotoLibrary, PhotoImport.thumbnail, PhotoCaption, GeneratedPhoto consumed by the app. Kit stays UIKit-free (UIImage only in the app's PhotoImageCache). OK.
- T4→T5: PhotoImageView, PhotoImageCache, launchWithPhotos, fixturePath, addPhotoFromMenu. T5 changes UITestHelpers.swift (adds colour(of:at:), isNear) that T4 also edits: additive. OK.
- T4→T6: PhotoShelf, PhotoHeader, PhotoRow, PhotoViewer, addPhotoFlow, ErrorLine. T4 moves ErrorLine out of YouScreen.swift; T6 edits YouScreen.swift again: sequential, OK. Both add tests to PhotosUITests.swift: additive. OK.
- T4/T6 seed: writePhotos (T4) seeds "The tree house" and Jordan's photos that only T6's tests read. OK.
- T1 self: test calls store.memories.fold(s, into: t); the file list names fold(_:into:in:). Both exist (MemoryRepository.swift:420, :424); the change goes in the static one. OK.
- T1 self: v13OnAPopulatedV12Database expects photo count 2 after the entity delete: p1 (link cascaded) and p2 (row written, cover link refused). Agrees with the schema. OK.
- T2 self: 12000×1500 → 2048×256; 3000×2000 with orientation 6 → 1365×2048 (width < height). Agrees with decision 3. OK.
- T3 self: the manifest fields are optional and export always writes them; aManifestWithoutPhotoFieldsStillReads uses rewritingManifest to nil them. OK.
- T4 self: step 1 commits Dependencies.photos before the views exist; needs only T2's PhotoLibrary. OK.
- T5 self: testNoTileOffersAPhotoWhenSomeHaveOne needs TileFace hidden from accessibility (stated). OK.
- T6 self: You's failure uses you.error, not photo.error (decision 21 says so). OK.
- T7 self: "before" worktree from origin/sections-you — the remote branch still exists. Day of the DECISIONS entry: the day it is written.
- Global: simulator id 88EC5B09-3A30-4544-8145-F5246BB99AEE exists (iPhone 17 Pro, booted).
Pre-flight result: no conflict found.
Baseline: swift test on f0eb114 → 862 tests in 8 suites passed, 0 failures.
Owner gate: v13 schema approved by the owner in chat on 2026-11-16 ("Yes, ship v13"), as shown: photo + photo_link with entity_id/memory_id, check, four partial unique indexes, two plain indexes.
Task 1: fix round 1/5 (6 addressed, 0 open — vacuous check assertion; no behavioural RED (mutation checks a–e done); setCover/unlink on an unlinked photo; signed digits; unused column; fold with no target cover; commits 7d331fc..b81932c)
Task 1: minor (deferred): PhotoRepository role fallback `?? .attached` hides a corrupt role value (schema has no check on role).
Task 1: note: the implementer wrote code before tests; RED was a compile error only. Remedied by five mutation checks, summarised in task-1-report.md. Later dispatches say "test first".
Task 1: note: hungFinalizeDoesNotBlockSegmentCloseOrStop and drainGivesUpAtItsDeadline failed in 3 full runs under load, pass alone and in the final run; timing tests, not photo code.
Task 1: complete (commits 426e7e0..b81932c, review clean; swift test 878)
Task 2: fix round 1/5 (5 addressed, 0 open — failed-write cleanup unproven (two tests + mutations added; internal writeCopy seam); repair of a missing file on re-add (ruling); sweep doc comment; deleteIfPresent rename; P3 and TIFF assertions; commits e18267c..c644a0f)
Task 2: minor (deferred): a deduplicated re-add drops a later assetLocalID (the first one is kept).
Task 2: minor (deferred): static sweep is not serialised with add; documented "run at launch before any add" — Task 4 must wire it so.
Task 2: note: in aWriteThatFailsStoresNothing the throw is the .partial Data.write (Cocoa 513), not the folder setup.
Task 2: note: drainGivesUpAtItsDeadline flaked once under load again; passes alone.
Task 2: complete (commits dc11f8b..c644a0f, review clean; swift test 907)
