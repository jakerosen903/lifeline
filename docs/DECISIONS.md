# Decision log

One entry per decision. Newest first. Status is Decided, Open, or Superseded.

## 2026-11-18 · PC-a: rulings made while building people and contacts

**Status:** Decided by the builder, except R13, which the controller made and the owner must confirm. The owner can overrule each one. Source: `docs/plans/2026-11-18-people-contacts.md`, ledger `.superpowers/sdd/2026-11-18-people-contacts/rulings.md` (R1 to R39). Narrows two statements of the entry below and of the spec.

**Decision.**

Schema:

- R36: the migration is named `v15`. Why: the photo story registered `v14` first (`session.subject_photo_id`), and GRDB records a migration by name, so a device that ran one `v14` would skip the other. After the merge with `main` the order is `v14` (photo story), then `v15`.

Matching and origins:

- R7: with a said name, only the name picks candidates. The relation part of "Priya, my mom" never picks a candidate. Rule 2 never fires when a name was said. Rule 3 needs exactly one candidate whose full name equals the said name.
- R12 and R13: every write that meets an existing link keeps the stronger origin, and no origin is the weakest. An older link with no origin takes the guess's origin when a retelling or a merge reaches it, and shows the mark when that is `assumed`. An older link nothing touches has no mark. Keep never settles a guess to `confirmed`. This narrows "Links older than this feature show no mark" below and in the spec. Why: a guess that reaches an old link is still a guess (principle 5).
- R8: a stored choice applied on Keep saves both halves of the said name as aliases, as settle does. A guess with origin `said` saves only the relation half. A group phrase is never saved.
- R9: a stored choice matches the whole said ref. "Robin" and "my roommate, Robin" are two keys.
- R14: a person made by a stored "Someone new" choice is not an empty guess. A later move never removes them.
- R15: an alias saved before this change that is a group phrase no longer links on Keep. The phrase asks again in each story.
- R10: until PC-b, a guessed contact cannot occur. A stored `contact` choice makes a new person with origin `confirmed`.
- R38: a fact linked by a person id that the model picked takes the origin of the mention link that reached the same person in that memory. With no such mention, it takes `assumed`. A move also takes a detail of the old person from each memory whose mention is in the move. Why: spec step 2 says a model-supplied person id is still `assumed`.
- R11: after a serious disclosure no person mention counts as carried. The name goes to the People queue.

Moves and Undo:

- R19 and R23: a detail moves only with a whole answer. A fact whose own mention is in the move always takes its detail along.
- R20 and R24: an empty guess is a person made by a guess, with nothing that refers to them. A move clears the target's guess flag.
- R39: a move removes a guessed person only when the owner has not edited them: the name is still as said, no dates are stated, and the person is not hidden or kept from the AI. A rename on the person's page clears the guess flag, as the rename in People does. Why: spec "Moving a name", point 6, "no name the owner gave".
- R21, R26 and R27: Undo is refused as stale when rows it would restore or change moved on since, for example a rename or a deleted memory. The refusal shows its sentence for 6 seconds, with no Undo.
- R25: a settle that changed nothing records nothing, so its Undo is not refused.
- R29: "Done" with the choice unchanged settles an `assumed` or `new` link. On `said`, `confirmed` or no origin it writes nothing.
- R34: when a move removes the person whose page is open, the page stays up with its content disabled and the notice "Changed to {name}." with Undo. It closes when the notice ends. A successful Undo brings the page back.

Cards and chips:

- R30: a card that waits shows a person chip only for each preview. A said name that Keep will not link has no chip there. A group phrase keeps its own "Who's this?" card.
- R37 (replaces the dead end in R30): a name marked "Not a person" on a waiting card keeps a quiet chip with the said name. The chip has no line and no mark. A tap opens the sheet with "Not a person" selected. Why: the sheet says "You can change this again at any time", and that must be true.
- R31: the move notice uses the slot each host already has. A refused Undo shows in the same place.
- R17: an `assumed` link with no said name still shows the word "Assumed".
- R18: link reads return hidden memories too. Each view filters them.

Test seeds:

- R35: `-uiTesting-seedGuesses` seeds Priya, made by a guess, for R34's held page. `-uiTesting-guessesLanding` leaves the latest landing open. The follow-ups fixture gained the group phrase "for our parents".

Plan decision 8: a name no memory carries keeps the old "Who's this?" card with its four choices in this PR. The owner decides later whether it goes.

**Why.** Each ruling closes a case the plan left open. A hidden guess breaks principle 5, so each ruling errs toward showing the guess and toward a recoverable change.

**Costs.** R13 puts a mark on an old link a retelling reaches, and the owner may see marks on old stories. R34 keeps a deleted person's page open for a few seconds. Two cards for one name exist until PC-b.

## 2026-11-18 · People are backed by contacts, and every guess about a name shows

**Status:** Decided. Source: the owner's brainstorm of 2026-11-18, four approved screens (`docs/design/PC1_Assumed.dc.html` to `PC4_NoContact.dc.html`) and the owner's approval of `docs/specs/2026-11-18-people-contacts.md`. Supersedes the line "`contact_identifier` is deferred; no Contacts framework in V1" in the first spec.

**Decision.** A person can hold one contact, and a contact one person. A person needs no contact, and the app works with full, limited or no contacts access. A link between a memory and a person records how it was made: `assumed`, `said`, `confirmed` or `new`. A link the app chose from a name alone shows a dashed ochre outline and the word "Assumed" until the owner settles it. Keep does not settle it.

- A name said with a relation phrase that one person holds ("Danielle, my sister") is not a guess.
- A guess teaches the app no name. An alias is saved only from the owner's own words or choice.
- One answer carries inside one recording only.
- The contact's picture is the person's first picture when the person has none.
- Nothing from a contact goes to the model.
- Two people can be merged, by a drag on People or by a button, with a confirm and Undo.
- The extractor will give each person in a recording a handle, so two people with one name stay apart (step 2, its own plan).

**Why.** On first use a story about a roommate was filed under a friend with the same spoken name, with no sign of a guess and no way to change it. A guess shown as a fact breaks principle 5. A contact gives a real person one identity across stories.

**Costs.** Marks are common, because every bare name is a guess. Links older than this feature show no mark, so an old wrong link looks settled until the owner changes it. A name the app does not know becomes a person on Keep, so a misheard name is a person until the owner removes or merges it. The extractor does not see a contact's full name.

## 2026-11-18 · S6c: chapters are names with stated years

**Status:** Decided by the builder. The owner can overrule each one. Source: `docs/plans/2026-11-18-timeline-chapters.md`, ledger `.superpowers/sdd/2026-11-18-timeline-chapters/rulings.md`.

**Decision.** A chapter is a name. It has stated years only when the person said them. It has said members: the moments the person put in it. `chapter.range` holds stated years only. The resolver computes the span of the said members on each run and never writes it to the chapter.

The ten builder's defaults:

1. The life map opens from the Timeline's "…" menu, item "Chapters", until S6b. The spec opens it from the pinned card, which does not exist yet. S6b can keep or remove the item.
2. A chapter with no name and with said members shows no tag on the Timeline. On the life map it shows as "No name yet", so the person can name it or remove it.
3. A tagged moment's menu has "Take out of "{name}"". The spec gives no other way to undo a wrong tag.
4. A rename to a name that another chapter has is refused. The sheet says "You already have a chapter with this name." A rename never merges two chapters.
5. A rename to an empty name is refused. A chapter loses its name only when it is removed.
6. Existing derived ranges stay in the database. No write clears them. The code ignores them. "Say when it was" replaces one with a stated range.
7. The prune keeps a chapter that a story points at. The launch repair changes in one way only: it never prunes a chapter with stated years.
8. Undo of a removal puts a tag back only on a memory that still exists and has no chapter. Undo never takes a moment from a chapter the person chose in the meantime.
9. Said members in the chapter's sheet are text rows. A tap on one does nothing yet.
10. The extractor's context packet sends a chapter's stated years, or no years. It no longer sends a member span as the chapter's dates.

Rulings made while building:

- R2. Inside one resolver run, a chapter's member span comes from the ranges in the store at the start of that run. A moment that the run places does not widen the span until the next run. The stored range was refreshed only at the end of a run before this build, so this is not a regression. `run()` stays idempotent.
- R3. The tag's accessibility label stays the chapter's name, with the hint "Opens this chapter". The plan's "Chapter: {name}" is withdrawn. An existing UI test asserts that the label is the name. The row's own label already says "chapter", and VoiceOver adds "button".
- R4. A life map row has an `isOpenEnded` field. The view does not repeat the kit's rule for "no stated end". One rule lives in one place.
- R7. The words "Untitled chapter" show nowhere. For a chapter with no name, the remove question is "Remove this chapter?" and the notice is "Removed a chapter with no name." A named chapter keeps "Remove “{name}”?" and "Removed “{name}”.". The notice sits on the Timeline, and the app must not quote a name that the person did not give.
- R8. A session delete prunes the empty chapters with no name, in the same write. A merge does not prune: a merge can be undone, and a prune would lose the tag on undo. The launch repair prunes that case. When an undo puts back a memory whose chapter was removed in the meantime, the memory comes back with no chapter.
- R9. Five minors from the final review are not fixed in this build. The plan lists them under "After S6c".
- R1, R5 and R6 are process rulings. `ChapterActions` owns the tag write path and `CandidateActions` forwards to it (R1). Two files the plan did not list are accepted, for one responsibility per file (R5). The docs are written before the final run, and the controller records the full run and the screenshots after the final review (R6).

**Supersedes.** "2026-10-26 · The timeline groups moments into computed life periods", for chapter ranges. That entry said that a chapter the person names replaces the period it covers. A chapter now never replaces a period. A chapter's range never comes from its members. The same rule in `docs/specs/2026-11-16-audit-data-fixes.md` (A1, rule 3) also yields to this entry.

**Why.** A span computed from members showed dates the person never said (PRINCIPLES 5). A date overlap says nothing about a moment, so the app tags no moment by its date (PRINCIPLES 1).

**Consequences.**

- A chapter that had dates before this build shows "No dates yet" under "Not placed in time yet" on the life map until the owner says when. Its old range stays in the database and is ignored.
- A said member dated outside the stated years keeps its tag. The app does not correct it.
- No migration. `memory.chapter_id` is the one tag for a moment. `story.chapter_id` stays in the schema. The Timeline does not read it. The kit still reads and writes it: `ChapterRepository.remove` and `restore`, the prune, and `StoryRepository`. A later migration can drop it after the kit stops using it.
- Each tag change is one write: the find-or-insert of a chapter, the tag and the prune.

**Known costs.** These stay after the final review.

- A chapter hint that is only punctuation cannot be accepted. The card stays pending and shows "Could not file that" on each tap. In "Add to a chapter…" and in the rename alert, a name of punctuation only keeps the button disabled.
- Undo of a removal can leave two chapters with one name, when a hint made a chapter of the same name inside the 6 seconds.

## 2026-11-16 · A photo starts a story; the app asks to see Favorites

**Status:** Decided. Four items are open for the owner (see the end of this entry). This entry reverses one rule of S4.

**Source:** `docs/specs/2026-11-16-photo-story.md` and `docs/plans/2026-11-16-photo-story.md`, decisions 1 to 12. The rulings made while building are below. The owner approved the v14 schema on 2026-11-16. The schema change is one column, `session.subject_photo_id`.

**Decision.** The person picks one photo and tells its story. The photo stays on screen while the person talks. After the story, the photo goes on each memory the person keeps.

- **This reverses S4’s rule “the app asks for no photo-library permission”.** The app now asks for photo access, once, on the first tap of “Tell a story about a photo”. The app does not ask at launch. It does not ask from the photo viewer. It does not ask from “Add a photo”, which still uses the system picker and asks for nothing.
- **The owner’s reason.** The first screen must be the person’s own Favorites, not the whole library. A picker that opens on the whole library is a worse prompt for a story. Only the Favorites album gives the person a short list of photos that they already chose to keep.
- **The access level.** The app asks with `.readWrite`. It is the only level that can read an album. The app never writes to the photo library.
- **What the app reads.** The app reads the Favorites album, or the set of photos the person allowed (limited access), and the one photo the person picks. It does not scan the library. It does not fetch an asset outside that album. It stores only the picked photo, with the S4 rules (a JPEG of at most 2048 pixels, no EXIF, no GPS).
- **Nothing leaves the phone.** The photo, its date and its position go nowhere. The app adds no network call. For the one picked photo, the system can download an iCloud original.
- **Three homes for a photo.** A photo can sit on a page (an entity), on a memory, and now on a session. A session points at its photo with `subject_photo_id`. A photo that a session still points at stays when its last page link goes. When nothing holds the photo, the row and the file go in one call.
- **Open and listen.** A photo session is a quick session that starts from a photo. The app speaks one fixed opening, “Tell me about this one.”, and then asks nothing. `TurnPolicy` and the interviewer prompt do not change.
- **Tap-only offers.** The photo links to a memory when the person keeps the memory, or when a telling of the session is merged into a memory. After that, the photo card offers “Add to {title}’s page” and “Use this date”. Each offer is a tap. An offer has no “No” button and stores no declined state. A date from a photo comes only from a tap.
- **A date from a photo is settled** (origin `photo`). The evidence text is “the photo’s date, 14 June 2012”. The memory page marks it “from a photo”.

**Rulings made while building (2026-11-16).** Each ruling has its cost.

- **Undo of a merge takes back the photo link that the merge added.** It never takes a link that the target held before. Why: without this, an undone merge leaves a photo on a memory that the telling no longer belongs to. Cost: none. Remove `MergeReceipt.addedPhoto` to undo the ruling. This differs from S4, where an undone merge leaves the photos on the target.
- **The merge write says which link it added (final review).** The link call returns the photo when it wrote the link. The check runs inside the transaction, after the folds of a group merge. Why: a check before the folds counted a photo that a folded memory carried to the target as added. The undo then took the photo off both memories.
- **“Use this date” is one write, then the resolver runs.** The write changes the memory’s range. (As first built, it also changed the range of the memory’s chapter. S6c of 2026-11-18 removed that: a chapter’s range holds stated years only.) Why: a memory placed relative to this one must be placed again at once. Cost: one resolver run per tap.
- **`PhotoCaption.longDate` is public.** The caption and the evidence text share one formatter.
- **The running session’s header reads “You chose a story about a photo”.** The Sessions list names the session “A story about a photo”. Why: the record bar sits under the session screen, so the plan’s name “on the bar” has no place to show. The header follows the pattern “You chose a quick story”. Cost: one string.
- **The Sessions list names a photo story from `startedFrom`, not from the photo row.** It needs no read. The name stays true after the photo leaves the story.
- **The system picker for “All photos”, for no access and for an empty album is inline in the start sheet.** Only its bottom toolbar is hidden. Why: every path then starts the session from the dismissal of that one sheet, and the app never presents the session over a sheet. Cost: the inline picker looks unlike the modal picker of “Add a photo”. The owner must see it on the device.
- **The record bar menu uses a fixed order.** The menu opens upward and showed its items in reverse, so “Tell a story about a photo” sat above “Settle in”.
- **A cancel while a photo is added stores nothing.** The rule lives in the kit (`CancellablePhotoStore`). A stray stored photo is not visible in the UI, so no UI test can fail for it.
- **Thumbnails ask for the full-quality image on the phone, then for the phone’s low-quality copy. The network stays off. A nil result is asked again.** Each request calls back once, so a tile never waits for a second delivery. The continuation resumes once, and a cancelled tile cancels its request. An iCloud-only favorite then shows its local low-resolution image, not an empty tile. Cost: two requests for an iCloud-only photo. Not checked against a real iCloud library. The device check covers it.
- **“Its photo goes too.” is on the landing’s delete dialog only.** The landing is the only place the app deletes a session.
- **A deleted session sweeps its homeless photo at once.** Why: the sentence in the dialog must be true before the next launch. Cost: one directory listing and one query per delete.
- **The Remove button’s accessibility label is “Remove from {title}”.** Two rows with the same visible “Remove” are the same to VoiceOver and Voice Control. The label starts with the visible text.
- **The card lists each memory that has a telling in the session (final review).** This includes a memory that a telling was merged into, which was first told in another session. The memory gets its title, “Remove”, its page offers and its date offer. Why: the merge put the photo on that memory, so the person must see it and be able to take it off.
- **The date offer is withheld for a date the person said or confirmed (review of PR #29).** `PhotoStory.offersDate` returns false for origin `stated` or `confirmed`. Why: “Use this date” replaces the range and its evidence text with no undo, so one tap could lose the person’s own words (principles 1 and 9). Cost: a photo cannot correct a said date from the card; the person uses the “when” controls. An offer with Undo is the other fix and is not built.
- **“Use this date” skips a memory whose range changed after the card was drawn (review of PR #29).** The write compares the stored range with the range the offer was made against, inside the transaction. Why: a stale offer must not replace a newer date. The card reads the store again when it next appears.
- **The offer stays for a guessed range (`inferred`, `derived`) outside the photo’s day. Open for the owner.** The review asked to withhold it there too, or to add Undo, because the tap replaces the range’s evidence text. The spec offers the date in this case, and withholding it would leave the offer for unplaced memories only. The recording and the transcript keep the person’s words; only the range’s evidence line is replaced. Cost if the owner disagrees: an Undo on the card, or one more guard in `offersDate`.
- **A date from a photo has no “you said” line (final review).** The memory page shows the day and the mark “from a photo”. The mark states the source. Why: the person tapped an offer. The person did not say the date. `TimeRange.saidEvidence` holds the rule.
- **“Tell its story” shows only where a session can start (final review).** The viewer inside a landing’s review does not show it. The app also hides it while a session or a landing is up. Why: there the button did nothing, and a start would replace a landing that the person has not answered.
- **“Remove the photo from this story” asks first (final review).** The dialog follows S4’s “Remove photo…”. Title: “Remove this photo?”. Message: “It leaves this story. The original stays in your photo library.” Buttons: “Remove photo” and “Keep it”. Why: when nothing else holds the photo, the tap deletes it from the app. The owner must confirm the new copy.
- **“Use this date” has the accessibility label “Use this date for {title}”.** Two offers are then not the same to VoiceOver and Voice Control. The label starts with the visible text.
- **The test seed has two photo sessions.** The second has no kept memory, and its photo has no other home. The delete test needs one. `-uiTesting-photoStoryLanding first|second` opens the app on a landing, because the delete dialog opens from a landing only.
- **Test changes.** The kit test target did not compile on Swift 6.4.2, so the controller un-nested two `#require` calls in `V7PeopleRulesTests.swift` in its own commit. `v13OnAPopulatedV12Database` now migrates up to v13, because its `select *` would see the v14 column. `testTheGridHoldsAtTheLargestText` launches with seeded people, because the Skip button of first open is out of reach at that size. That is an existing defect outside this work.
- **A known red test, not ours.** `keepWritesTheCardsKind` fails on `origin/main` (a1638c3). It stays as it is.

**Open items for the owner.** Each needs a decision or a look. The copy of the new “Remove this photo?” dialog also needs the owner’s word (see the rulings).

1. **Plan decision 4: the re-link case.** The app does not store “removed from this memory”. If the person removes the photo from a memory, and a second telling of the same photo session is merged into that memory, the app links the photo again. The spec says it must not. The plan accepted this rare case to avoid a new table. Cost of a fix: a table of removed links.
2. **The inline picker’s look.** See the ruling above. The device check shows it.
3. **The opening swap.** When the person swaps the opening, the photo stays under a scene question. The spec keeps alternates. The owner must say if this is wrong.
4. **A photo-dated memory reads as a guess on summaries.** The memory page shows a plain day. The entity page span and the life strip show “around 2019”. Plan decision 6 makes the date settled but not “as said”. Cost of a fix: one line in `readsAsSaid`.

## 2026-11-16 · S6a: rulings made while building the spine

**Status:** Decided by the builder. The owner can overrule each one. Source: `docs/plans/2026-11-16-timeline-spine.md`, ledger `.superpowers/sdd/2026-11-16-timeline-spine/rulings.md`.

**Decision.**

- A gap is measured from the latest end of all the moments above it, not only from the moment directly above. Example: 2000–10, then 2003, then 2012. The gap above 2012 is 2 years, not 9.
- The margin leaves out the years only when the moment above shows the same years and the same qualifier. A guess in the same year as a stated date keeps its word "around".
- Owner, 2026-11-16: for a confirmed relation ("before Graduation (2004)") the margin shows no years. The row shows the full text and the mark stays a dashed capsule. This changes the plan's decision 4.
- Owner, 2026-11-16: a story of one year has a solid dot only when every dated member reads as said. Otherwise it has a dashed dot and "around". This changes the plan's decision 8.
- An open story that is the last stop keeps the spine beside its members, and the spine ends at the last member (R7).
- A spine row keeps the age ("age ~7") on its date line, so the person sees why a guess sits where it does (R8).
- The "in your voice" length sits on its own line on a spine row, so the title has the full width (R9).
- Opening a story scrolls it to the top of the list. Opened members landed under the record bar. The owner confirmed this on 2026-11-16 (R13).
- The Check-this tag wraps. A long tag pushed the "..." menu off the row (R14).
- A tap on a tag does nothing until S6c makes the tag a button (R15).
- A story's members are list rows of their own, so each long-press menu belongs to one member (R16).
- Two UI tests that the plan wrote also pass on the old build, and they stay as written. One is a guard for kept behaviour (R12). The other cannot see where the date sits, so that is checked on the device at the largest text size (R11).
- Owner, 2026-11-16: "New chapter from here" goes with no replacement until S6c (decision 2), and a moment in a collection stays off the spine (decision 9). Known cost of decision 9: a gap label can cover years that hold collection moments.
- A guess that crosses two calendar years ("around 1999–2000", an age with a mid-year birthday) keeps "around" in the margin. Without it, the guess read as a stated range (R17).
- A gap next to a confirmed relation has no label and is not dashed. Its space stays. The edge of the relation's band is the builder's slack, so a number of years there is not what the person said (R18).

**Why.** A label of "9 years" across years that an earlier moment covers states something false about the person's life. A guess whose word is hidden reads as a fact (PRINCIPLES 5).

**Consequences.** Each kit ruling is a small change in `SpineLayout` with its tests. To overrule one, change the code and its tests. The view rulings (R7, R8, R9, R13, R14, R15, R16) have no unit test. The device checklist checks them: `docs/plans/2026-11-16-timeline-spine-device-check.md`.

## 2026-11-16 · Photos on pages, kept on the phone (S4)

**Status:** Decided. Builds on the five-sections decision of 2026-11-15.

**Source:** `docs/plans/2026-11-16-sections-photos.md`, decisions 2, 3, 4, 6, 7, 8, 10, 11, 15 and 20. The rulings made while building it are below. The owner approved the v13 schema on 2026-11-16. The schema is `photo_link` with `entity_id` and `memory_id`.

**Decision.** A person, place or thing page, a memory page and You can hold photos. The first photo is the cover. A cover shows as the page header and as the face of the People tile.

- **Links per subject kind (decision 2).** `photo_link` has `entity_id` and `memory_id`, exactly one set, each with `on delete cascade`. The spec had one polymorphic key. A cascade removes the link on every delete path with no code at each call site, and it needs no trigger, which the destructive-migration guard would flag. Cost: a third kind of subject, a chapter for example, needs a new column.
- **Metadata stripped from the file (decisions 3 and 4).** The stored copy is a JPEG of at most 2048 pixels with no EXIF, GPS or orientation flag. The date taken and the position live only in the database row, with their origin. Cost: the app re-encodes the photo, so the person’s original bytes are not kept. The original stays in the Photos app.
- **Metadata is a caption only (decision 6).** The app shows “taken {date}” and does nothing with the position. Cost: a photo’s date does not place it on the life strip, and its position does not suggest a place. A later spec must say where metadata may be offered.
- **Cover rules (decision 8).** When the cover is removed, the oldest-added photo becomes the cover. With no photo left, the tile shows its letter and the page has no header.
- **No orphans (decision 10).** A cascade removes links in the delete’s own transaction. A launch sweep removes unlinked photos, files with no row and `.partial` files. The sweep never deletes a row for a missing file.
- **You (decision 15).** You shows the owner’s cover and a “…” menu with “Add a photo”. Photos on the strip wait.
- **Backup (decision 20).** The copy holds `photos/*.jpg`, stored without compression. The manifest gets optional `photoFiles` and `photoBytes`.
- **A pre-S4 build refuses a post-S4 copy.** The copy has schema v13. A build from before S4 shows “This copy was made by a newer version of Lifeline.” A copy from before S4 restores and has no photos.
- **One copy per photo (decision 7).** The SHA-256 of the picked file identifies a photo. The same photo added to a second page links the one copy to both pages. The same photo added again to the same page changes nothing. Cost: two pages share one file, so removing the photo from one page must keep the file for the other.
- **A merge moves photos (decision 11).** A merge of two memories moves the source memory’s photos to the target. A source cover becomes an attached photo when the target has a cover. Undoing the merge does not move the photos back. Cost: an undone merge leaves the photos on the target.
- **Photos stay on their pages for now.** No Timeline row, Things tile, search result or map uses a photo yet (S5 to S8).

**Rulings made while building (2026-11-16).** Each ruling has its cost.

- **A repeat add repairs a missing file.** When the person adds a photo whose row exists and whose stored file is missing, the app writes the file again, with the same id and name, then links it. Why: picking the photo again is the only way to repair a photo that does not show. Cost: one extra file write on a rare path.
- **The page scrolls to its top when the cover changes.** This holds for the entity page and You. Why: “Make this the cover” is tapped lower on the page, and the person must see the result. Cost: a scroll jump the owner may not want. The owner must confirm.
- **The viewer’s “Done” has no glass background.** It is a plain toolbar button. With the glass background it measured 36 points at the largest text, under the 44-point minimum. Cost: this sheet’s toolbar looks unlike other sheets. The owner must confirm on the device.
- **Four plan tests differ from the plan’s text, with assertions of equal strength.** The owner must see them.
  - `photo.confirmRemove` is found with `.firstMatch`, because iOS 26 lists a confirmation-dialog button twice.
  - The viewer caption query is scoped to `photo.viewer`, because the page’s caption under the sheet has the same identifier.
  - The list cover sample is at x=0.1, not 0.04. At 0.04 the point lands on the row’s inset, before the face.
  - `testAMemoryShowsItsPhotos` reveals its row and waits for `memory.range`. The row is off screen in a lazy list, and “The tree house” is an event, so its page shows the range and no kind.
- **The pixel-colour tests poll for up to 10 seconds.** They poll before the unchanged colour assertion. Why: the image decodes off the main thread, so an immediate screenshot is a race. Cost: none. A wrong colour still fails.
- **Two extra failure tests.** A foreign-key failure at the row insert and a failure at the file write prove that a failed add stores nothing. Cost: two more tests.

**Rulings from the final review (2026-11-16).** Each ruling has its cost.

- **The sweep also runs before every copy.** Settings runs the sweep before an export and before a restore is staged, through the photo library, so it cannot run between an add's file and its row. Why: a photo whose memory or session was deleted in this run keeps its row and file until the next launch, and a copy made before then would carry it. The copy is the one thing that leaves the phone. Cost: a short pause before each copy. A sweep that fails is logged and does not stop the copy.
- **"Adding the photo…" starts when the picked item arrives.** It shows before the system hands the file over, which takes seconds for a photo in iCloud, and it clears on every exit. A count keeps it on while a second pick is still running. Cost: none known. Device check item 2 confirms it.
- **A staged restore keeps its recordings and photos out of the cloud backup.** After the unzip, the app excludes the staged `audio/` and `photos/` folders. The app never flags the staging folder itself, because that folder becomes the archive folder at the swap. A flag on it could leave the database out of the cloud backup after a kill. Cost: the staged database can go into the cloud backup until the next launch, as it could before S4.
- **The backup tests run one at a time.** They are in one serialized suite. They zip whole archives on the test thread, and in parallel they starved a timing test in the extraction queue (`drainGivesUpAtItsDeadline`). Cost: the backup tests take longer; no assertion changed.

**The owner must see:**

- The delete dialogs for a memory or a session do not say that its photos go too.
- A photo whose stored file is missing shows an empty frame as a page header. A tile shows its letter.
- `PhotoShelf.load` has one failure string outside the plan's copy list: "Could not show the photos: {reason}".

**Why.** A life has faces and places. The person recognizes them by sight (P1). The person keeps the photos and decides which one leads (P2). The app shows only what the file says. The app never describes a photo and never guesses from it (P5). Photos stay on the phone, as audio does (data posture).

**Costs.** The app re-encodes every photo. Metadata does not feed any other feature yet. The schema is permanent once v13 ships. S4 builds storage and display, not the “one photo, one story” prompt.

## 2026-11-16 · The Timeline is a spine; a chapter is a tag, a "During" line and a bar on the life map

**Status:** Decided by the owner from mock-ups. Source: `docs/specs/2026-11-16-timeline.md`. Supersedes in part "The timeline groups moments into computed life periods" (2026-10-26) and "Archive structure: chapters → stories → moments" (2026-10-22).

**Decision.** The Timeline is one spine of moments with gaps that follow the years between them. A pinned card shows the whole life as a strip, with a frame for the years on screen and a "During" line that names the chapters over those years. A moment shows one tag when the person put it in a chapter. One sheet, the life map, shows every chapter as a bar on a year axis and is where a chapter is renamed, dated or removed.

- A chapter is not a container on the Timeline. "Outside any chapter" and the chapter sections go away.
- A tag is what the person said about a moment. The "During" line and the life map go by stated years. A date overlap never makes a tag.
- A chapter shows years only when the person stated them. The span of its members is never shown as its dates.
- Periods are always computed from age. A chapter never replaces a period.

**Why.** The owner found that most moments sat outside every chapter, that empty chapters could not be removed, and that the Timeline read as a list. Marks on every row (a band or several tags) break with many chapters, because chapters overlap. One line and one map hold any number.

**Consequences.** `chapter.range` holds stated years only. The chapters in the owner's archive show under "Not placed in time yet" until the owner says when. The chapter rules in the audit data fixes spec move to S6. S6 is specified ahead of the ship order and of the two-week watch.

## 2026-11-17 · Extractor v7's rules in code: rulings made while building A2a

**Status:** Decided by the builder, for the owner to overrule. Source: PR #25 and `docs/plans/2026-11-16-extractor-v7.md`, "Rulings made while building A2a".

- **No stored match-key column and no migration.** Lookups read the rows of one type and compare keys in Swift. The tables are small.
- **Places, things and collections with one match key are joined once at launch, without a question,** as stories are (owner's call 1 of 2026-11-16). People and ideas are never joined by name. A pair is left alone when joining would drop a detail line or dates that differ, or when the side that would go has photos.
- **The owner's own name is never a person on the extraction path.** `findPerson` never returns the owner. A name the person typed or chose themselves still reaches the owner, so typing your own name never makes a second person.
- **A bad `about_ref` is cleared, not retried.** A retry costs a model call for a field that can safely be empty.
- **A place with no name leaves only the quote.** It is unnamed when it starts with "a", "an", "some" or "somewhere" and no later word is capitalised, so "A Coruña" is a name.
- **A group phrase is recognised by its wording in A2a.** The `group` mention kind waits for the v7 prompt (A2b).

**Open for the owner.** You draws the owner's life strip from moments linked to the owner as a person. New recordings no longer add that link. The strip should read every dated moment; that change is not made yet.

## 2026-11-16 · A feeling has no title, and "our parents" is not one person

**Status:** Decided by the owner. Source: `docs/specs/2026-11-16-audit-data-fixes.md`, "A2: titles", "A2: groups of people" and "A2: the Change sheet for what is not a moment".

**Decision.** A fact, a feeling or a goal shows as the person's quote, with no composed title. A phrase that names more than one person is a group: its card takes several people or "Leave it as said", and the phrase is never saved as a name for one person. A person's page lists the other names the app holds, each with "Remove". The Change sheet asks about a scene only for a moment.

**Why.** The owner said of a friend, "I think we had some of our most formative experiences together". The app showed it with the title "our most formative experiences together" and asked "Who was there". In the same story "our parents" raised "Who's this?", took one answer, and saved the phrase as a name for the owner's father.

## 2026-11-16 · Owner's calls on the audit data fixes

**Status:** Decided by the owner, except call 4. Source: `docs/specs/2026-11-16-audit-data-fixes.md`, "Owner's calls".

- Exact duplicates (stories with one title, "Ohio." beside "Ohio") are merged once without a question, with one notice.
- The owner's typed name goes to the model provider in the context packet.
- The second read does not offer memories that v7 finds and v6 missed.
- The second read's line shows on You only.
- A chapter shows no years until the person states them.
- Build order: A1 (stories), then A2 (extractor v7) after Photos merges, then A3 (the second read).
- **Open:** whether the second read may change a memory's kind. The owner wants to see v7's output on the whole archive first.

## 2026-11-16 · You is a portrait, and About leaves the Timeline (S3)

**Status:** Decided. Builds on the five-sections decision of 2026-11-15. Source: `docs/plans/2026-11-16-sections-you.md`, decisions 2, 4, 5, 8, 17 and 18, and the rulings made while building it.

**Decision.** You shows the name and birth line, the owner's life strip, one lead line, then "Who you are", "How it felt", "What you think" and "What you're hoping for". Every line with a recording plays only its own span.

- A fact shows on You when it has a detail link to the owner, or none. A fact detailed only to someone else shows on that page. A fact about only a hidden person or thing follows it and does not show on You. The app never names a hidden entity in "about". The app does not guess who a fact is about.
- A feeling says "about {title}" from its first non-owner detail link, else its first mention link. With no link, no line shows. Feelings and facts show no date. A goal shows "said in {month}" or "said in {month} {year}", the month its session started.
- The lead comes from facts, feelings and goals with own words and a recording. It changes each time You appears, stays across a refresh, never repeats in its part, and stays while a tag chip other than "All" is selected.
- Hide and Delete... move to a long-press menu on each line. Hide shows "Hidden." with Undo for 6 seconds, because a long-press Hide is easy to trigger by mistake. Delete asks first.
- A feeling's quote opens its memory page, and "about" is a separate link, so one kind of line behaves one way.
- A play error shows in ink with a red icon, to keep 4.5:1 contrast. A missing file reads "Could not play this: the recording could not be found."
- The About list leaves the Timeline. The summary keeps "and N things about your life".
- No migration. The portrait reads in batches, reads nothing until it is on screen, and refreshes when a session closes.

**Rulings from the final review (2026-11-16).** Each ruling has its cost.

- **A line from a heavy session never leads.** A line whose first telling is in a session with a disclosure or a wish to stop is not in the lead pool. It still shows in its part, with its play control. The app reads the heavy sessions in one batch, as the landing reads one session. Why: a disclosure must not show at title size with a play button each time the person opens a tab (PRINCIPLES, session arc and safety). Cost: the check is per session, so an ordinary line from a heavy session never leads either.
- **One slot for Undo and errors.** "Hidden." with Undo, a play error, and a failed hide, delete or undo show in one slot pinned at the bottom of You, above the record bar. It replaces "under the lead". One message shows at a time, and a newer one replaces the older. Undo stays in the slot while its 6 seconds last, also when an error replaces "Hidden.". A play tap clears only an old error. It never ends Undo. A second hide, or a delete that works, can replace an open Undo. VoiceOver announces each message when it appears, also when the same text appears again. The error for a page that could not be read keeps its own place. Why: an Undo the person cannot see is no safety net. Cost: one more floating element above the record bar while it shows.
- **A stale play error goes.** The slot clears when You disappears and when a new lead is picked. Cost: none.
- **Playback stops when its line leaves the page.** Hide, Delete and a tag chip that filters the line out each stop it. Cost: none.
- **Sort order.** Facts, feelings and goals sort by when they were told (the session start), then by the start of the span, then by id. A line with no recording sorts after the others, by id. Why: one stable answer. Cost: two lines told in the same second sort by the span start, not by meaning.
- **Chips come from listed facts only.** A tag only on a hidden, floating or unlisted memory makes no chip. Why: a chip must never lead to an empty part. Cost: none.
- **"said in" uses the Gregorian calendar in English.** Only the time zone comes from the device. Why: the copy is English, and a Buddhist-calendar year in English copy reads as wrong. Cost: a person whose device uses another calendar sees Gregorian years.
- **The owner is never an "about" target.** A feeling linked to the owner and to the lake reads "about The lake". Why: "about you" on your own page says nothing. Cost: none.
- **Timeline count and tag menu.** "N things about your life" counts visible facts, feelings and goals. The tag filter and "Show hidden memories" do not change it. While a tag filter is on, the summary leaves out the "and N things" part. The tag menu offers only the tags that at least one moment carries. With a filter on and no moment that matches, the empty state shows. A Timeline tag filter turns itself off when no moment carries its tag any more. Why: Timeline must not claim content that it does not show. Cost: a tag used only on facts cannot filter the Timeline; it is a chip on You.
- **Screens built before the owner answered.** The screen tasks were built on the plan's defaults before the owner answered the plan's open questions (dates under feelings, when the lead changes, the strip as the link to the owner's page, hidden lines one way, facts about others staying on You until extractor v7). Cost: rework of the affected views and tests if the owner overrules a default.

**Why.** About held 62% of everything on one screen (audit F9), and the owner is a person too (F10). A portrait in the person's own words and voice serves P1 and P2. Showing only what the person said, with no guessed link, serves P5.

**Costs.** Most facts about other people stay on You until extractor v7 re-reads the archive and adds detail links. A fact about a hidden entity shows nowhere until the entity shows again. The lead changes less often while a person filters. No dark palette exists yet.

**Cost of Hide (read this before you hide a line).** Hide on You has no way back after its 6-second Undo, or after the person leaves the You root. No screen shows a hidden fact, feeling or goal again. "Show hidden memories" on Timeline shows only hidden moments. It does not show hidden facts, feelings or goals. A hidden fact, feeling or goal cannot be deleted, because no screen shows it. Lines hidden before this change are in the same state. A way back is a follow-up for the owner to place.

## 2026-11-15 · Five sections: Timeline, People, Places, Things, You

**Status:** Decided. Supersedes owner's call 4 of the UI audit of 2026-10-26 (a tab bar of Timeline, People, Sessions, Settings). Source: the owner's approval of `docs/specs/2026-11-15-five-sections.md`.

**Decision.** The app has five tabs and search. Timeline stays home. People is a grid of faces, Places is a map, Things is a shelf, and You is a portrait in the person's own words. Sessions is a labeled button on Timeline. Settings is a labeled button on You. The record bar sits above the tabs on every tab and names the page the person is on.

- The tabs ship first with the current lists inside them. Each section gets its own shape in a later step, when its data exists.
- A session started from a page records that page as its subject and opens with a question about it. The app links nothing the person did not say.
- A computed life period is named by age only ("Childhood", "Teens", "Twenties"). Any other name comes from the person.
- The person picks photos one at a time with the system picker. The app keeps a copy in its own folder, includes it in backup export, and keeps it out of the phone's cloud backup, as it does audio.
- The app may show an Apple map and send the place searches the person types to Apple. Lookups the app starts itself stay off.

**Why.** After a month of use, one screen carried everything and six unlabeled icons led away from it (audit F7, F9). Each kind of thing in a life needs its own way of being seen, and every one of them must lead back to telling (P1, P2). No screen may ask the person to complete a record (P9), and no inferred span, location or name may show as fact (P5).

## 2026-11-15 · A kept card's close can be undone

**Status:** Decided by the owner. Source: the review of PR #18 (`CardHandler.close`); `docs/specs/2026-10-26-cards-follow-ups.md`, rules 9 and 11.

When a kept card closes, the follow-ups nobody answered are dismissed. A card closes on "Done" and also when the person acts on another memory card, so follow-ups could go with no tap on them. The app now shows "{n} suggestions dismissed." with Undo for 6 seconds whenever a close dismissed something. Undo makes the follow-ups pending again and brings the card back.

Closes inside one 6-second window add up: one Undo takes all of them back. The close writes its dismissals in one transaction, and Undo writes its restores in one transaction, so a failure or a kill leaves every follow-up of that write as it was (PRINCIPLES 4).

**Why.** Unanswered follow-ups must not pile up in "Waiting for you": that backlog is what the UI audit removed. So the close still dismisses them. But a dismissal the person did not choose must be one they can take back (PRINCIPLES 9).

**Not chosen.** Leaving unanswered follow-ups pending: one leftover card for each kept memory. Keeping the silent dismissal: no way back.

## 2026-10-26 · Filler words are hidden in quotes on lists and pages

**Status:** Decided by the owner. Source: `docs/specs/2026-10-26-ui-audit.md`, call 1 and finding F12.

Quotes on lists, entity pages and About hide filler words ("um", "uh", "like", "you know") and repeated words. The stored transcript does not change. The memory page and the audio keep every word (PRINCIPLES 1).

## 2026-10-26 · The timeline groups moments into computed life periods

**Status:** Decided by the owner. Superseded in part: for a chapter's range, by "2026-11-18 · S6c: chapters are names with stated years". A named chapter no longer takes the place of a period, and a chapter's range no longer comes from its members. Source: `docs/specs/2026-10-26-ui-audit.md`, call 2 and findings F2–F3.

The timeline reads life periods from the dates and the owner's age, for example "Growing up · 2004–2012". Each computed period shows as a guess (PRINCIPLES 5). A chapter the person names replaces the period it covers. "Outside any chapter" goes away.

## 2026-10-26 · Extractor v7 changes to existing memories are suggestions

**Status:** Decided by the owner. Source: `docs/specs/2026-10-26-ui-audit.md`, call 3.

Extractor v7 re-reads the existing memories. Each change it finds (a new title, a link to a person, "about you" in place of the owner's name) is a suggestion the person approves. No change is applied silently (PRINCIPLES 9).

## 2026-10-26 · A labeled tab bar replaces the floating icons

**Status:** Decided by the owner. Source: `docs/specs/2026-10-26-ui-audit.md`, call 4 and finding F7.

The app's top level is a tab bar with labels: Timeline, People, Sessions, Settings. The six unlabeled floating icons go away.

## 2026-10-26 · Follow-ups stay on the memory card

**Status:** Decided by the owner after a month of use. Source: `docs/specs/2026-10-26-ui-audit.md`, finding F1.

A follow-up (a domain tag, a story hint, a collection hint, an entity) never appears as its own card. After Keep, the memory card stays and shows its follow-ups as optional chips. A separate card read as random because nothing tied it to its memory (PRINCIPLES 9).

## 2026-10-25 · The interviewer speaks briefly, never over the person, and never improvises on safety (M8)

The app speaks its fixed lines and short model reflections in a settle-in session. A quick story stays nearly silent. Any speech from the person stops the app at once. The app's own words are kept apart from the person's in the transcript and never become a memory.

- A spoken turn waits for the safety check in the interviewer's own reply, and for the extractor's flags when they come first. Only the extractor moves the arc. This holds for every turn after the opening, bank questions included.
- The next question after a quiet spell stays on screen. It is not spoken.
- The model is `claude-haiku-5-5`. Echo cancellation runs on capture, and the recording sound changes with it; speech is not limited to headphones.
- The disclosure card does not change. The app speaks the 988 line only for present danger.
- The "About the app" line says that the person's words go to Anthropic as text.
- No "mm" acknowledgements in V1. The voice is the best installed system voice. "Lifeline speaks" is on by default.

Why: P1, P2, P3, P6, P8 and P9. See `docs/specs/2026-10-25-m8-interviewer.md`.

## 2026-10-25 · Memory kinds and domains: moments on the timeline, everything else by what it is about (M7)

**Status:** Decided. Closes "Open · Memory kinds and domains". Source: the owner's answers to the M7 spec, `docs/specs/2026-10-24-m7-elements.md`.

**Decision.** A memory has a kind: `event` and `other` are moments; `fact`, `feeling` and `goal` are not. Non-moments leave the timeline's shelf and chapters and are never asked "when?". The resolver still stores their ranges and the timeline hides them. The archive gains four entity kinds with pages: People, Places, Things, Ideas. Possessions, buildings, vehicles and objects are Things. Non-moments become details of an entity, or of the person ("About you"). People become entities with one link table for every kind; no parallel path for people. An entity page shows its details first and its moments below. The app never asks for a date on a Thing or a Place; the person can add one. An idea's title is the person's own words or "An idea you mentioned on {date}". Curiosity about entities asks for a scene, never for a date or an evaluation. Domains are free-text tags with no fixed list.

**Why.** Much of what a person says is not a moment. Forcing it onto the timeline fills the shelf with things that never get a date and makes the app ask the wrong question (Principle 2). A composed idea title or "Do you still think that?" interprets and evaluates a life (Principle 1).

**Consequences.** M7 ships as two PRs: PR A (kind column, migration v9, About section, "What is this?") first, then PR B (entities, migration v10, prompt v6). The person split is the largest task of PR B. `place`, `memory_place` and `memory_person` stay one release and are read nowhere; v10 drops them.

## 2026-10-24 · Copies of the archive stay out of the phone's cloud backup

**Status:** Decided. Source: Claude review of #9 (Backup.swift).

**Decision.** Every `.lifeline` file the app writes is excluded from the phone's cloud backup: an export, a safety copy before a restore, and the replaced archive zipped at launch. The audio folder is already excluded, so a copy must not send the same audio and transcripts out by another path.

**Why.** Data posture (V1): content leaves the device only when the person shares it. A copy in Files is on the device. The person moves it off the phone by sharing the file, which is an explicit act.

**Consequence.** A copy left in Files does not protect against a lost phone until the person shares it to iCloud Drive or another place. The export screen must say so.

## 2026-10-22 · Preserve first, organize later (review follow-up)

**Status:** Decided. Source: external design review of the V1 spec, M1 to M4 plans, design canvases and Swift code; mock-ups R1 to R9 on the design canvas.

**Decision.** The recording is the product; organization is optional. Finishing a session never waits for extraction: persist, show the landing, let sorting finish in the background with durable retries. Extracted memories are drafts until reviewed; accepting a memory approves its organization, not its survival. Principle 9 added to `docs/PRINCIPLES.md`.

**Consequences for M4 and later.** `stop` must not block on the extraction hook. The session screen gets two views: Listen (default; prompt, status, pause, finish, a small "N possible memories" count that never scrolls the screen) and Transcript & memories (the review view, opened by choice). The landing says "Your recording is saved", shows a few moments with play, and makes "Done for now" the default with review optional. Per-memory keep / private / let go is no longer required at landing; it moves to the review view and the privacy controls.

## 2026-10-22 · Session length: quick story or settle in; no automatic stop

**Status:** Decided.

**Decision.** Two equally valid ways in: "Tell a quick story" (a few minutes, one memory) and "Settle in" (longer, prompts on offer). The quick story is also the shape of a daily habit; the home screen invites "today's story" without streaks or counters. The 60-minute hard stop is replaced by a gentle wrap-up at the planned length and an explicit "keep going", unless a real recording limit forces a stop. `ArcConfig.hardStopAt` becomes a wrap-up prompt, not a stop.

## 2026-10-22 · Correction is a first-class action

**Status:** Decided.

**Decision.** Memory cards offer Keep · Change… · Dismiss. "Change…" offers the title, who was there, when it was, which part of the recording, and "just tell me" (spoken correction, later). Dismiss has Undo and leaves the recording untouched; deleting recording content is a separate, explicit action. Accepting a memory does not confirm its inferred details: each inferred value carries a visible "Check this" tag (ochre plus a symbol or word, never reduced opacity) until the person settles it. Supersedes "Add / Not quite" on `MemoryCard` and the low-confidence fade.

## 2026-10-22 · Archive structure: chapters → stories → moments; years as a lens

**Status:** Decided.

**Decision.** A session is when you recorded. A moment is a scene you described, with its original audio. A story connects related moments, possibly across sessions. A chapter is broader life context. Years and months are an optional chronological lens, shown only when they help (three stories in a year: show the stories; forty: offer seasons or months). Collections remain the thematic thread across chapters ("Family trips"); a moment can sit in its story and in a collection without being copied. Chapters may overlap. The person approves any composed story or chapter title. Every level has "Listen at this level": a playlist in the person's voice (life: chosen highlights; chapter: selected stories; story: its moments; moment: the audio). Narrated assembly comes later. Pinch-to-zoom is an enhancement; Life / Chapter / Year controls, tappable headings and a clear back path are the baseline.

**Fuzzy time, progressively disclosed.** List: "During the Boston years." Detail: "Probably 2011 to 2013." Editor: likely and possible bands with evidence. Undated stories look as valuable as dated ones.

**Consequences.** The data model gains `story` (id, title, chapter_id?) and `story_moment` (story_id, memory_id, order). "Memory" in code is the moment. The extractor's `same_as_memory_id` becomes "belongs to story"; segment reconciliation (below) feeds it.

## 2026-10-22 · Privacy controls named by effect; local-only is chosen before recording

**Status:** Decided.

**Decision.** Replace the single word "private" with four controls: Hide from timeline (keep recording and memory; remove from everyday browsing); Exclude from AI processing (no future processing or context use; cannot unsend); Share… (exact content and recipients); Delete… (the selected recording content and its derivatives, with confirmation). A session that must never leave the phone is chosen before recording ("Local only") and cannot be switched on afterwards. The copy "nothing is saved until you say so" is wrong and is removed everywhere; saving is continuous. A usable backup-and-restore path (audio included, explicitly) ships before anyone beyond the owner uses the app.

## 2026-10-22 · Pipeline changes from the review

**Status:** Decided; scheduled into M4/M5.

- Finish recording independently of extraction (see Preserve first).
- Separate audio segments from story boundaries: a silence threshold ends a segment; one story may span several segments. Accumulate or reconcile related segments before presenting several cards.
- Budget the context packet by tokens and relevance, not by fixed caps per table. Select relevant memories and people within a total budget.
- Treat pending (unreviewed) stories as context, so someone who never touches the screen still gets continuity and duplicate handling.
- Evaluate cheaper extraction configurations on consented sessions against invented details, fragmentation, missed memories and editing effort before choosing a default.
- Deletion must handle overlapping memories that reference the same audio and preserve playback offsets.

## 2026-10-22 · Readability and interaction fixes

**Status:** Decided.

Keep the palette, serif titles and the tree-ring icon. Do not fade uncertain memories. Pair ochre with a word or symbol. Reduce small uppercase labels and metadata on primary screens. Serif for titles and chosen quotes; a highly readable body face for transcripts. Chips must wrap (replace the `HStack` in `FlowChips`). Every swipe or long-press action has a visible alternative. Validate large text and VoiceOver before testing with older relatives.

## 2026-10-22 · Roadmap: minimal photo prompt pulled forward; playback tested early

**Status:** Decided.

Choose one photo and tell its story, with no clustering or face work, moves into Phase 1.5. Simple playback of an accepted story (the first payoff) ships before narrated chapter assembly.

## 2026-10-22 · Closing question after a hard session

**Status:** Decided (closes the open item).

Neutral by default ("Thank you. That's enough for today."). Never a question about the person or loss just discussed, and never framed as "something lighter".

## 2026-10-21 · Platform: iOS native app + stateless server; web viewer deferred

**Status:** Decided.

**Decision.** The capture app is native iOS (Swift/SwiftUI). The interviewer and extractor run as a stateless server. A read-only web viewer for replay and sharing is deferred to Phase 3.

**Why.** Long sessions (30 to 60 minutes) happen with the screen off; iOS Safari and PWAs suspend audio capture in that state. On-device speech-to-text with word timestamps exists on iOS and does not in the browser. Hours of audio in browser storage is fragile (quotas, Safari eviction). Phase 2 props (PhotoKit, Vision, Core ML) are native only. Web wins for viewing and sharing, which is Phase 3's surface.

**Alternatives considered.** Web app or PWA (fails on background recording and storage). React Native/Expo with native modules (saves some Swift but still needs native audio and speech plumbing; adds a layer between us and the parts that matter most).

**Consequences.** V1 is iPhone only. The server is platform-agnostic, so extraction and resolver work can start in Python against voice memos before any Swift exists.

## 2026-10-21 · Voice pipeline: cascade behind a `VoiceSession` interface

**Status:** Decided.

**Decision.** V1 uses VAD → streaming STT → text-model interviewer → TTS. A `VoiceSession` interface (events: speechStarted, transcriptPartial, transcriptFinal, userPaused; commands: say, acknowledge, interrupt) hides the implementation so a realtime speech model can replace the cascade later.

**Why.** Cheaper per minute; the transcript is a first-class artifact we need anyway; turn-taking logic stays in our code. What we give up (prosody awareness, low-latency backchannels, barge-in) is the case for the later swap.

**Turn policy (initial values, for testing).** A ~1 s silence triggers a fast end-of-thought check. Complete thought: reply after a 1 to 2 s grace. Unfinished: wait up to 6 to 8 s, then a soft acknowledgement only. The classifier runs on-device or under ~300 ms.

## 2026-10-21 · Data posture (V1)

**Status:** Decided for V1; revisit before any release beyond family.

**Decision.** Audio, transcripts, timeline and people stay on the device. The server is stateless: it receives a transcript segment plus a context packet and returns a result, and persists nothing. Sharing is explicit. A memory the person chooses to "let go" is deleted with its audio.

**Open for later.** On-device vs server LLM; end-to-end encryption for shared bundles; ownership after death.

## 2026-10-21 · Photos in V1: manual tagging, no face model

**Status:** Decided.

**Decision.** The person picks favorite photos; the app reads EXIF date and location and derives clusters; the person names who is in each photo ("who's this?"). No face embedding model in V1.

**Why.** PhotoKit does not expose People, Memories or Trips. Apple's face-identity request is private API. Cross-age face matching (childhood prints to adult photos) is where off-the-shelf embeddings are weakest. Manual tags build the labeled set needed to evaluate a model later.

## 2026-10-21 · Phase order

**Status:** Decided.

Phase 1 personal timeline → Phase 2 props (photos, then music) → Phase 3 family sharing.

## 2026-10-21 · V1 scope: listen-only app, no server, recording study deferred

**Status:** Decided. Design: `docs/specs/2026-10-21-v1-listening-app-design.md`.

**Decision.** V1 is a listen-only iPhone app. It records, transcribes on the device, extracts candidate memories, places them as ranges, and lands every session. It does not speak. `VoiceSession` ships as `ListenOnlyVoiceSession`; `say`, `acknowledge` and `interrupt` are no-ops that log. The first user is the owner, telling their own life. "Hand the phone over" is not in V1.

**Why.** The owner wants to record real sessions on their own phone as soon as possible. Real sessions calibrate the extractor better than a study does. Every interface keeps the full voice interviewer reachable.

**Consequences.** The recording study (`docs/experiments/recording-study.md`) runs after V1 is usable. The `eval` command keeps its scoring ready. Closes "Open · First user".

## 2026-10-21 · No separate server in V1; LifelineKit is the later server

**Status:** Decided. Supersedes "Open · Server language".

**Decision.** The app calls the Anthropic Messages API directly through an `ExtractionService` protocol. Domain, store, extraction, resolution and session-arc code live in a Swift package, `LifelineKit`, that compiles for iOS and macOS. A `lifeline` macOS CLI runs extraction and resolution over exported sessions. When a server is needed, it is LifelineKit compiled as a Swift server executable, and the app switches to a `RemoteExtractionService` conformer.

**Why.** One language, one package, no second runtime to keep in step. Switching to a server later is one conformer and one line in the composition root. The data posture holds: audio never leaves the device; only transcript segments and a context packet go to the model.

## 2026-10-21 · Model provider: Anthropic Console API

**Status:** Decided.

**Decision.** Extraction calls the Anthropic Messages API with an API key, billed to the Console. Default model `claude-opus-5-5`, adaptive thinking at low effort, structured output. Model and effort are configuration.

**Why.** A Claude Max subscription does not cover API calls. The Agent SDK bridge was rejected as too heavy for one extraction call per segment.

## 2026-10-21 · Typed context at the start is allowed

**Status:** Decided.

**Decision.** An optional "About you" screen at first open takes name, birthday, birthplace and free text. Every field can be skipped. Everything is editable in Settings. Typed values carry origin `typed`. The free text goes into the fixed part of the extractor's context packet.

**Why.** The start is the easy place to give context, and the owner wants that to be easy when the context is useful. A birth date lets age anchors resolve from the first session.

**Consequences.** This is the one exception to "no form-style questions for baseline facts". In a session the rule holds. A stated date that disagrees with a typed date shows a "which is right?" card; the app never picks silently.

## 2026-10-21 · Disclosure card text (V1)

**Status:** Decided for V1; the owner may revise the words at any time.

**Decision.** On a `serious_disclosure` flag the app shows this fixed card and nothing improvised: "Thank you for telling me that. You can stop here, or keep going. It is your choice. If you need to talk to someone now, call or text 988 (Suicide and Crisis Lifeline, US)." The crisis line is a locale-keyed configuration value; V1 ships the US line only.

## 2026-10-22 · API key lives in the Keychain, typed into Settings

The Anthropic Console key is entered in Settings and stored in the device Keychain (after first unlock, this device only). It is never in a build setting, an xcconfig, the repo or a log. The CLI reads `ANTHROPIC_API_KEY` from the environment instead.

Why: nothing secret in the build; the owner can rotate the key without a rebuild; the same code path serves a second phone later. Cost: a first-run setup step, and sessions before the key is added are recorded but not sorted (they are retried by the CLI or a later re-run).

## 2026-10-23 · M4 ships the landing, correction and durable sorting; the rest of the review waits for M5

What M4 ships from the 2026-10-22 review: finishing never waits for sorting (a launch-time worker picks up anything left pending); the Listen and Transcript & memories views; Keep / Change… / Dismiss with Undo and "Check this" tags; the light landing with Done for now as the default, Hide today and Delete today's recording; the disclosure flag with past and present kinds, a fixed card, and every organizational prompt (who's this included) suppressed in a heavy moment; visibility as two flags, `hidden_from_timeline` and `excluded_from_ai`; pause and resume; two ways in at first open and on the timeline.

Numbers chosen here, all configuration: a quick story has no time element; settling in is planned at 30 minutes with a 10-minute grace between wrap-up offers and the next question offered after 6 seconds of quiet; the recording limit of 3 hours is the one automatic landing.

Waits for M5: span-level deletion with offsets preserved (M4 deletes whole sessions and single memories); the privacy screen with Share and Local-only; stories and `story_moment`; reconciliation of related segments and the token-budgeted context packet; backup and restore; "Which part of the recording" and "Just tell me" on the Change sheet, shown disabled so the shape of correction is visible.

Added 2026-10-23 after the M4.1 device run: **duplicates among memories already kept.** M4.1 only compares a new card with one earlier memory, so three tellings of the same moment can sit on the timeline. M5 adds a pass over existing memories: the matcher ranks pairs, the extractor is asked in one batch which pairs tell the same moment, and each agreed pair becomes an "Are these the same?" card in Waiting for you with Play on each, Same story and Keep separate. A retelling that matches more than one memory names them all ("Same as X and 1 more?") and Same story merges the group into the oldest with one receipt, so Undo takes the whole thing back.

Why: the review's "preserve first, organize later" changes the landing and the session more than the data model; shipping those first lets the owner feel the new shape before the model grows. Cost: a memory told across two sessions goes with the first one deleted until span deletion lands.

## 2026-10-23 · V1 is one person's app: "protect" waits, backup does not

**Status:** Decided (owner).

The owner is the only user of V1. The privacy screen (Share…, Local-only before recording), span-level deletion with offsets preserved, the two disabled rows on the Change sheet and the in-app extractor re-run are not needed for V1 and wait until someone else uses the app. Hide from timeline, Exclude from AI processing and Delete (session or memory) already exist and stay.

One item is kept out of that list: a plain backup. Every recording and its derivatives live only on the phone, so a lost phone is a lost archive, which breaks "preserve first" for one user as much as for many. A one-tap export of the database and the audio to Files or iCloud Drive, with a restore path, is scheduled as a small task after M5, not as a milestone.

M5 is "organize" (`docs/specs/2026-10-23-m5-organize.md`); there is no M6 "protect" in V1.

## 2026-10-23 · Same story is offered, never applied; dates are stated, never inferred by the app

On the second day of the M4 build a story told in two recordings became two memories: the extractor's `same_as_memory_id` was never acted on and the packet only carried the current session's memories. A memory with no anchor had no way to get a date. M4.1 adds the moves the person can make and a suggestion they confirm.

**Decision.** Retrieval by on-device sentence embeddings (Apple's NaturalLanguage, cosine over `title. quote`) finds the nearest earlier memories across all recordings; they ride in the extractor's packet marked `related`. The extractor decides whether a segment retells one of them; a strong on-device match alone is also enough to put "Same as X?" on the card. The person decides: Keep stays the default and primary; "Same story" is one tap and undoable for six seconds. A merge is one memory with several audio spans (the V1 spec's `memory_span`); stories in M5 can group memories without undoing it. Merging into a resolver stand-in makes it real: the telling becomes its first span and `created_from_candidate_id` is set, so a memory with a nil candidate is only ever a stand-in. Undo is offered for six seconds and is refused if the target changed in any way since the merge; both merge and undo are single transactions. "Tell me when" writes a year, an around-year, a between, or an age with origin `stated`, shown as said; the resolver and the relative questions treat a stated range as settled. A memory excluded from AI is never embedded or suggested; a hidden one is never suggested on a card.

**Consequences.** Migration v7 (`memory_embedding`, span `title_text` and `candidate_id`); extractor prompt v4; deleting a recording removes only its spans, and a memory with a telling elsewhere survives; the Change sheet gains "Same as another memory…" and "Tell me when"; shelf rows show "Add a date" and "Add to a collection" inline. Thresholds (retrieve 0.55, suggest 0.80) are starting points to tune on the owner's recordings. Embeddings for earlier memories are backfilled in a detached launch task before the sorting worker runs, per model, not on the main actor. "Between two years" displays in the app's year-span style ("1996–99"). Spec: `docs/specs/2026-10-23-m4.1-same-story-and-when.md`.

## 2026-10-23 · Steady: sorting is visible and restartable, a copy is a file the person owns, a telling can be trimmed

After M5 the landing said sorting was still going on and the timeline said nothing; the phone held the only copy of everything; the Change sheet promised two corrections it could not do.

**Decision.** One quiet line on the timeline says what is still being sorted ("Still sorting 2 moments from today's recording…"), that the duplicate pass is checking for repeats, that sorting stopped ("Not sorting right now", Try again), or that a key is missing (the line opens Settings). The worker can start again: a saved key, the foreground, Try again. Hidden recordings count; deleted ones do not. "Your copy" in Settings exports one `.lifeline` file (a zip: the database copied through GRDB's backup API after a checkpoint, the audio, the pause log, a manifest; never the key) and restores one: the app writes a safety copy of what is on the phone to Files first, stages the copy, and applies it at the next launch before the database opens; a copy with a newer schema is refused, an older one migrates on open. "Which part of the recording" moves a telling's start and end to word boundaries within its segment, one part at a time for a telling told across a pause, and rewrites the card's span so Separate agrees later; Undo stays until the sheet closes. "Just tell me" waits for the interviewer. Two tests that flaked on the clock and on a timestamp tie are deterministic.

**Consequences.** ZIPFoundation 0.9.19 is the kit's second dependency (owner's call 0 in the spec; AppleArchive and a hand-written zip were the alternatives). `SortingReporter` is one more thing the composition root owns. Under `-uiTesting` the export skips the system share sheet, which a UI test cannot drive, and keeps the file in Documents. A restore never merges.

## 2026-10-23 · One moment, one story: pairs are asked, groups merge on one tap, stories ride on Keep in view

After M4.1 the owner had three memories of one friendship and a card that could name only one of them. M5 makes the same moment told any number of times one memory, a telling split by a pause one card, and related moments one story, without the app ever merging or grouping on its own.

**Decision.** A duplicate pass, after the embedding backfill at launch and a couple of seconds after every Keep, sends each memory's nearest few (cosine, `pairTop` 3, floor 0.55 only for a calibrated model) to a second structured prompt, the reconciler, in one batch of up to 20. Its `same_moment` and `same_story` verdicts become "Are these the same?" / "Sounds like one story" cards with Play on both sides; `different` is stored `separate` and never asked again, and so is Keep separate. Same story on a pair folds the newer memory into the older with one Undo. A card whose extractor names several memories (`same_as_memory_ids`, prompt v5) says "Same as X and n more?" and merges them oldest-first under one receipt, after the person checks the list. A segment that carries on a pending card (`continues_candidate_id`) grows that card ("+ 1 segment") instead of making another; Keep writes one memory whose later spans record what they continue (`continues_order`), and a continuation that arrives after the card was answered is an ordinary card. Stories are rows the person can rename, split, move into and take out of; the extractor proposes membership as a line on the card ("Part of: X", "Not part of it" one tap away) and a title as a hint card; Keep includes what the card showed. A story ref the model invents is minted into an id when stored, and a story with one visible member is not a group. Separate this telling turns a later telling back into its own memory, continuations and the anchors only it named along; a date the anchors gave goes with it, a date the person typed stays. The extractor's packet gains the session's pending cards and stories and a 6000-token ceiling (characters ÷ 4) that drops whole entries from the least relevant section first, never the profile text, never a section's first entry.

**Consequences.** Migration v8 (`story`, `story_moment` unique on memory, `duplicate_pair` cascading with its memories, `memory_span.continues_order`); prompts `extractor.v5.md` and `reconciler.v1.md`; a merged pair's row goes with the folded memory, so undo writes it back open; a resolver stand-in never outranks a real memory of the same session when a group is ordered; under `-uiTesting` the pass also writes its log next to the test database. The timeline's "Waiting for you" identifier moved to the section header: a List lays the card stack out as rows and an identifier on the stack replaced every card's own. Thresholds and the budget are starting points; the owner's device run decides them.

## 2026-10-23 · Quick story and settle in differ in shape, not in length

The owner's words: one is answering a prompt, the other is more of a conversation. A quick story is one prompt, finished when the person is done, with nothing about time on screen however long it runs. Settling in offers the next question when the room goes quiet after a story, and a gentle wrap-up with "Keep going" at the planned length. Nobody is stopped for talking longer than expected. Supersedes the entry below where they differ.

## 2026-10-23 · Sessions are short by default; the timer is a backstop

The owner's sessions run a few minutes and that is the intended shape. A session ends when the owner taps "Let's leave it there". The 40-minute wind-down and 60-minute hard stop from the design become a quiet backstop: a one-line nudge at 55 minutes and the summary opening by itself at 60. No screen shows session length as a goal. The spec's `middle` stage is dropped; stages are open, windDown, ended.

Why: the design was written imagining long oral-history sittings; real use is lighter, and every session must still land. Revised the same day by the review's "no automatic stop": the planned length brings a wrap-up offer with an explicit "Keep going"; the only automatic landing is a real recording limit. See the M4 plan (revised).

## 2026-10-23 · Direction: a short daily activity that builds over time

The owner's picture of the product (2026-10-23): a few minutes a day, one story at a time, with the timeline growing over weeks rather than being filled in one long sitting. Not a milestone of its own yet. It shapes what follows: each session opens with one fresh question (M3, done); the summary ends with one line for next time (M4); the spoken interviewer, when it comes, asks for one scene and stops. No streaks, counters or reminders that turn it into a chore; the principles rule out pressure. Open: whether a gentle daily nudge belongs in V1 at all.

## Open · Memory kinds and domains (closed 2026-10-25, see M7 above)

A later version will sub-divide memories by kind (fact, feeling, goal or intention, event, other) and by domain (relationships, health, education, travel, work, more). V1 ships one memory type and keeps the seam open: the candidate payload is JSON so a new extractor version can back-fill, no V1 code or copy assumes a memory is an event, and collection and chapter hints stay free text. Design after V1 has real sessions.

## Open · First user (closed 2026-10-21, see V1 scope)

Is the first user the person telling their own life, or an adult child interviewing a parent? Changes whose timeline a session writes to and whether "hand the phone over" is in V1. Default for now: the person's own life; design the session so handing over is a small change.

## Open · Server language (closed 2026-10-21, see No separate server in V1)

TypeScript or Python. Python is the natural home for the recording experiment and extraction prototypes; TypeScript matches the owner's web background. Decide when the server is created; the experiment can start in Python regardless.

## Open · How much the app may write

Verbatim quotes assembled into chapters, or prose the app composes in the person's style? The principles favor verbatim; replay narration may need light stitching. Decide with real transcripts in hand.

## Open · Closing question after a hard session (closed 2026-10-22, see above)

Unrelated by default, or tied gently to the memory? Decide after the recording study.
