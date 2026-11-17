# S4: Photos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The person can add a photo to a person, place, thing or memory page, or to You, with the system picker. The app keeps its own downscaled copy, shows the subject's cover on its People tile and at the top of its page, shows several photos in a small row, carries every photo in the backup export, and keeps them out of the phone's cloud backup.

**Architecture:** Task 1 adds migration v13 (`photo`, `photo_link`) and `PhotoRepository`, with batched reads. Task 2 adds the file side in the kit: a `PhotoLibrary` actor that downscales, strips metadata, writes the file before the row, removes, and sweeps orphans at launch. Task 3 extends `Backup` so export, restore and the safety copies carry `photos/`. Tasks 4 to 6 build the app: the entity page (header, row, viewer, "Add a photo"), the People tiles, then the memory page and You. Task 7 is docs, screenshots and the device check.

**Tech Stack:** Swift 6, SwiftUI on iOS 26 (`photosPicker`, `PhotosPickerItem`, `Transferable` with `FileRepresentation`), ImageIO, CryptoKit, GRDB 7 (migration v13), ZIPFoundation, Swift Testing, XCUITest.

**Spec:** `docs/specs/2026-11-15-five-sections.md`, sections "Photos", "People", "Entity page", "You", "Data", "Appearance and accessibility", "Owner's calls" (call 3: photos stay out of the phone's cloud backup) and "Left to the builder" (downscale size; how a merge treats photos). The umbrella plan `docs/plans/2026-11-15-sections.md`, Part 1 (S4 budget; search is S5, Timeline S6, Things S7, Places S8, guessed locations S9). The S2 plan `docs/plans/2026-11-15-sections-pages.md` ("After S2": S4 replaces `TileFace`'s content and keeps the frame) and the S3 plan `docs/plans/2026-11-16-sections-you.md` (decision 14 and "After S3": photos on You wait for S4). `docs/DECISIONS.md`, entries of 2026-11-15 and 2026-11-16, and 2026-10-24 "Copies of the archive stay out of the phone's cloud backup". `docs/OVERVIEW.md` sections 7 and 9. Mock-ups: `docs/design/Sections.html`, the screens "People" and "A page, with a photo", "The same page, with little" and "You, at the top". Read all of these before Task 1.

**Worktree and branch:** `/Users/jakerosen/dev/lifeline/lifeline-photos`, branch `sections-photos`, based on the tip of `origin/sections-you` (`90f7b54`). Work only there.

---

## Decisions made in this plan

The spec leaves these open. Each one is decided here so the owner can overrule it before work starts.

1. **Migration v13, additive.** Two new tables and their indexes. No existing table or column changes. The number is confirmed at implementation time: if another branch has taken v13 on `origin/main`, this one takes the next free number and every "v13" in this plan follows it. A shipped migration is never edited.
2. **The link table has a foreign key per subject kind (differs from the spec).** The spec names `photo_link(photo_id, element_kind, element_id, role, sort_order)`. This plan stores `photo_link(photo_id, entity_id NULL, memory_id NULL, role, sort_order)`, with a check that exactly one of the two is set, and `on delete cascade` on all three keys. Why: a memory goes in four places today (`MemoryRepository.delete`, `SessionRepository.deleteSession`, `MemoryRepository.fold` for merges and `mergeGroup`), and an entity in one. A cascade removes the photo's link on every path, in the same transaction, with no code at each call site. A polymorphic key would need triggers, and a trigger's `delete from` trips the destructive-migration guard in `.github/scripts/pr_guards.py`. Cost: a third kind of subject later (a chapter, say) needs a new column. `photo` keeps the spec's columns (`lat`, `lon`, `taken_origin`) and adds `location_origin`, `pixel_width`, `pixel_height` and `added_at`.
3. **The stored copy.** JPEG, quality 0.85, longest edge at most 2048 pixels, never enlarged. The orientation is applied to the pixels, so the file has no orientation flag. Pixels are 8-bit Display P3 (a superset of sRGB, so a wide-colour photo keeps its colours and an sRGB one loses nothing). A transparent area is drawn on white. An HDR gain map is not kept. HEIC, PNG, JPEG and any other format ImageIO reads are accepted. The file is `<root>/Lifeline/photos/<photo id>.jpg`. Why JPEG: an exported copy opens on any computer.
4. **The stored file carries no metadata.** No EXIF, no GPS, no TIFF dates, no maker notes. The date and location the photo carried live only in the database row, with origin `exif`. Deleting the original from the photo library changes nothing in the app.
5. **What is read from the picked file.** `DateTimeOriginal` only, as a date and time with no time zone (`2012-06-14T15:32:10`); no file date and no `DateTime` (which is an edit date). The GPS latitude and longitude only when both are present and in range. The asset identifier, when the picker gives one. Nothing else.
6. **What the app does with the metadata: nothing but store and say it.** The date shows as "taken 14 June 2012" under the page header's photo and in the photo viewer, and is the photo's accessibility value. The location shows nowhere. Neither changes a memory, an entity, a range or a location, and neither leaves the phone except inside the person's own backup file.
7. **One stored copy per photo.** The SHA-256 of the picked file identifies a photo. Picking the same photo for a second page links the one copy to both. Picking it again for the same page changes nothing.
8. **The cover.** The first photo added to a subject is its cover. "Make this the cover" changes it. When the cover is removed, the oldest-added photo left becomes the cover. When the last photo goes, the subject has no cover: its tile shows the monogram again and its page has no header.
9. **Removing.** "Remove photo…" asks first and removes the photo from this page only. A photo with no page left is deleted at once: the row first, then the file.
10. **No orphaned files.** Deleting an entity or a memory removes its photo links by cascade, in the delete's own transaction. A photo left with no link, a file with no row, and a half-written `.partial` file go at the next launch, in `PhotoLibrary.sweep(root:photos:)`. `Dependencies.live()` and `uiTesting()` call it after the database opens and before any screen reads. An import writes the file first and the row second, so a kill between them leaves only a file, which the sweep removes. The sweep never deletes a row because its file is missing; such a photo does not show (the image does not load and the view falls back).
11. **A merge moves photos.** `MemoryRepository.fold` (used by "Same story" merges and group merges) moves the source memory's photo links to the target before it deletes the source. A source cover becomes an attached photo when the target has a cover. Undoing a merge leaves the photos on the target. There is no entity merge in the code today, so nothing else changes.
12. **The page header.** The cover sits at the top of the page, inside the page margins, rounded (radius 22), filled and clipped: 4:3 for a landscape cover, 3:4 for a portrait one, so a portrait photo is not cut to a strip. The title and the person's words sit under the photo, never over it, so no scrim is needed for 4.5:1 and the dark palette has nothing to redo. The caption "taken {date}" sits under the photo when the date is known. Tapping the photo opens the viewer.
13. **The Photos row.** On a person, place or thing page and on You it shows when the subject has two or more photos (one photo is already the header). It holds every photo, cover first, then in the order added. It sits after "Often with" and before the moments (spec "Entity page"). On a memory page, which has no header, it shows with one photo or more, under the title and Play.
14. **The viewer.** A sheet with the photo fitted to the screen, the caption, "Make this the cover" (only when the photo is not the cover), "Remove photo…" and "Done". No zoom in this PR.
15. **You: the smallest honest version.** You shows the owner's cover above the name, the same header as a page, and the Photos row with two or more. "Add a photo" is in a new "…" menu on You's toolbar, beside "Settings", and adds to the owner's entity, so the owner's page shows the same photos. Photos placed on the life strip at their years wait: that uses the photo's date to place it, and decision 6 keeps metadata to a caption until a later spec decides where it may be offered.
16. **The People tile.** The cover fills the tile's face, same frame and corner radius; without a cover the monogram stays. The tile reads to VoiceOver as before (the name, then the own words); the face stays hidden from VoiceOver. No tile carries an add mark.
17. **Thumbnails.** No thumbnail files. The app decodes the stored copy with ImageIO downsampling (`kCGImageSourceCreateThumbnailAtIndex`) at 400 pixels for tiles and the row, and 1600 for the header and the viewer, on an actor, never on the main thread. An `NSCache` keeps the results, so scrolling the grid decodes each tile once. The grid reads every cover in one query.
18. **The picker.** `.photosPicker(isPresented:selection:matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())`, one photo at a time. `.shared()` gives the asset identifier with no permission prompt. The picked photo arrives as a file (`FileRepresentation(importedContentType: .image)`), never as one `Data` in memory, so a 100 MB image does not spike memory.
19. **Accessibility labels say only what the person did.** "Photo of {title}" on a person, place or thing page, "Photo of you" on You and the owner's page, "Photo for {memory title}" on a memory page. The value is "taken {date}" when known. The app never describes what is in a photo.
20. **Backup format.** The archive gets `photos/*.jpg` entries, stored without compression. `BackupManifest` gets two optional fields, `photoFiles: Int?` and `photoBytes: Int64?`. Export always writes them (0 with no photos). An archive without them reads as before. The restore summary and the export progress copy do not change.
21. **Notices.** While a photo is being added, "Adding the photo…" shows with a spinner where the photo will go. A failure shows in a slot pinned at the bottom of the page, above the record bar: ink text with a red symbol, announced to VoiceOver. On You it uses You's existing slot. Copy: "Could not add this photo: {reason}", "Could not remove this photo: {reason}", "Could not make this the cover: {reason}". An unreadable file's reason is "Lifeline cannot read this file as a photo."
22. **A test seam for the picker.** UI tests cannot drive the out-of-process picker. Under `-uiTesting-pickPhoto <path>`, "Add a photo" skips the picker and adds that file, as `-uiTesting-restoreFrom` skips the file picker. Under `-uiTesting-seedPhotos`, the seed adds generated photos (solid colours with a circle; no real person's photo).
23. **Before screenshots need no cherry-pick.** The "before" screens are People, Maya's page, a memory page and You at the tip of `origin/sections-you`, with `-uiTesting-seedPeople` and `-uiTesting-seedPortrait`, which exist there.

### Conflicts and limits found while planning

- **Schema shape (owner should confirm before Task 1).** Decision 2 changes the spec's `photo_link` columns. The tables are the same in meaning. Once v13 ships to the phone, the shape is permanent.
- **Backup format (owner should know).** A copy made after S4 has schema v13. A build before S4 refuses it ("This copy was made by a newer version of Lifeline."), as it refuses any newer schema today. A copy made before S4 restores on S4 and migrates. Photo files are only in copies made after S4.
- **The location may not arrive.** Whether the system picker hands over GPS in the file, and whether the person's "include location" choice in the picker removes it, is decided by iOS. The kit tests use generated files with GPS. Device checklist item 4 checks a real photo.
- **"Taken" is the camera's clock.** A camera set to the wrong date gives a wrong "taken" date. The caption says "taken", which is what the file says, and nothing uses it as a fact about a memory (decision 6).
- **Out of S4's scope, by the ship order:** a photo on a Timeline row (S6), Things tiles with photos (S7), a place's small map and anything that uses a photo's location (S8), photos in search (S5), photos in "Often with" chips (mock-up only), suggested clusters and face naming (later, no schema change: `asset_local_id` is kept for it).
- **Dark and increased-contrast values** still have no PR. S4 adds no colour value; every new view uses `Theme` tokens, and no text sits on a photo.

---

## Global Constraints

- Deployment target iOS 26.0. Swift 6 with complete strict concurrency. Verify `photosPicker(isPresented:selection:matching:preferredItemEncoding:photoLibrary:)`, `PhotosPickerItem.itemIdentifier` and `FileRepresentation(importedContentType:)` against the current documentation before use.
- One migration, v13, additive (decisions 1 and 2). Never edit a shipped migration. The new migration needs a change to `MigrationsTests.swift` (the guard checks for it).
- The app asks for no photo-library permission and never reads the library on its own. No `PHPhotoLibrary.requestAuthorization`, no `PHAsset` fetch.
- A photo's date and location are stored with origin `exif` and only stored. They change no memory, entity, range or location, and are sent nowhere (non-negotiable 2 and 3, PRINCIPLES 5).
- Photos live in `<root>/Lifeline/photos/`, excluded from the phone's cloud backup like `audio/` (owner's call 3). The stored file has no metadata (decision 4).
- No "add photo" mark on a tile, no empty photo frame, no count of what has no photo (PRINCIPLES 9). "Add a photo" lives only in a page's menu. A page or tile without a photo looks complete.
- Copy, exact:
  - Menu item: "Add a photo". Section heading: "Photos".
  - Caption and accessibility value: "taken {d MMMM yyyy}", for example "taken 14 June 2012" (Gregorian, `en_GB`, no time).
  - Accessibility labels: "Photo of {title}", "Photo of you", "Photo for {memory title}".
  - Viewer: "Make this the cover", "Remove photo…", "Done". Dialog: title "Remove this photo?", message "It leaves this page. The original stays in your photo library.", button "Remove photo".
  - Progress: "Adding the photo…". Errors: "Could not add this photo: {reason}", "Could not remove this photo: {reason}", "Could not make this the cover: {reason}". Unreadable file: "Lifeline cannot read this file as a photo."
- View models do no reads in `init` (except `MemoryViewModel`, which already reads in `init` and is not refactored here) and expose `isLoaded`. A visible screen refreshes on appear and when `home.coverClosings` changes.
- Lists read in batches. The People grid reads every cover in one query. No image is decoded on the main thread or more than once per scroll.
- Text colours: `Theme.ink`, `Theme.secondaryText`, `Theme.oliveText`, `Theme.ochreText`. `Theme.oliveOnFill` tints `.bordered` buttons. `Theme.olive` is for fills and prominent buttons only. Headings use `sectionHeadingStyle()`. Every text colour reaches 4.5:1 on its surface; no text sits on a photo. No new colour values.
- Every control is at least 44 by 44 points, with the frame and `contentShape` inside the button's label. Metadata uses the footnote style or larger. Dynamic Type must not clip.
- Errors and notices on a page: ink text with a red symbol only, in the pinned slot, announced with `AccessibilityNotification.Announcement`.
- Keep these accessibility identifiers: `entities.row`, `entity.title`, `entity.ownWords`, `entity.more`, `entity.rename`, `entity.addDates`, `entity.detail`, `entity.moment`, `entity.oftenWith`, `people.grid`, `people.list`, `memory.change`, `memory.kind`, `home.settings`, `home.start`, `you.name`, `you.error`, `entities.aboutYou`. New ones: `entity.addPhoto`, `memory.more`, `memory.addPhoto`, `you.more`, `you.addPhoto`, `photo.header`, `photo.caption`, `photo.thumb`, `photo.adding`, `photo.error`, `photo.makeCover`, `photo.remove`, `photo.confirmRemove`, `photo.done`, `photo.viewer`.
- Kit tests: `cd ios/LifelineKit && swift test`. They run in full at every task.
- UI tests: `cd ios && xcodegen generate && xcodebuild test -project Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/<Class>`. Each task names the classes it runs. The task report gives the verbatim `Executed N tests, with M failures` line for each class. The whole UI suite runs once, by the controller, after the final review's fixes. No task runs it.
- Real TDD: each new test is seen failing before the code that makes it pass.
- No test's assertions are weakened. A test that asserts behaviour this plan changes moves to the new behaviour with an assertion of equal strength. The plan names each one: `MigrationsTests.schemaVersionsOrderByMigrationPosition` (Task 1: `"v12"` becomes `"v13"`).
- The out-of-process picker cannot run under UI tests. The seam is `-uiTesting-pickPhoto <path>` (decision 22). Device checklist items 1 to 4 cover the real picker.
- Test images are generated (solid colours and shapes). Never a real person's photo. Fixtures are invented; never a real person's words or places.
- `ios/Config/Local.xcconfig` is never committed.
- Commit messages are imperative and one line, with a body when the why is not obvious. No AI attribution lines. Nothing is pushed.
- Before and after simulator screenshots with invented data go under `docs/screenshots/sections-photos/` (Task 7).
- Docs under `docs/` use ASD-STE100 style.

## Review Focus

1. **Migration with data.** A v12 database with sessions, memories and entities migrates to v13; every existing row and column is unchanged, and the new tables accept a photo. Task 1 (`v13OnAPopulatedV12Database`).
2. **Backup both ways.** A v12 archive (no photo table, no photo fields in the manifest) restores on this build and migrates; a v13 archive with photos restores its files, out of the cloud backup; the safety copy and the moved-aside archive keep the phone's photos. Task 3 (`aV12ArchiveRestoresAndMigrates`, `aRestorePutsThePhotosBack`, `theSafetyCopyKeepsThePhonesPhotos`, `theReplacedArchiveKeepsPhotosAddedAfterStaging`, `aManifestWithoutPhotoFieldsStillReads`).
3. **Orphaned files.** Deleting an entity, a memory or a whole session leaves no photo file after the sweep; a merge keeps the photo on the target. Task 1 (`deletingASubjectRemovesItsLinks`, `foldingAMemoryMovesItsPhotos`) and Task 2 (`aPhotoWithNoPageGoesAtTheSweep`, `deletingASessionLeavesNoPhotoFileAfterTheSweep`).
4. **A kill mid-import.** The file exists and the row does not, or a `.partial` file is left: the next launch removes it and nothing else. Task 2 (`aFileWithNoRowGoesAtTheSweep`, `aPartialFileGoesAtTheSweep`, `aRowWithAMissingFileStays`).
5. **A very large or corrupt image, or a full disk.** A 12 000-pixel image is stored at most 2048 pixels; a file that is not an image, or a write that fails, stores no row and no file and says why. Task 2 (`aHugeImageIsStoredAtMost2048Pixels`, `aFileThatIsNotAPhotoStoresNothing`, `aWriteThatFailsStoresNothing`) and Task 4 (`testAnUnreadablePhotoSaysSoAndAddsNothing`).

---

### Task 1: Store — photo tables (v13) and batched reads

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/Migrations.swift` (append `v13` after `v12`)
- Create: `ios/LifelineKit/Sources/LifelineKit/Domain/Photo.swift` (`PhotoID`, `PhotoOrigin`, `PhotoTakenAt`, `Photo`, `PhotoSubject`, `PhotoRole`, `PlacedPhoto`)
- Create: `ios/LifelineKit/Sources/LifelineKit/Store/PhotoRepository.swift` (the repository and the record conformances, as `EntityRepository.swift` keeps its records)
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/ExtractionStore.swift` (a `photos` member, last in both inits), `ios/LifelineKit/Tests/LifelineKitTests/ExtractionQueueTests.swift:11` (the one memberwise caller)
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/MemoryRepository.swift` (`fold(_:into:in:)`, before the source row is deleted)
- Test: `ios/LifelineKit/Tests/LifelineKitTests/MigrationsTests.swift`, create `ios/LifelineKit/Tests/LifelineKitTests/PhotoRepositoryTests.swift`

**Interfaces:**
- Consumes: `TypedID`, `CivilDate`, `EntityType`, `EntityID`, `MemoryID`, `StoreFixtures`, the `StatementCounter` pattern in `EntityBatchReadsTests.swift`.
- Produces:

```swift
public struct PhotoID: TypedID { public let rawValue: String; public init(rawValue: String) }
public enum PhotoOrigin: String, Codable, Sendable { case exif }
/// A camera's date and time with no time zone.
public struct PhotoTakenAt: Sendable, Hashable {
    public let date: CivilDate; public let hour: Int; public let minute: Int; public let second: Int
    public init?(exif: String)      // "2012:06:14 15:32:10"; nil for "0000:00:00 00:00:00" or any other form
    public init?(stored: String)    // "2012-06-14T15:32:10"
    public var stored: String { get }
}
public struct Photo: Sendable, Equatable, Identifiable {
    public var id: PhotoID; public var fileName: String; public var assetLocalID: String?
    public var takenAt: PhotoTakenAt?; public var takenOrigin: PhotoOrigin?
    public var lat: Double?; public var lon: Double?; public var locationOrigin: PhotoOrigin?
    public var sha256: String; public var pixelWidth: Int; public var pixelHeight: Int; public var addedAt: Date
}
public enum PhotoSubject: Sendable, Hashable { case entity(EntityID), memory(MemoryID) }
public enum PhotoRole: String, Codable, Sendable { case cover, attached }
public struct PlacedPhoto: Sendable, Equatable, Identifiable {
    public var photo: Photo; public var role: PhotoRole
    public var id: PhotoID { get }; public var isCover: Bool { get }
}

public struct PhotoRepository: Sendable {
    public init(_ db: AppDatabase)
    public func photo(id: PhotoID) throws -> Photo?
    public func photo(sha256: String) throws -> Photo?
    /// One transaction: the row, then its link. The first photo on a subject is its cover (decision 8).
    public func insert(_ photo: Photo, linkingTo subject: PhotoSubject) throws
    /// Links an existing photo. Already linked: nothing changes. The first photo on a subject is its cover.
    public func link(_ photo: PhotoID, to subject: PhotoSubject) throws
    /// Cover first, then by `sort_order` (the order added).
    public func photos(of subject: PhotoSubject) throws -> [PlacedPhoto]
    /// One statement: the cover of every entity of a type that is not hidden.
    public func covers(type: EntityType) throws -> [EntityID: Photo]
    public func setCover(_ photo: PhotoID, of subject: PhotoSubject) throws
    /// One transaction. Removes the link; a removed cover passes to the oldest-added photo left. Returns
    /// the photo when no link is left and its row was deleted, so the caller deletes the file.
    public func unlink(_ photo: PhotoID, from subject: PhotoSubject) throws -> Photo?
    /// Deletes every photo row with no link; returns them.
    public func deleteUnlinked() throws -> [Photo]
    public func fileNames() throws -> Set<String>
}
```

- `ExtractionStore.photos: PhotoRepository`.
- v13, exactly:
  - `photo`: `id` text primary key; `file_name` text not null unique; `asset_local_id` text; `taken_at` text; `taken_origin` text; `lat` double; `lon` double; `location_origin` text; `sha256` text not null unique; `pixel_width` integer not null; `pixel_height` integer not null; `added_at` datetime not null.
  - `photo_link`: `photo_id` text not null references `photo` on delete cascade; `entity_id` text references `entity` on delete cascade; `memory_id` text references `memory` on delete cascade; `role` text not null; `sort_order` integer not null; check `(entity_id is null) <> (memory_id is null)`.
  - Unique indexes: `(photo_id, entity_id) where entity_id is not null`; `(photo_id, memory_id) where memory_id is not null`; `(entity_id) where role = 'cover' and entity_id is not null`; `(memory_id) where role = 'cover' and memory_id is not null`. Plain indexes on `photo_link.entity_id` and `photo_link.memory_id`.

- [ ] **Step 1: Write the failing tests**

```swift
// MigrationsTests
@Test func schemaVersionsOrderByMigrationPosition() {
    #expect(Migrations.currentSchemaVersion == "v13")   // was "v12"; the other three expectations stay as they are
}
@Test func v13OnAPopulatedV12Database() throws {
    // foreign keys on; migrate upTo "v12"; insert by SQL: session s1, segment g1, entity e1 (person "Maya"),
    // memory m1, moment_entity (m1, e1, 'mention'); read every row of those five tables as [Row] before.
    try Migrations.migrator.migrate(queue)
    #expect(rowsAfter == rowsBefore, "no existing row or column changes")
    #expect(Set(try queue.read { try $0.columns(in: "photo") }.map(\.name)) == ["id", "file_name", "asset_local_id", "taken_at", "taken_origin", "lat", "lon", "location_origin", "sha256", "pixel_width", "pixel_height", "added_at"])
    // insert photo p1 and photo_link (p1, entity e1, cover, 0): works
    #expect(throws: DatabaseError.self, "a link names one subject") { /* insert a link with entity_id and memory_id both set */ }
    #expect(throws: DatabaseError.self, "a link names a subject") { /* both null */ }
    #expect(throws: DatabaseError.self, "one cover per subject") { /* p2's row in its own write first, then its link to e1 as cover */ }
    try queue.write { try $0.execute(sql: "delete from entity where id = 'e1'") }
    #expect(try queue.read { try Int.fetchOne($0, sql: "select count(*) from photo_link") } == 0, "the link goes with its entity")
    #expect(try queue.read { try Int.fetchOne($0, sql: "select count(*) from photo") } == 2, "the photo row waits for the sweep")
}

// PhotoRepositoryTests — ExtractionStore(try AppDatabase.inMemory()), invented people Maya and Dad, memory "The tree house".
@Test func takenAtReadsTheCameraFormOnly() {
    #expect(PhotoTakenAt(exif: "2012:06:14 15:32:10")?.stored == "2012-06-14T15:32:10")
    #expect(PhotoTakenAt(exif: "0000:00:00 00:00:00") == nil)
    #expect(PhotoTakenAt(exif: "2012-06-14") == nil)
    #expect(PhotoTakenAt(stored: "2012-06-14T15:32:10")?.date == CivilDate(year: 2012, month: 6, day: 14))
}
@Test func theFirstPhotoIsTheCoverAndTheRestFollowInOrder() throws {
    try photos.insert(a, linkingTo: .entity(maya.id)); try photos.insert(b, linkingTo: .entity(maya.id)); try photos.insert(c, linkingTo: .entity(maya.id))
    #expect(try photos.photos(of: .entity(maya.id)).map(\.id) == [a.id, b.id, c.id])
    #expect(try photos.photos(of: .entity(maya.id)).map(\.isCover) == [true, false, false])
    try photos.setCover(c.id, of: .entity(maya.id))
    #expect(try photos.photos(of: .entity(maya.id)).map(\.id) == [c.id, a.id, b.id])
}
@Test func aRowRoundTripsEveryColumn() throws {
    // a: takenAt 2012-06-14T15:32:10, takenOrigin .exif, lat 0.5, lon -30.0, locationOrigin .exif, assetLocalID "invented/L0/001",
    // addedAt a whole second (the datetime column keeps milliseconds only)
    try photos.insert(a, linkingTo: .memory(treeHouse.id))
    #expect(try photos.photo(id: a.id) == a)
    #expect(try photos.photo(sha256: a.sha256) == a)
}
@Test func linkingTwiceChangesNothing() throws {
    try photos.insert(a, linkingTo: .entity(maya.id)); try photos.link(a.id, to: .entity(dad.id)); try photos.link(a.id, to: .entity(maya.id))
    #expect(try photos.photos(of: .entity(maya.id)).count == 1)
    #expect(try photos.photos(of: .entity(dad.id)).map(\.isCover) == [true])
}
@Test func removingTheCoverPassesItToTheOldestLeft() throws {
    // a (cover), b, c on Maya
    #expect(try photos.unlink(a.id, from: .entity(maya.id)) == a, "no page left: the row goes")
    #expect(try photos.photos(of: .entity(maya.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" } == ["\(b.id.rawValue) cover", "\(c.id.rawValue) attached"])
    _ = try photos.unlink(b.id, from: .entity(maya.id)); _ = try photos.unlink(c.id, from: .entity(maya.id))
    #expect(try photos.photos(of: .entity(maya.id)).isEmpty)
    #expect(try photos.covers(type: .person)[maya.id] == nil)
}
@Test func unlinkingFromOnePageKeepsTheOther() throws {
    try photos.insert(a, linkingTo: .entity(maya.id)); try photos.link(a.id, to: .entity(dad.id))
    #expect(try photos.unlink(a.id, from: .entity(maya.id)) == nil)
    #expect(try photos.photo(id: a.id) == a)
}
@Test func deletingASubjectRemovesItsLinks() throws {
    try photos.insert(a, linkingTo: .entity(maya.id)); try photos.insert(b, linkingTo: .memory(treeHouse.id))
    try store.entities.delete(maya.id); try store.memories.delete(treeHouse.id)
    #expect(try photos.deleteUnlinked().map(\.id).sorted { $0.rawValue < $1.rawValue } == [a.id, b.id].sorted { $0.rawValue < $1.rawValue })
    #expect(try photos.fileNames().isEmpty)
}
@Test func foldingAMemoryMovesItsPhotos() throws {
    // target t has cover x; source s has cover y and attached z; s and t are both told memories
    try store.memories.fold(s, into: t)
    #expect(try photos.photos(of: .memory(t.id)).map { "\($0.id.rawValue) \($0.role.rawValue)" } == ["\(x.id.rawValue) cover", "\(y.id.rawValue) attached", "\(z.id.rawValue) attached"])
    #expect(try photos.deleteUnlinked().isEmpty, "nothing is orphaned by a merge")
}
@Test func coversReadEveryPersonAtOnce() throws {
    // Same counter as `summariesReadInAFixedNumberOfStatements`: covers for 3 people with photos, add 30 more with photos, read again.
    #expect(statementsForMany == statementsForFew)
    #expect(try photos.covers(type: .person)[maya.id] == a)
    #expect(try photos.covers(type: .place).isEmpty)
}
@Test func aHiddenPersonHasNoCoverInTheGrid() throws {
    try store.entities.setHidden(maya.id, true)
    #expect(try photos.covers(type: .person)[maya.id] == nil)
}
```

- [ ] **Step 2: Run `cd ios/LifelineKit && swift test --filter "Migrations|PhotoRepository"`.** Expected: FAIL; `Photo` does not exist and the schema is v12.
- [ ] **Step 3: Add the domain types, migration v13, `PhotoRepository` and `ExtractionStore.photos`.** Partial indexes go through `db.execute(sql: "create unique index … where …")`. `covers(type:)` is one join of `photo_link`, `photo` and `entity` with `role = 'cover'`, `entity.type = ?` and `entity.hidden_from_timeline = 0`. A new link's `sort_order` is one more than the subject's largest. In `fold`, before the source row goes: move the source's links that the target does not already have to the target, as `attached` when the target has a cover, with `sort_order` after the target's.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, the whole kit suite.
- [ ] **Step 5: Commit** — `Store: photos and their links, one cover per subject (v13)` (body: why `photo_link` has a key per subject kind, decision 2)

### Task 2: Kit — the photo library: import, remove, sweep

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Store/PhotoLocation.swift`
- Create: `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoImport.swift` (pure ImageIO and CryptoKit functions)
- Create: `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoLibrary.swift` (the actor)
- Create: `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoCaption.swift`
- Create: `ios/LifelineKit/Sources/LifelineKit/Photos/GeneratedPhoto.swift` (writes invented test images; used by kit tests, the UI seed and the fixture writer, as `ScriptedExtractionService` ships in the kit)
- Test: create `ios/LifelineKit/Tests/LifelineKitTests/PhotoLibraryTests.swift`, `PhotoCaptionTests.swift`

**Interfaces:**
- Consumes: Task 1 `PhotoRepository`, `Photo`, `PhotoSubject`, `PhotoTakenAt`; `AudioLocation.rootDirectory(under:)`, `AudioLocation.applyBackupExclusion(to:)`.
- Produces:

```swift
public enum PhotoLocation {
    /// `<root>/Lifeline/photos`, created and excluded from backup.
    public static func directory(under root: URL) throws -> URL
    public static let directoryName = "photos"
}
public enum PhotoImport {
    public enum Error: Swift.Error, LocalizedError, Equatable { case unreadable }   // "Lifeline cannot read this file as a photo."
    public struct Metadata: Sendable, Equatable { public var takenAt: PhotoTakenAt?; public var lat: Double?; public var lon: Double? }
    public static let maxPixel = 2048
    public static func metadata(of source: URL) throws -> Metadata
    /// Decision 3 and 4. Returns the stored pixel size.
    public static func writeDownscaled(from source: URL, to destination: URL, maxPixel: Int = maxPixel) throws -> (width: Int, height: Int)
    /// Lower-case hex; reads the file in 1 MB chunks.
    public static func sha256(of file: URL) throws -> String
    /// For display: the stored copy downsampled so its longest edge is at most `maxPixel`.
    public static func thumbnail(at file: URL, maxPixel: Int) throws -> CGImage
}
public actor PhotoLibrary {
    public init(root: URL, photos: PhotoRepository)
    /// Same photo already stored (decision 7): links it. Otherwise: writes `.<id>.partial`, renames it to `<id>.jpg`, then inserts the row and link.
    public func add(fileAt source: URL, assetLocalID: String?, to subject: PhotoSubject, now: Date = .now) throws -> Photo
    /// Unlinks; when no page is left, deletes the row, then the file.
    public func remove(_ photo: PhotoID, from subject: PhotoSubject) throws
    public func setCover(_ photo: PhotoID, of subject: PhotoSubject) throws
    public nonisolated func url(for photo: Photo) -> URL
    public struct Swept: Sendable, Equatable { public var rows: Int; public var files: Int; public init(rows: Int, files: Int) }
    /// Decision 10: unlinked rows and their files; files with no row; `.partial` files. Never a row whose file is missing.
    @discardableResult public static func sweep(root: URL, photos: PhotoRepository) throws -> Swept
}
public enum PhotoCaption {
    public static func taken(_ takenAt: PhotoTakenAt?) -> String?      // "taken 14 June 2012"
    public static func label(title: String, isOwner: Bool, isMemory: Bool) -> String
}
public enum GeneratedPhoto {
    /// A solid `rgb` rectangle with a white circle in its lower right quarter, written as JPEG (or PNG when `alpha`),
    /// with `DateTimeOriginal`, GPS and the EXIF orientation when given.
    public static func write(to url: URL, width: Int, height: Int, rgb: Int, takenAt: String? = nil,
                             gps: (lat: Double, lon: Double)? = nil, orientation: Int = 1, alpha: Bool = false) throws
}
```

- [ ] **Step 1: Write the failing tests**

Each test uses a fresh root in the temporary folder, `AppDatabase.open(at: root/Lifeline/lifeline.sqlite)`, and `GeneratedPhoto` sources. Invented values only.

```swift
@Test func addStoresADownscaledCopyWithNoMetadata() async throws {
    // source: 3000×2000, rgb 0xE07A2E, takenAt "2012:06:14 15:32:10", gps (0.5, -30.0), orientation 6 (rotated)
    let photo = try await library.add(fileAt: source, assetLocalID: "invented/L0/001", to: .entity(maya.id))
    let stored = library.url(for: photo)
    #expect(stored.lastPathComponent == "\(photo.id.rawValue).jpg")
    #expect(max(photo.pixelWidth, photo.pixelHeight) == 2048 && photo.pixelWidth < photo.pixelHeight, "the rotation is in the pixels")
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(stored as CFURL, nil)!, 0, nil) as? [CFString: Any])
    #expect(props[kCGImagePropertyGPSDictionary] == nil, "no GPS in the stored file")
    #expect((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
    #expect((props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    #expect(props[kCGImagePropertyHasAlpha] as? Bool != true)
    #expect(photo.takenAt?.stored == "2012-06-14T15:32:10" && photo.takenOrigin == .exif)
    #expect(photo.lat == 0.5 && photo.lon == -30.0 && photo.locationOrigin == .exif)
    #expect(photo.assetLocalID == "invented/L0/001" && photo.sha256.count == 64)
    #expect(try store.photos.photos(of: .entity(maya.id)).map(\.isCover) == [true])
}
@Test func aPhotoLocationIsNeverAPlace() async throws {
    let places = try store.entities.entities(type: .place).count, memories = try store.memories.allMemories()
    _ = try await library.add(fileAt: sourceWithGPS, assetLocalID: nil, to: .memory(treeHouse.id))
    #expect(try store.entities.entities(type: .place).count == places)
    #expect(try store.memories.allMemories() == memories, "no memory's range or place changes")
}
@Test func aPhotoWithoutMetadataStoresNone() async throws {
    let photo = try await library.add(fileAt: plain, assetLocalID: nil, to: .entity(maya.id))
    #expect(photo.takenAt == nil && photo.takenOrigin == nil && photo.lat == nil && photo.locationOrigin == nil)
}
@Test func aSmallPhotoIsNotEnlarged() async throws { /* 800×600 */ #expect((photo.pixelWidth, photo.pixelHeight) == (800, 600)) }
@Test func aHugeImageIsStoredAtMost2048Pixels() async throws { /* 12 000×1 500 */ #expect(photo.pixelWidth == 2048 && photo.pixelHeight == 256) }
@Test func aTransparentImageIsStoredOnWhite() async throws { /* alpha: true PNG */ #expect(props[kCGImagePropertyHasAlpha] as? Bool != true) }
@Test func aFileThatIsNotAPhotoStoresNothing() async throws {
    try Data("this is not a photo".utf8).write(to: bogus)
    await #expect(throws: PhotoImport.Error.unreadable) { try await library.add(fileAt: bogus, assetLocalID: nil, to: .entity(maya.id)) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: photosDir.path).isEmpty)
    #expect(try store.photos.photos(of: .entity(maya.id)).isEmpty)
    #expect(PhotoImport.Error.unreadable.localizedDescription == "Lifeline cannot read this file as a photo.")
}
@Test func aWriteThatFailsStoresNothing() async throws {
    // photos directory set to 0o500 (a full disk as the test can make one); restored to 0o700 in a defer
    await #expect(throws: (any Error).self) { try await library.add(fileAt: source, assetLocalID: nil, to: .entity(maya.id)) }
    #expect(try store.photos.photos(of: .entity(maya.id)).isEmpty)
    #expect(try store.photos.fileNames().isEmpty)
}
@Test func theSamePhotoTwiceKeepsOneCopy() async throws {
    let first = try await library.add(fileAt: source, assetLocalID: nil, to: .entity(maya.id))
    let second = try await library.add(fileAt: source, assetLocalID: nil, to: .entity(dad.id))
    _ = try await library.add(fileAt: source, assetLocalID: nil, to: .entity(maya.id))
    #expect(second.id == first.id)
    #expect(try FileManager.default.contentsOfDirectory(atPath: photosDir.path) == ["\(first.id.rawValue).jpg"])
    #expect(try store.photos.photos(of: .entity(maya.id)).count == 1)
}
@Test func removeDeletesTheFileWhenNoPageIsLeft() async throws {
    // first is on Maya and Dad
    try await library.remove(first.id, from: .entity(maya.id))
    #expect(FileManager.default.fileExists(atPath: library.url(for: first).path))
    try await library.remove(first.id, from: .entity(dad.id))
    #expect(!FileManager.default.fileExists(atPath: library.url(for: first).path))
    #expect(try store.photos.photo(id: first.id) == nil)
}
@Test func aFileWithNoRowGoesAtTheSweep() throws {
    try Data([1, 2, 3]).write(to: photosDir.appending(path: "\(PhotoID().rawValue).jpg"))   // a kill after the file, before the row
    #expect(try PhotoLibrary.sweep(root: root, photos: store.photos) == .init(rows: 0, files: 1))
    #expect(try FileManager.default.contentsOfDirectory(atPath: photosDir.path).isEmpty)
}
@Test func aPartialFileGoesAtTheSweep() throws {
    try Data([1]).write(to: photosDir.appending(path: ".\(PhotoID().rawValue).partial"))
    #expect(try PhotoLibrary.sweep(root: root, photos: store.photos).files == 1)
}
@Test func aPhotoWithNoPageGoesAtTheSweep() async throws {
    let photo = try await library.add(fileAt: source, assetLocalID: nil, to: .entity(maya.id))
    try store.entities.delete(maya.id)
    #expect(try PhotoLibrary.sweep(root: root, photos: store.photos) == .init(rows: 1, files: 1))
    #expect(!FileManager.default.fileExists(atPath: library.url(for: photo).path))
}
@Test func deletingASessionLeavesNoPhotoFileAfterTheSweep() async throws {
    // treeHouse is told only in session s1
    _ = try await library.add(fileAt: source, assetLocalID: nil, to: .memory(treeHouse.id))
    try store.sessions.deleteSession(s1)
    try PhotoLibrary.sweep(root: root, photos: store.photos)
    #expect(try FileManager.default.contentsOfDirectory(atPath: photosDir.path).isEmpty)
}
@Test func aRowWithAMissingFileStays() async throws {
    let photo = try await library.add(fileAt: source, assetLocalID: nil, to: .entity(maya.id))
    try FileManager.default.removeItem(at: library.url(for: photo))
    #expect(try PhotoLibrary.sweep(root: root, photos: store.photos) == .init(rows: 0, files: 0))
    #expect(try store.photos.photo(id: photo.id) != nil)
}
@Test func photosStayOutOfCloudBackup() throws {
    #expect(try PhotoLocation.directory(under: root).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
}
@Test func thumbnailsAreDownsampled() async throws {
    let image = try PhotoImport.thumbnail(at: library.url(for: photo), maxPixel: 400)
    #expect(max(image.width, image.height) == 400)
}
// PhotoCaptionTests
@Test func theCaptionSaysOnlyTheDate() {
    #expect(PhotoCaption.taken(PhotoTakenAt(stored: "2012-06-14T15:32:10")) == "taken 14 June 2012")
    #expect(PhotoCaption.taken(nil) == nil)
}
@Test func theLabelSaysWhereThePersonPutIt() {
    #expect(PhotoCaption.label(title: "Maya", isOwner: false, isMemory: false) == "Photo of Maya")
    #expect(PhotoCaption.label(title: "Jordan", isOwner: true, isMemory: false) == "Photo of you")
    #expect(PhotoCaption.label(title: "The tree house", isOwner: false, isMemory: true) == "Photo for The tree house")
}
```

- [ ] **Step 2: Run `swift test --filter "PhotoLibrary|PhotoCaption"`.** Expected: FAIL; `PhotoLibrary` does not exist.
- [ ] **Step 3: Implement the five files.** `writeDownscaled`: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform` and `kCGImageSourceThumbnailMaxPixelSize = min(maxPixel, longest edge)`, drawn into an opaque 8-bit Display P3 `CGContext` filled white, written with `CGImageDestination` (`UTType.jpeg`, `kCGImageDestinationLossyCompressionQuality: 0.85`) and no properties dictionary. `metadata` reads `kCGImagePropertyExifDateTimeOriginal` and the GPS latitude, longitude and their refs (south and west are negative; out of range is nil). `add` hashes the source first; it does all its work in one actor call, with no suspension point between the file and the row. `PhotoCaption.taken` uses a Gregorian calendar, `Locale(identifier: "en_GB")` and `dateFormat` "d MMMM yyyy" on the civil date.
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** — `Kit: a downscaled copy with no metadata; remove and sweep leave no orphans`

### Task 3: Kit — photos in the backup

**Files:**
- Modify: `ios/LifelineKit/Sources/LifelineKit/Store/Backup.swift` (`BackupManifest`, `export(appDirectory:…)`, `applyPendingRestore`)
- Modify: `ios/LifelineKit/Tests/LifelineKitTests/BackupTests.swift` (the `Root` fixture gets `photos: Int = 0`: with photos, it makes the person "Maya" and adds that many `GeneratedPhoto` images to her through `PhotoLibrary`; helpers `photoFileNames() -> [String]` (sorted), `photoBytes() -> Int64`, `photoData() -> [String: Data]`; new tests)

**Interfaces:**
- Consumes: Task 2 `PhotoLocation.directoryName`, `PhotoLocation.directory(under:)`, `PhotoLibrary`, `GeneratedPhoto`.
- Produces:
  - `BackupManifest.photoFiles: Int?` and `BackupManifest.photoBytes: Int64?`. `init` gains `photoFiles: Int? = nil, photoBytes: Int64? = nil` after `audioBytes`. Synthesized `Codable` omits them when nil and reads them as nil when absent.
  - `Backup.photosDirectory = "photos"`. Export adds every `*.jpg` in `<Lifeline>/photos/`, sorted, as `photos/<name>`, with `compressionMethod: .none`, and sets both fields (0 with none). `applyPendingRestore` creates `photos/` in the restored archive and marks it excluded, as it does `audio/`. Nothing else in stage, apply or preserve changes: the safety copy and the moved-aside copy go through `export`, so they carry photos.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func exportCarriesThePhotosAndCountsThem() throws {
    let source = try Root(sessions: 1, memories: 1, photos: 2)
    let manifest = try Backup.export(root: source.url, appVersion: "1.0", to: archive, database: source.db)
    #expect(manifest.photoFiles == 2 && manifest.photoBytes == source.photoBytes())
    #expect(try Backup.entryNames(of: archive).filter { $0.hasPrefix("photos/") }.sorted() == source.photoFileNames().map { "photos/\($0)" })
    #expect(try Backup.inspect(archive) == manifest)
}
@Test func aRestorePutsThePhotosBack() throws {
    // export source (2 photos on Maya), stage and apply on an empty target
    let restored = ExtractionStore(try AppDatabase.open(at: target.appending(path: "Lifeline/lifeline.sqlite")))
    #expect(try restored.photos.photos(of: .entity(maya)).count == 2)
    for (name, data) in try source.photoData() { #expect(try Data(contentsOf: targetPhotos.appending(path: name)) == data) }
    #expect(try targetPhotos.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    #expect(try PhotoLibrary.sweep(root: target, photos: restored.photos) == .init(rows: 0, files: 0), "the restore leaves nothing to sweep")
}
@Test func aManifestWithoutPhotoFieldsStillReads() throws {
    let old = try Backup.rewritingManifest(of: archive) { $0.photoFiles = nil; $0.photoBytes = nil }
    #expect(try Backup.inspect(old).photoFiles == nil)
    let m6 = #"{"appVersion":"0.9","audioBytes":10,"audioFiles":1,"createdAt":"2026-10-24T12:00:00Z","memories":1,"schemaVersion":"v8","sessions":1}"#
    // decode with the manifest decoder (ISO 8601 dates)
    #expect(decoded.photoFiles == nil && decoded.photoBytes == nil && decoded.sessions == 1)
}
@Test func aV12ArchiveRestoresAndMigrates() throws {
    // oldRoot: a database migrated upTo "v12" with one session and the entity "Maya", no photos folder;
    // its archive's manifest is rewritten to drop the photo fields, as a v12 build wrote it.
    #expect(try Backup.inspect(oldArchive).schemaVersion == "v12")
    // target: a phone with one photo on its own person
    _ = try Backup.stage(oldArchive, root: target.url, appVersion: "1.0", database: target.db, safetyCopyDirectory: documents)
    #expect(try Backup.applyPendingRestore(root: target.url, safetyCopyDirectory: documents))
    let opened = try AppDatabase.open(at: target.url.appending(path: "Lifeline/lifeline.sqlite"))
    #expect(try opened.writer.read { try $0.tableExists("photo") && $0.tableExists("photo_link") }, "migrated on open")
    #expect(try ExtractionStore(opened).photos.fileNames().isEmpty)
    #expect(try PhotoLocation.directory(under: target.url).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    #expect(try SessionRepository(opened).listSessions().count == 1)
}
@Test func theSafetyCopyKeepsThePhonesPhotos() throws {
    let phone = try Root(sessions: 1, memories: 1, photos: 1)
    let pending = try Backup.stage(otherArchive, root: phone.url, appVersion: "1.0", database: phone.db, safetyCopyDirectory: documents)
    #expect(try Backup.entryNames(of: pending.safetyCopy).contains("photos/\(phone.photoFileNames()[0])"))
    #expect(try Backup.inspect(pending.safetyCopy).photoFiles == 1)
}
@Test func theReplacedArchiveKeepsPhotosAddedAfterStaging() throws {
    // as applyKeepsWhatWasWrittenAfterStaging: stage, then add one photo on the phone, then apply
    let replaced = try archives(in: documents).first { $0.lastPathComponent.hasPrefix("Lifeline-replaced-") }!
    #expect(try Backup.entryNames(of: replaced).contains("photos/\(added.fileName)"))
}
```

- [ ] **Step 2: Run `swift test --filter Backup`.** Expected: FAIL; the manifest has no photo fields and `photos/` is not in the archive.
- [ ] **Step 3: Implement as the Interfaces block says.** The existing `BackupTests` stay as they are; `Root(sessions:memories:)` keeps its meaning with `photos: 0`.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, every existing backup test included.
- [ ] **Step 5: Commit** — `Backup: photos travel in the copy; older copies still restore` (body: the two manifest fields are optional; a v12 archive migrates on open)

### Task 4: App — photos on a page: add, header, row, viewer

**Files:**
- Create: `ios/Lifeline/Screens/Photos/PhotoShelf.swift`, `PhotoImageView.swift` (with `PhotoImageCache`), `PhotoHeader.swift`, `PhotoRow.swift`, `PhotoViewer.swift`, `AddPhotoFlow.swift`
- Create: `ios/Lifeline/Support/ErrorLine.swift` (moved from the private `ErrorLine` in `YouScreen.swift`, unchanged)
- Modify: `ios/Lifeline/Screens/You/YouScreen.swift` (uses the moved `ErrorLine`)
- Modify: `ios/Lifeline/Dependencies.swift` (`photos`, `photoImages`, `pickPhotoPath`, the launch sweep, the seed flag), `ios/Lifeline/UITestSeed.swift` (`writePhotos`)
- Modify: `ios/Lifeline/Screens/Entities/EntityScreen.swift`, `ios/Lifeline/Screens/Entities/EntityViewModel.swift`
- Modify: `ios/LifelineKit/Tests/LifelineKitTests/FixtureArchiveWriter.swift` (a second gated test, `writePhotoFixture`)
- Create: `ios/LifelineUITests/Fixtures/photo-orange.jpg` (written by the fixture writer), `ios/LifelineUITests/Fixtures/not-a-photo.jpg` (the text "this is not a photo")
- Modify: `ios/LifelineUITests/UITestHelpers.swift`
- Test: create `ios/LifelineUITests/PhotosUITests.swift`

**Interfaces:**
- Consumes: Task 2 `PhotoLibrary`, `PhotoImport.thumbnail`, `PhotoCaption`, `GeneratedPhoto`; Task 1 `PlacedPhoto`, `PhotoSubject`; `EntityViewModel`, `home.coverClosings`, `sectionHeadingStyle()`.
- Produces:
  - `Dependencies.photos: PhotoLibrary`, `Dependencies.photoImages: PhotoImageCache`, `var pickPhotoPath: String?` (`-uiTesting-pickPhoto <path>`). Both factories call `PhotoLibrary.sweep(root:photos:)` right after `AppDatabase.open`; a sweep error is logged and never stops launch.
  - `UITestSeed.writePhotos(store:profile:sessions:library:)` under `-uiTesting-seedPhotos`: calls `writePeople`, then adds generated photos through `PhotoLibrary`: Maya, first a 1600×1200 `0xC8893F` photo with `takenAt` "2012:06:14 15:32:10" and GPS (0.5, -30.0), then a 1200×1600 `0x5F7046` photo with no metadata; the memory "The tree house", a 1600×1200 `0xECE3D2` photo with `takenAt` "1999:07:04 10:00:00"; Jordan (the owner), a 1600×1200 `0x8F5A1C` photo. Dad, Sam and Lena get none.
  - `PhotoImageCache` (`actor`): `func image(for photo: Photo, size: PhotoImageSize) async -> UIImage?`; `enum PhotoImageSize: Int { case small = 400, large = 1600 }`. Decodes with `PhotoImport.thumbnail` off the main actor; `NSCache` keyed by file name and size. Nil when the file cannot be read.
  - `PhotoImageView(photo: Photo, size: PhotoImageSize, cache: PhotoImageCache, placeholder: () -> some View)`: loads in `.task(id: photo.fileName)`, shows the placeholder until the image is there and when it fails; fills and clips.
  - `PhotoShelf` (`@MainActor @Observable final class`): `init(subject: PhotoSubject, deps: Dependencies, onError: @escaping (String) -> Void)` does no reads. `private(set) var photos: [PlacedPhoto]`, `var cover: Photo? { get }`, `private(set) var isAdding = false`. `func load()` (one `photos(of:)`; a failure goes to `onError`). `func add(fileAt: URL, assetLocalID: String?) async`, `func makeCover(_ photo: PhotoID) async`, `func remove(_ photo: PhotoID) async`: each calls `deps.photos`, then `load()`, and sends "Could not add this photo: …", "Could not make this the cover: …" or "Could not remove this photo: …" to `onError`.
  - `AddPhotoFlow` view modifier, `.addPhotoFlow(isPresented: Binding<Bool>, deps: Dependencies, onFile: @escaping (URL, String?) async -> Void, onError: @escaping (String) -> Void)`: under `deps.pickPhotoPath` it calls `onFile` with that path at once and shows no picker; otherwise `.photosPicker` as decision 18, then `loadTransferable(type: PickedPhotoFile.self)`, where `PickedPhotoFile: Transferable` copies the received file into the temporary folder; the copy is removed after `onFile` returns. A load failure goes to `onError` as "Could not add this photo: …".
  - `PhotoHeader(cover: Photo, label: String, cache:, onOpen:)`: a `Button` with the image (4:3, radius 22, `.large`), identifier `photo.header`, accessibility label `label`, value `PhotoCaption.taken(…) ?? ""`, trait `.isImage`. Under it, the caption (footnote, `Theme.secondaryText`, identifier `photo.caption`) when the date is known.
  - `PhotoRow(photos: [PlacedPhoto], label: String, cache:, onOpen:)`: heading "Photos" with `sectionHeadingStyle()`, then a horizontal `ScrollView` of 88-point square buttons (radius 14, `.small`), identifier `photo.thumb`, the same label and value as the header.
  - `PhotoViewer(photo: PlacedPhoto, label: String, canMakeCover: Bool, cache:, onMakeCover:, onRemove:)`, shown as a `.sheet(item:)` with identifier `photo.viewer`: the image fitted, the caption, then "Make this the cover" (`photo.makeCover`, only when `canMakeCover`), "Remove photo…" (`photo.remove`, `role: .destructive`) and "Done" (`photo.done`, toolbar). Buttons are `.bordered`, `.tint(Theme.oliveOnFill)`, `.frame(minHeight: 44)` inside the label. "Remove photo…" shows the Global Constraints dialog; its button is `photo.confirmRemove`. Each action dismisses the sheet.
  - On `EntityViewModel`: `let shelf: PhotoShelf` (subject `.entity(entity.id)`, `onError` sets `photoError`), `private(set) var photoError: String?`, `var photoLabel: String` (`PhotoCaption.label(title:isOwner:isMemory: false)`). `refresh()` also calls `shelf.load()`.
  - `EntityScreen` (not for an idea, which keeps its layout): `PhotoHeader` first in the header section when `shelf.cover` is set, above the type caption and the title; while `shelf.isAdding`, a row "Adding the photo…" with a `ProgressView` (identifier `photo.adding`) in the same place. `PhotoRow` as its own section after "Often with" and before the moments when `shelf.photos.count >= 2`. "Add a photo" (`systemImage: "photo"`, identifier `entity.addPhoto`) is the first item in the `entity.more` menu. `photoError` shows in a `.safeAreaInset(edge: .bottom)` slot as `ErrorLine` (identifier `photo.error`), posted as an announcement when it is set, cleared on disappear and when the next photo action starts.
  - In `UITestHelpers.swift`: `static func launchWithPhotos(_ extra: [String] = []) -> XCUIApplication` (`-uiTesting -uiTesting-seedPhotos`, then skip first open as `launchWithPeople`), `static func fixturePath(_ name: String, ext: String) throws -> String` (copies a bundle fixture to the temporary folder, as `SteadyUITests.fixtureArchive` does), `func addPhotoFromMenu(_ menu: String, _ item: String)`.

- [ ] **Step 1: Write the fixtures and the seed; commit them alone.** Add to `FixtureArchiveWriter.swift` a second test, `writePhotoFixture`, gated on `LIFELINE_WRITE_FIXTURES` like the first: `GeneratedPhoto.write(to: out/photo-orange.jpg, width: 3000, height: 2000, rgb: 0xE07A2E, takenAt: "2012:06:14 15:32:10", gps: (0.5, -30.0), orientation: 6)`. Run it once with `cd ios/LifelineKit && LIFELINE_WRITE_FIXTURES=../LifelineUITests/Fixtures swift test --filter writePhotoFixture`. The archive fixtures must not change; `git status` shows only the new image. Write `not-a-photo.jpg` by hand. Add `Dependencies.photos` and the `-uiTesting-seedPhotos` line, and `UITestSeed.writePhotos`.

```bash
git add ios/LifelineKit/Tests/LifelineKitTests/FixtureArchiveWriter.swift ios/LifelineUITests/Fixtures/photo-orange.jpg ios/LifelineUITests/Fixtures/not-a-photo.jpg ios/Lifeline/UITestSeed.swift ios/Lifeline/Dependencies.swift
git commit -m "UI tests: generated photos to seed and to pick"
```

- [ ] **Step 2: Add the helpers, then write the failing UI tests**

```swift
final class PhotosUITests: XCTestCase {
    @MainActor
    func testAddingAPhotoMakesItThePagesCover() throws {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")])
        app.openEntityPage("Lena")
        XCTAssertFalse(app.buttons["photo.header"].exists, "no photo, no frame")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        let header = app.buttons["photo.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.label, "Photo of Lena")
        XCTAssertEqual(header.value as? String, "taken 14 June 2012")
        XCTAssertEqual(app.staticTexts["photo.caption"].label, "taken 14 June 2012")
        XCTAssertLessThan(header.frame.maxY, app.staticTexts["entity.title"].frame.minY, "the title sits under the photo, not on it")
        XCTAssertGreaterThan(header.frame.height, header.frame.width, "the rotated photo is stored upright and framed 3:4")
        XCTAssertFalse(app.staticTexts["Photos"].exists, "one photo is the header, not a row")
    }
    @MainActor
    func testAPageWithoutAPhotoHasNoFrame() {
        let app = XCUIApplication.launchWithPhotos(); app.openEntityPage("Sam")
        XCTAssertFalse(app.buttons["photo.header"].exists)
        XCTAssertFalse(app.staticTexts["Photos"].exists)
        XCTAssertFalse(app.buttons.matching(identifier: "photo.thumb").firstMatch.exists)
    }
    @MainActor
    func testSeveralPhotosShowInARow() {
        let app = XCUIApplication.launchWithPhotos(); app.openEntityPage("Maya")
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "taken 14 June 2012")
        let thumbs = app.buttons.matching(identifier: "photo.thumb")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        XCTAssertEqual(thumbs.count, 2)
        XCTAssertEqual(thumbs.allElementsBoundByIndex.map(\.label), ["Photo of Maya", "Photo of Maya"])
        XCTAssertEqual(thumbs.allElementsBoundByIndex.map { $0.value as? String ?? "" }, ["taken 14 June 2012", ""], "cover first")
        XCTAssertLessThan(app.buttons["entity.oftenWith"].firstMatch.frame.minY, app.staticTexts["Photos"].frame.minY)
        XCTAssertLessThan(app.staticTexts["Photos"].frame.minY, app.buttons["entity.moment"].firstMatch.frame.minY)
    }
    @MainActor
    func testMakeThisTheCoverChangesTheHeader() {
        let app = XCUIApplication.launchWithPhotos(); app.openEntityPage("Maya")
        XCTAssertTrue(app.reveal(app.staticTexts["Photos"]))
        app.buttons.matching(identifier: "photo.thumb").element(boundBy: 1).tap()
        XCTAssertTrue(app.any("photo.viewer").waitForExistence(timeout: 5))
        app.buttons["photo.makeCover"].tap()
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "")
        XCTAssertFalse(app.staticTexts["photo.caption"].exists, "no date, no caption")
    }
    @MainActor
    func testRemovingTheCoverAsksFirstAndPassesTheCoverOn() {
        let app = XCUIApplication.launchWithPhotos(); app.openEntityPage("Maya")
        app.buttons["photo.header"].tap()
        XCTAssertFalse(app.buttons["photo.makeCover"].exists, "it is already the cover")
        app.buttons["photo.remove"].tap()
        let confirm = app.buttons["photo.confirmRemove"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "Remove photo")
        XCTAssertTrue(app.staticTexts["It leaves this page. The original stays in your photo library."].exists)
        confirm.tap()
        XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["photo.header"].value as? String, "", "the other photo is the cover now")
        XCTAssertFalse(app.staticTexts["Photos"].exists, "one photo left: no row")
    }
    @MainActor
    func testAnUnreadablePhotoSaysSoAndAddsNothing() throws {
        let app = XCUIApplication.launchWithPeople(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("not-a-photo", ext: "jpg")])
        app.openEntityPage("Lena")
        app.addPhotoFromMenu("entity.more", "entity.addPhoto")
        let error = app.any("photo.error")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "Could not add this photo: Lifeline cannot read this file as a photo.")
        XCTAssertFalse(app.buttons["photo.header"].exists)
        XCTAssertTrue(app.staticTexts["entity.title"].isHittable, "the page stays as it was")
    }
    @MainActor
    func testTheViewerControlsAreFullSizeAtTheLargestText() {
        let app = XCUIApplication.launchWithPhotos(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.openEntityPage("Maya"); app.buttons["photo.header"].tap()
        for id in ["photo.remove", "photo.done"] { XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44) }
        XCTAssertTrue(app.staticTexts["photo.caption"].frame.height > 0, "the caption reads in full")
    }
}
```

- [ ] **Step 3: Run `-only-testing:LifelineUITests/PhotosUITests`.** Expected: FAIL; `entity.addPhoto` does not exist.
- [ ] **Step 4: Build the shelf, the views, the flow and the page as the Interfaces block says.** Run `xcodegen generate` after adding files. The header frame is 4:3 for a landscape cover and 3:4 for a portrait one (from `pixelWidth` and `pixelHeight`), so a portrait photo is not cut to a strip; the assertion on the rotated fixture checks this. Images fill their frame with `.scaledToFill()` and `.clipped()` inside the rounded shape.
- [ ] **Step 5: Run `swift test`, then `-only-testing:LifelineUITests/PhotosUITests -only-testing:LifelineUITests/EntityPageUITests -only-testing:LifelineUITests/EntitiesUITests -only-testing:LifelineUITests/ShellUITests -only-testing:LifelineUITests/YouUITests`.** Expected: PASS.
- [ ] **Step 6: Commit** — `Pages: add a photo from the menu; the cover heads the page, more photos sit in a row`

### Task 5: App — the People grid shows covers

**Files:**
- Modify: `ios/Lifeline/Screens/Entities/PersonTile.swift` (`TileFace`, `PersonTile`, `PersonRow`), `ios/Lifeline/Screens/Entities/EntitiesViewModel.swift`, `ios/Lifeline/Screens/Entities/PeopleGridScreen.swift`
- Modify: `ios/LifelineUITests/UITestHelpers.swift` (`colour(of:at:)`, `isNear(_:_:)`)
- Test: `ios/LifelineUITests/PeopleUITests.swift`

**Interfaces:**
- Consumes: Task 1 `PhotoRepository.covers(type:)`; Task 4 `PhotoImageView`, `PhotoImageCache`, `UITestHelpers.launchWithPhotos`, `fixturePath`, `addPhotoFromMenu`.
- Produces:
  - `EntitiesViewModel.covers: [EntityID: Photo]`, read with `covers(type:)` in the same `refresh()` as `rows` (one more statement, whatever the number of people). Read only for `.person`.
  - `TileFace(summary: EntitySummary, cover: Photo?, cache: PhotoImageCache, letterFont: Font = …)`: the same `RoundedRectangle(cornerRadius: 22)` frame and `aspectRatio(1)`. With a cover, `PhotoImageView(photo:size: .small)` fills it, with the monogram as its placeholder; without one, the monogram as today. Still `accessibilityHidden(true)`.
  - `PersonTile` and `PersonRow` take `cover: Photo?` and pass `deps.photoImages`. Their accessibility label and value do not change.
  - `XCUIApplication.colour(of:at:)` returns the 0xRRGGBB of the pixel at a unit point of the element's screenshot. `func isNear(_ a: Int, _ b: Int) -> Bool` allows 24 per channel (the copy is JPEG in Display P3).

- [ ] **Step 1: Write the failing UI tests**

```swift
@MainActor
func testATileShowsItsCover() {
    let app = XCUIApplication.launchWithPhotos(); app.openTab("People")
    let maya = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "Maya")).firstMatch
    let dad = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "Dad")).firstMatch
    XCTAssertTrue(maya.waitForExistence(timeout: 5))
    let face = CGPoint(x: 0.25, y: 0.2)   // inside the face's upper left quarter, clear of the circle
    XCTAssertTrue(app.isNear(app.colour(of: maya, at: face), 0xC8893F), "Maya's cover fills her face")
    XCTAssertTrue([0xE3DCC6, 0xDDE2D3, 0xEADBCB].contains { app.isNear(app.colour(of: dad, at: face), $0) }, "Dad keeps his letter tile")
    XCTAssertEqual(maya.value as? String, "my sister", "the tile reads as before")
}
@MainActor
func testAPhotoAddedOnThePageShowsOnTheTile() throws {
    let app = XCUIApplication.launchWithPeople(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")])
    app.openEntityPage("Lena"); app.addPhotoFromMenu("entity.more", "entity.addPhoto")
    XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()
    let lena = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "Lena")).firstMatch
    XCTAssertTrue(lena.waitForExistence(timeout: 5))
    XCTAssertTrue(app.isNear(app.colour(of: lena, at: CGPoint(x: 0.25, y: 0.2)), 0xE07A2E))
}
@MainActor
func testNoTileOffersAPhotoWhenSomeHaveOne() {
    let app = XCUIApplication.launchWithPhotos(); app.openTab("People")
    XCTAssertTrue(app.any("people.grid").waitForExistence(timeout: 5))
    XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "photo")).count, 0)
}
@MainActor
func testTheListKeepsTheCoverAtTheLargestTextSize() {
    let app = XCUIApplication.launchWithPhotos(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]); app.openTab("People")
    XCTAssertTrue(app.any("people.list").waitForExistence(timeout: 5))
    let maya = app.buttons.matching(identifier: "entities.row").matching(NSPredicate(format: "label == %@", "Maya")).firstMatch
    XCTAssertTrue(app.isNear(app.colour(of: maya, at: CGPoint(x: 0.04, y: 0.5)), 0xC8893F))
}
```

The UI test target does not link the kit, so the three tints are the literals of `Palette.monogramTints`.

- [ ] **Step 2: Run `-only-testing:LifelineUITests/PeopleUITests`.** Expected: FAIL; Maya's face is a tint.
- [ ] **Step 3: Read the covers in `EntitiesViewModel.refresh()` and draw them in `TileFace`.** The grid creates no task per frame: `.task(id:)` runs once per tile, and the cache answers the rest.
- [ ] **Step 4: Run `swift test`, then `-only-testing:LifelineUITests/PeopleUITests -only-testing:LifelineUITests/PhotosUITests -only-testing:LifelineUITests/ShellUITests`.** Expected: PASS; `testNoTileOffersAPhoto` still passes unchanged.
- [ ] **Step 5: Commit** — `People: a cover fills the tile; a tile without one keeps its letter`

### Task 6: App — photos on a memory page and on You

**Files:**
- Modify: `ios/Lifeline/Screens/Memory/MemoryScreen.swift`, `ios/Lifeline/Screens/Memory/MemoryViewModel.swift`
- Modify: `ios/Lifeline/Screens/You/YouScreen.swift`, `ios/Lifeline/Screens/You/YouViewModel.swift`, `ios/Lifeline/Screens/You/PortraitHeader.swift`
- Test: `ios/LifelineUITests/PhotosUITests.swift`

**Interfaces:**
- Consumes: Task 4 `PhotoShelf`, `PhotoHeader`, `PhotoRow`, `PhotoViewer`, `.addPhotoFlow`, `ErrorLine`, `launchWithPhotos`, `fixturePath`, `addPhotoFromMenu`.
- Produces:
  - `MemoryViewModel.shelf: PhotoShelf` (subject `.memory(memory.id)`), `photoError`, `photoLabel` (`isMemory: true`); `refresh()` calls `shelf.load()`. `MemoryScreen`: the toolbar keeps "Change…" (`memory.change`) and adds a `Menu` (`ellipsis.circle`, accessibility label "More", identifier `memory.more`) holding "Add a photo" (`memory.addPhoto`). `PhotoRow` (decision 13: one photo or more) under the title and Play; "Adding the photo…" in its place while adding; `photoError` in a bottom slot (`photo.error`); the viewer as on entity pages.
  - `YouViewModel.shelf: PhotoShelf?`, made in `refresh` for `.entity(owner.id)` once the owner is known, with `onError` setting `notice = .error(message)` in You's existing slot (`you.error`). `PortraitHeader` takes `cover: Photo?`, `photos: [PlacedPhoto]`, `cache:` and `onOpen:`: `PhotoHeader` (label "Photo of you") above the name when there is a cover, and `PhotoRow` under the strip with two or more. `YouScreen`'s toolbar gets a `Menu` (`ellipsis.circle`, label "More", identifier `you.more`) holding "Add a photo" (`you.addPhoto`) only when there is an owner; "Settings" stays a labeled button.

- [ ] **Step 1: Write the failing UI tests**

```swift
@MainActor
func testAMemoryShowsItsPhotos() {
    let app = XCUIApplication.launchWithPhotos(); app.openEntityPage("Maya")
    app.buttons.matching(identifier: "entity.moment").matching(NSPredicate(format: "label == %@", "The tree house")).firstMatch.tap()
    XCTAssertTrue(app.any("memory.kind").waitForExistence(timeout: 5))
    let thumb = app.buttons.matching(identifier: "photo.thumb").firstMatch
    XCTAssertTrue(thumb.exists)
    XCTAssertEqual(thumb.label, "Photo for The tree house")
    XCTAssertEqual(thumb.value as? String, "taken 4 July 1999")
}
@MainActor
func testAPhotoAddedToAMemoryShowsThere() throws {
    let app = XCUIApplication.launchWithPeople(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")])
    app.openEntityPage("Sam")
    app.buttons.matching(identifier: "entity.moment").firstMatch.tap()
    XCTAssertFalse(app.buttons.matching(identifier: "photo.thumb").firstMatch.exists, "no photo, no frame")
    app.addPhotoFromMenu("memory.more", "memory.addPhoto")
    XCTAssertTrue(app.buttons.matching(identifier: "photo.thumb").firstMatch.waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["memory.change"].exists, "Change… stays a labeled button")
}
@MainActor
func testYouShowsYourCover() {
    let app = XCUIApplication.launchWithPhotos(); app.openYou()
    let header = app.buttons["photo.header"]
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    XCTAssertEqual(header.label, "Photo of you")
    XCTAssertLessThan(header.frame.maxY, app.staticTexts["you.name"].frame.minY)
    XCTAssertTrue(app.buttons["home.settings"].exists)
}
@MainActor
func testAddingAPhotoOnYouGoesToYourPage() throws {
    let app = XCUIApplication.launchWithPortrait(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("photo-orange", ext: "jpg")]); app.openYou()
    XCTAssertFalse(app.buttons["photo.header"].exists)
    app.addPhotoFromMenu("you.more", "you.addPhoto")
    XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 10))
    app.buttons["entities.aboutYou"].tap()
    XCTAssertTrue(app.buttons["photo.header"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["photo.header"].label, "Photo of you")
}
@MainActor
func testAnUnreadablePhotoOnYouUsesYourSlot() throws {
    let app = XCUIApplication.launchWithPortrait(["-uiTesting-pickPhoto", try XCUIApplication.fixturePath("not-a-photo", ext: "jpg")]); app.openYou()
    app.addPhotoFromMenu("you.more", "you.addPhoto")
    XCTAssertTrue(app.any("you.error").waitForExistence(timeout: 10))
    XCTAssertEqual(app.any("you.error").label, "Could not add this photo: Lifeline cannot read this file as a photo.")
}
```

- [ ] **Step 2: Run `-only-testing:LifelineUITests/PhotosUITests`.** Expected: FAIL; `memory.more` and `you.more` do not exist.
- [ ] **Step 3: Implement as the Interfaces block says.**
- [ ] **Step 4: Run `swift test`, then `-only-testing:LifelineUITests/PhotosUITests -only-testing:LifelineUITests/YouUITests -only-testing:LifelineUITests/KindsUITests -only-testing:LifelineUITests/SameStoryUITests -only-testing:LifelineUITests/SteadyUITests -only-testing:LifelineUITests/ShellUITests`.** Expected: PASS. The last four reach the memory page or You's toolbar.
- [ ] **Step 5: Commit** — `Memories and You: add a photo; a memory shows its photos, You shows your cover`

### Task 7: Docs, screenshots and the device check

**Files:**
- Modify: `docs/OVERVIEW.md` ("The shape of the app" paragraph, section 7 "Data model", section 9 "Keeping a copy", "Designed, not built")
- Modify: `docs/DECISIONS.md` (one entry for S4, dated the day it is written: decisions 2, 3, 4, 6, 8, 10, 15 and 20)
- Create: `docs/plans/2026-11-16-sections-photos-device-check.md`
- Create: `docs/screenshots/sections-photos/before-people.png`, `before-maya.png`, `before-memory.png`, `before-you.png`, `after-people.png`, `after-maya.png`, `after-maya-photos.png`, `after-viewer.png`, `after-sam.png`, `after-memory.png`, `after-you.png`, `after-people-largest-text.png`

- [ ] **Step 1: Take the "before" screenshots.** Create a temporary worktree: `git worktree add ../lifeline-photos-before origin/sections-you`. No cherry-pick is needed (decision 23). In both worktrees, add an uncommitted UI test file `ScreenshotTour.swift` that adds each screen as a kept `XCTAttachment`. Before: `-uiTesting -uiTesting-seedPeople` for People, Maya's page and "The tree house"; `-uiTesting-seedPortrait` for You. After: `-uiTesting -uiTesting-seedPhotos` for People, Maya at the top, Maya's Photos row, the viewer, Sam, "The tree house" and You, and People at `UICTContentSizeCategoryAccessibilityXXXL`. Run each with `-resultBundlePath`. Export with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`. Copy the images under the names above. Remove the temporary worktree and delete `ScreenshotTour.swift`.
- [ ] **Step 2: Update OVERVIEW.** Say how a photo is added and where it shows (tile, header, row, memory page, You), what the app keeps (a 2048-pixel JPEG with no metadata in `photos/`), what it reads from the photo and what it does with it (a "taken" caption only), how remove and the cover work, how a launch sweep removes orphans, and that photos are in the `.lifeline` copy and out of the phone's cloud backup. Add `photo` and `photo_link` to the data model text. Move "one photo, one story" out of "Designed, not built" only if the owner says the prompt is done; S4 builds the storage, not the prompt.
- [ ] **Step 3: Add the DECISIONS entry** in the file's existing format, newest first, with the costs: links per subject kind (decision 2), metadata stripped from the file (decisions 3 and 4), photos stay on the target after an undone merge (decision 11), a pre-S4 build refuses a post-S4 copy, photos on the strip wait.
- [ ] **Step 4: Write the device checklist.** Each item is one line the owner ticks on the iPhone:
  1. "Add a photo" on Maya's page opens the system picker, and no permission prompt shows, before or after.
  2. Pick a HEIC photo, a screenshot (PNG) and a photo from iCloud that is not on the phone; each shows upright as the cover, and "Adding the photo…" shows while the iCloud one downloads.
  3. Pick a wide-colour (Display P3) photo; its colours on the page match the Photos app.
  4. Pick a photo taken with location on: the caption says "taken {date}"; no place, map or memory changes. Export a copy, unzip it on a Mac, and check with Preview's inspector that the file in `photos/` has no GPS and no EXIF date.
  5. Delete the original in the Photos app; the photo stays in Lifeline.
  6. In Settings, iCloud Backup shows that Lifeline's backup size did not grow by the photos' size.
  7. Remove a cover; the next photo becomes the cover. Remove the last; the tile shows its letter and the page has no header or empty frame.
  8. Scroll a People grid with 20 covers quickly; nothing stalls.
  9. With VoiceOver, the header reads "Photo of Maya, taken {date}", and a tile reads only the name and "my sister".
  10. Export a copy, restore it, relaunch: every photo is back. Restore a copy made before this build: it opens and has no photos.
- [ ] **Step 5: Run `swift test`.** Expected: PASS. Do not run the whole UI suite here; the controller runs it after the final review.
- [ ] **Step 6: Check that `git status` shows no `ios/Config/Local.xcconfig` and no `ScreenshotTour.swift`.**
- [ ] **Step 7: Commit** — `Docs: photos in the overview, screenshots, and the device checklist`

---

## After S4

S5 (search) and S8 (places) may start in either order. S6 shows a moment's cover on its Timeline row, and S7 a thing's cover on its shelf tile, both from `PhotoRepository.covers` or a memory equivalent. Whether a photo's date may place it on You's strip, or a photo's location may suggest a place, needs a spec section first (decision 6). The dark and increased-contrast colour values still have no PR assigned.
