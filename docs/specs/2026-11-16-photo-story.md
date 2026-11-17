# A photo starts a story (Phase 1.5)

Status: direction decided by the owner on 2026-11-16 in conversation. Draft for the owner's redline. A plan must follow before code.

This spec is "Phase 1.5: one photo, one story" in `docs/OVERVIEW.md`. It builds on the photo store of S4 (`docs/plans/2026-11-16-sections-photos.md`). The mock-up is `docs/design/Photo2.dc.html`, without its "who's this?" part.

## Intent

A person who does not know where to start can pick one photo, look at it and tell its story. `docs/PRINCIPLES.md` ("Props: photos and music as memory cues") says a picture gets a richer scene than a question does. Photos in the app today only decorate a page. This step makes a photo produce a story.

## Terms

- **Photo session:** a session that is about one photo.
- **Subject photo:** the photo a photo session is about.
- **Favorites grid:** the app's own screen that shows the person's Favorites album from the photo library.
- **Photo card:** the block on the landing and on the session's page that shows the subject photo and its offers.
- **Offer:** one labeled button that the person can tap to accept. An offer has no "No" button. An offer that is not tapped changes nothing.

## Goals

1. The person can start a photo session from a new photo and from a photo that is already in the app.
2. The new-photo path opens on the person's Favorites.
3. The subject photo stays on screen while the person talks.
4. Each memory that the telling produces holds the photo.
5. The app offers the photo to the pages of the people, places and things that the story names. The person accepts each with one tap.
6. The app offers the photo's date as the "when" of a memory. The person accepts with one tap.

## Non-goals

- Face detection, face grouping and "who's this?" naming.
- Photo clusters and any scan of the library.
- A guess of the era from how a photo looks.
- A change to "Add photo" on a page. It keeps the system picker.
- Photos on the life strip of You.
- Use of the photo's location. The app stores it, as in S4, and offers nothing from it.
- More than one subject photo for one session.
- Follow-up questions about the photo, and a "Settle in" session about a photo.

## Anti-goals

- The app must not attach a photo to a page that the person did not choose.
- The app must not set a memory's date from a photo without a tap.
- The app must not send the photo, its date or its location to a model or to a server.
- The app must not ask for photo access at launch.
- The app must not say what is in a photo. It cannot see the photo.

## Constraints

- Data posture: the photo stays on the phone. This step adds no network call. The system can download an iCloud original when the person picks it; that download is the system's, as with the system picker in S4.
- The person is the author. Every link to a page and every date from a photo comes from a tap.
- Uncertainty is shown. A date that came from a photo must be stored and shown as such.
- The app asks for photo-library access. This reverses the S4 rule "the app asks for no photo-library permission". The plan must add an entry to `docs/DECISIONS.md` with the reason: the owner wants the first screen to be the person's own Favorites, not the whole library.
- The schema change must be additive. No table is rebuilt.
- Fixtures are invented. Test photos come from `GeneratedPhoto`.

## Approaches

The question was how a session remembers its photo. A story is sorted after the recording ends, and a memory can be kept days later, so the tie must be durable.

1. **The session points at its photo (chosen).** The session row gains one optional column. The sweep keeps a photo that a session points at. The change is one added column. It mirrors `subject_entity_id`, so the opening, the record bar and "Tell another" extend in the same way.
2. **A third kind of photo link.** `photo_link` gains a session subject. The model is uniform, but the table has a check constraint ("exactly one subject"). SQLite cannot change it in place, so the table must be rebuilt one day after it shipped. The risk is larger than the feature needs.
3. **The pending photo waits outside the database.** A kill, a restore or a late landing can lose the tie, and the sweep then deletes the photo. Rejected.

The owner chose approach 1.

## Behaviour

### Where a photo session starts

- **A new photo.** The record bar's menu gains "Tell a story about a photo", below "Settle in". It is on every tab. It opens the Favorites grid (see "Photo access and the Favorites grid").
- **A photo already in the app.** The photo viewer (`PhotoViewer`) gains a labeled button, "Tell its story". It starts a photo session with that photo. The photo keeps every link it has.

A photo session is a quick session (`SessionKind.quick`). There is no photo form of "Settle in" in this step. A tap while a session is starting or recording does nothing, as for every start.

### Photo access and the Favorites grid

- The app asks for access the first time the person taps "Tell a story about a photo". It does not ask at launch or from the viewer path.
- Before the system prompt, the app shows one screen with this copy and one button, "Continue": "Lifeline will ask to see your photos. They stay on this phone. Lifeline shows them only so you can pick one."
- The usage string in `ios/project.yml` (`NSPhotoLibraryUsageDescription`) is: "Lifeline shows your photos so you can pick one and tell its story. They stay on this phone."
- **Full access:** the grid shows the Favorites album, newest first, under the heading "Your favorites".
- **Limited access:** the grid shows the photos the person allowed, newest first, under the heading "Photos you allowed". It does not say "Favorites".
- **Every grid** has a labeled button, "All photos", that opens the system picker. A photo picked there starts the photo session in the same way.
- **No access, or an empty grid:** the system picker opens directly. The app does not ask again and shows no error. The feature works without the permission.
- The app reads only that album (or the allowed set). It reads thumbnails for the grid and the full image for the one photo the person picks. It stores only that photo, with the S4 import rules: a downscaled copy, the SHA-256 one-copy rule, the date and the location with origin `exif`, and the asset identifier. `PhotoLibrary.add` needs a page or a memory to link to, and a photo session has neither at this point. So `PhotoLibrary` gains a second method that stores a photo with no link and returns it. For a photo that is already stored, that method returns the stored photo, repairs a missing file, and adds no link.
- A tap on a photo in the grid starts the session. There is no second confirmation.
- While the photo is copied, the app shows "Adding the photo…" (`PhotoAddingLine`). A failed import shows the S4 error line and starts no session.
- PhotoKit code lives in the app target, behind a small protocol, so the kit stays free of it and a UI test can supply generated photos (a launch argument in the manner of `-uiTesting-pickPhoto`).

### The session

- The session screen shows the subject photo at the top, above the turns. The photo stays for the whole session. It must stay visible at the largest text size.
- The opening is fixed: "Tell me about this one."
- After the opening the app only listens, as in every quick session (`TurnPolicy`, reason `quickStory`). The turn policy, the interviewer's request and its prompt do not change. The second line of the mock-up ("Where were you? What happened right before someone took it?") is not built.
- The opening does not use the person's open questions or the scene bank. Its log ID is `photo`. The alternates are the scene prompts, as for a page session.
- The record bar and the session list name a photo session "A story about a photo".
- A kill during a photo session leaves the session row with its photo. The resumed landing shows the photo card.
- "Tell another" after a photo session opens the Favorites grid again. After a kill it starts on the tab, as today.

### What gets the photo

- **Memories.** When a memory is created from a candidate of a photo session, the same write links the subject photo to that memory. This also applies when a telling from a photo session is merged into an older memory: that memory gains the photo. The link is added once. If the person later removes the photo from that memory, the app does not add it again.
- The S4 cover rule applies without change (`PhotoRepository.link`): the photo joins the end of the memory's photos, and it becomes the cover only when the memory has no photo.
- **Pages.** The photo card offers the photo to each person, place and thing that is linked to a memory of the session and does not hold the photo. One button for each: "Add to Maya's page". For the owner: "Add to your page". A tap links the photo to that page with the same S4 rule: at the end, and as the cover only when the page has no photo. A page kept from the AI is offered like any other; the offer is local.
- A photo that started on a page keeps that link.

### The photo's date

- For each memory of the session, the photo card can offer the photo's date. The copy is "The photo is dated 14 July 2019. Use that for when this happened?" with one button, "Use this date". The copy says "dated", not "taken": a scanned print carries the date of the scan.
- The app offers the date when the photo has a date and one of these is true:
  - The memory is unplaced.
  - The photo's date is outside the memory's `earliest`…`latest` band.
- The app does not offer it when the photo's date is inside the band. The person's words win.
- The app does not offer it when the memory's date has origin `stated` or `confirmed`, wherever the photo's date falls. A tap replaces the range and its evidence text, and there is no undo, so the person's words must not be at risk (review of PR #29). The person can still change that date with the existing "when" controls.
- A tap sets the memory's range to that day, with day granularity, a new origin `photo`, and the evidence text "the photo's date, 14 July 2019". The display of that memory's date must show that it came from a photo, in the manner the app shows `inferred` today.
- A date with origin `photo` is settled (`TimeRange.isSettled`), like `stated` and `confirmed`: the person tapped it. The resolver must not rewrite it, and an open "when" question must not target that memory. It does not read as said (`readsAsSaid`): the display says it came from a photo.
- The person can change the date afterwards with the existing "when" controls. Their change replaces origin `photo`.
- The time of day and the location of the photo are not used.
- A photo with no date offers nothing.

### The photo card

The card is one view, used on the landing and on the session's page in Sessions. It reads the store each time it appears, so it is correct whenever the memories are kept.

- The photo, with its caption (`PhotoCaption`).
- One line for the state of the memories:
  - While any moment of the session is not yet kept: "This photo goes on each moment you keep."
  - For each kept memory that holds it: the memory's title, with a labeled "Remove" button that unlinks the photo from that memory.
- The page offers, if any.
- The date offers, if any.
- On the session's page only: "Remove the photo from this story". It clears the session's pointer. It does not unlink the photo from any memory or page.

The landing still asks for nothing. Every offer is optional, and "Done for now" stays the default.

The rules for which offers show are one pure function in the kit, with tests: inputs are the photo, the session's memories with their ranges, the entities linked to those memories, and the photo's links.

### Where a photo lives

A photo now has three kinds of home: a page, a memory, and a session that points at it.

- The sweep deletes a photo row only when it has no link and no session points at it (`PhotoRepository.deleteUnlinked`).
- `PhotoRepository.unlink` deletes the row with its last link only when no session points at it.
- "Remove the photo from this story" clears the pointer. If the photo then has no link, the same call deletes the row and the file.
- A deleted session clears nothing by hand: its row is gone, so the next sweep removes a photo with no other home. The sweep before an export already runs, so such a photo does not travel in a copy.
- The delete dialog for a session gains one sentence when its photo has no other home: "Its photo goes too." A memory that came only from that session is deleted with it, so it does not count as another home.
- "Hide today from the timeline" does not change the photo.

## Data model

Migration v14, additive:

- `session.subject_photo_id`, text, nullable, references `photo(id)` with `on delete set null`, with an index.
- `session.started_from` accepts a new value, `photo`. The column has no check constraint, so only `SessionOrigin` changes.

In code:

- `RangeOrigin` gains `photo`. The `origin` column has no check constraint.
- `Session` gains `subjectPhotoID`. A photo session has no `subjectEntityID`, also when it starts from a photo on a page.
- `OpeningPrompt` gains a `photo` case.

Backup: no format change. The photo row and file travel as in S4. The session row carries the new column. A restore of an archive from before v14 migrates as usual.

The plan must confirm that v14 is free on `origin/main` before the first task, and show the owner the exact schema before it ships.

## Edge cases the plan must cover

- The person picks a photo that is already stored (same SHA-256): the session points at the stored photo; no second copy.
- The person picks a photo whose stored file is missing: the S4 repair writes it again.
- The person denies access, then taps the entry again: the system picker opens.
- The person changes access in Settings between two sessions: the grid follows the current access each time it opens.
- A kill between the photo's import and the session's first write: the photo has no home; the launch sweep removes it. The order is: store the photo with no link, then create the session row with its pointer. The plan must make this the only loss.
- A session that produces no memory: the photo stays on the session and shows on its page.
- A memory merged into another (S4 `movePhotoLinks`): the photo's link moves with it; the pointer does not change.
- Two photo sessions about the same photo: each points at it; removing it from one story keeps it for the other.
- A subject photo removed from every memory and page: it still shows on the session's page.
- The largest text size: the photo, the opening and the session's controls must all stay reachable on the session screen.
- VoiceOver: the photo on the session screen has a label that states the caption, not the content.

## Tests

- Kit: the migration; the three-homes rule in the sweep and in `unlink`; the link at memory creation and at merge; no re-link after a removal; the offer function (unplaced, outside the band, inside the band, no date, already linked page, owner page); the `photo` origin through a date change; the opening chooser with a photo.
- UI: both entry points; the grid in full, limited and no access (through the test source); the photo on the session screen; the landing card with its offers; the session page's card; the delete dialog's sentence. One test at the largest text size.
- A device checklist: the real permission prompt in each of its three answers, a Favorites album with an iCloud-only photo, a scanned print's date, and the photo on screen while the app speaks.

## Left to the builder

- The layout of the photo on the session screen and of the card, within the existing theme.
- The grid's column count and thumbnail size.
- Where the "came from a photo" mark shows on a memory's date, in line with how `inferred` shows today.

## Calls made in this spec without the owner

The owner decided: both entry points; ask for access and open on Favorites; a photo can sit on several memories and several pages; pages are offered with a tap; the date is offered with a tap; the app opens and then only listens; approach 1. These are the writer's calls, for the owner to check:

1. The new-photo entry is in the record bar's menu, on every tab.
2. The grid starts the session on one tap, with no confirmation step.
3. The app shows its own one-screen explanation before the system prompt.
4. Each memory gets the photo when it is kept, not at the landing, because a moment can be kept days later.
5. An offer has no "No" button and no stored "declined" state. It stays available on the session's page.
6. The date is not offered when it is inside the memory's band, even if it would narrow the band. A date the person took from a photo is settled: later sorting does not move it.
7. A session is a home for its photo, with its own "Remove the photo from this story".
8. A photo session started from a photo on Dad's page is not also "about Dad".
9. "Tell another" after a photo session opens the grid again.
10. The session's delete dialog says "Its photo goes too." when that is true.
