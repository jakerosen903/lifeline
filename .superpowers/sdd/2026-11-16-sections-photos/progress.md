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
Task 3: minor (deferred): BackupTests photoBytes() repeats export's size sum (a shared bug would cancel out).
Task 3: minor (deferred): the "nil is omitted" check uses a local JSONEncoder, not JSONEncoder.manifest.
Task 3: minor (deferred): Backup.swift audio and photo size loops are near-duplicates.
Task 3: complete (commits 487bbcc..3235cf6, review clean; swift test 913)
Task 4: minor (deferred): PhotoViewer Done is .plain with no foregroundStyle — system primary, not a Theme text colour (Global Constraints). Fix in the final wave.
Task 4: minor (deferred): PhotoShelf.load failure copy "Could not show the photos: …" is not in the plan's copy list and uses the photo-action slot. Final wave: send load failures to the page's existing error line.
Task 4: minor (deferred): "Adding the photo…" row and an existing cover show together, progress above the cover.
Task 4: minor (deferred): UITestSeed.writePhotos returns silently when Jordan, Maya or "The tree house" is missing; should throw.
Task 4: minor (deferred): UITestSeed blocks main on a semaphore around a default-priority detached task (test-only; priority-inversion warning).
Task 4: minor (deferred): viewer buttons are not disabled while an action is awaited (double tap repeats an idempotent call).
Task 4: minor (deferred): EntityViewModel binds shelf.onError after init through a captured local.
Task 4: note: kit 914; UI one run: PhotosUITests 7/0, EntityPageUITests 8/0, EntitiesUITests 2/0, ShellUITests 13/0, YouUITests 22/0.
Task 4: complete (commits 4fa3d7a..0db34d7, review clean; 4 rulings in rulings.md)
Task 5: cannot-verify checked: PhotoImageView loads in .task(id:) and PhotoImageCache is an actor over NSCache (grep at 1d68cf9). OK.
Task 5: minor (deferred): colour(of:at:) records an XCTFail per poll inside waitForColour on a screenshot failure.
Task 5: minor (deferred): EntitiesViewModel.refresh leaves covers stale when covers(type:) throws after rows updated.
Task 5: note: kit 914 (two known timing flakes under load, pass alone); UI one run: PeopleUITests 10/0, PhotosUITests 7/0, ShellUITests 13/0.
Task 5: complete (commits 1a0ad6d..1d68cf9, review clean; 2 rulings in rulings.md)
Task 6: fix (controller ruling, not a review round): testAMemoryShowsItsPhotos could not pass as the plan wrote it; reveal + memory.range (rulings.md); commit 6b3fd14; PhotosUITests 12/0.
Task 6: cannot-verify checked: the memory page has no refresh on appear or on coverClosings. Not a gap: MemoryViewModel reads in init (allowed), a memory's photos change only through this page's own actions (each reloads the shelf), and every sheet dismissal calls refresh(). Seeded photo shows on open (testAMemoryShowsItsPhotos).
Task 6: minor (deferred): YouScreen scrolls to top on any cover id change, including a removal to nil; scroll only when the new value is non-nil. Same check for EntityScreen.
Task 6: minor (deferred): addPhoto/makeCover/removePhoto/photoFailed/clearPhotoError wrappers repeat in Entity, Memory and You view models.
Task 6: note: PhotoAddingLine and PhotoErrorSlot were extracted from EntityScreen (shared by three pages); PortraitHeader has two extra parameters (isAdding, label). Reviewer accepted both.
Task 6: note: kit 914 (drainGivesUpAtItsDeadline flaked, passes alone); UI: PhotosUITests 12/0, YouUITests 22/0, KindsUITests 1/0, SameStoryUITests 5/0, SteadyUITests 6/0, ShellUITests 13/0.
Task 6: complete (commits ab4bef0..6b3fd14, review clean; 1 ruling in rulings.md)
Task 7: fix round 1/5 (7 addressed, 0 open — one copy per photo and merge-moves-photos missing from the docs; precision and STE minors; commits add9004..9334904)
Task 7: minor (deferred): DECISIONS S4 "Source" line omits decisions 7 and 11.
Task 7: minor (deferred): OVERVIEW "Photos": the caption sentence sits in the SHA-256 paragraph.
Task 7: note: "undoing a merge leaves the photos on the target" is stated from plan decision 11, not verified in code — final review to check.
Task 7: note: letter-tile tint differs between before/after People screenshots because the tint derives from the entity id, random at each seed; this branch does not touch it.
Task 7: complete (commits 237ff36..9334904, review clean; swift test 914)
Final review (whole branch, 77d0440..443cb17): 0 Critical, 2 Important (I1 adding line not shown during hand-over; I2 a deleted page's photo travels in the next export), 6 Minor (M1 unmerge test; M2 picked-* temp file after a kill; M3 Done colour; M4 staging photos not excluded until relaunch; M5 placeholder flash and repaired file not reloaded; M6 docs). Full text: final-review.md. Deferred-minor triage: fix now = T4 Done colour, T7 two doc lines; the rest leave. No ruling judged wrong. "Undo of a merge leaves photos on the target" verified by reading MergeActions.swift and MemoryRepository.swift.
Final review: one fix wave dispatched (I1, I2, M1–M6). FIX_BASE recorded below.
Final fix wave: commits 1fa910d..5a75faa (c0dc1cb M1, 87d3cb4 I2, 9cb21c4 M4, ed80fab I1, 64f184c M3, bb2c14e M2+M5, 5a75faa M6). Kit 923. UI: PeopleUITests 10/0, PhotosUITests 12/0, SteadyUITests 6/0.
Final fix wave re-review: I1, I2, M1–M6 ADDRESSED. New Important: M4's flag on the staging folder moves to Lifeline/ at the swap; a kill before the clear strands the database out of the cloud backup. Ruling (rulings.md): flag staging/audio and staging/photos only; targeted fix dispatched to the same implementer (kit only).
Final review: minor (left): a People tile does not reload a repaired file until the tile view is made again.
Final fix wave: residual fixed in 575910b (staging/audio and staging/photos flagged; no flag on the staging folder; no clear). Controller read the diff: matches the ruling. swift test --filter Backup 29/29; full 924/925 (drainGivesUpAtItsDeadline flake, passes alone).
Full UI run 1 (on 5a75faa): 130 tests, 1 failure — YouUITests.testAPlayErrorLeavesAnOpenUndoInPlace. Diagnosis (you-undo-debug-report.md): the test races the 6 s Undo window (CardHandler.undoWindow, unchanged since 466a5fb); fails 3 of 8 iterations on base 77d0440 too; not from this branch; no change made. For the owner.
Full UI run 2 (on 51fc882, final): Executed 130 tests, with 0 failures. TEST SUCCEEDED.
