# Decision log

One entry per decision. Newest first. Status is Decided, Open, or Superseded.

## 2026-11-18 · A photo story's photo goes on the pages of its people

**Status:** Decided. Parts 1 to 4 of the spec are built on the branch `photo-people`: part 3 is “Done” and “Edit”, part 4 is several photos at one time. The branch is not merged. Nobody has run the device check. The open items for the owner are at the end of this entry. This entry changes the 2026-11-18 photo card entry below. It reverses one rule of that spec: “a page link is always the person’s tap”. It also reverses point 4 of that entry, “Photos do not move with a name”. Part 3 reverses the rule of that entry that the card has one layout (spec part 3, point 11): “Also show this photo on” has two layouts, open and done. The owner asked for it.

**Source:** `docs/specs/2026-11-18-photo-on-people-pages.md` (approved by the owner on 2026-11-18, approach A) and `docs/plans/2026-11-18-photo-on-people-pages.md`, decisions 1 to 18. One migration (`v16`). No new network call.

**Why.** The owner told a photo story about a person two times on the phone. Each time, the person’s page did not show the photo. The card waited for a tap on a chip. The owner’s rule: the app can make an assumption, but it must say that it made it, and the assumption must be easy to change.

**Decision.** When the owner keeps a moment of a photo story, the photo goes on the page of each person the moment names. The card shows which pages the story chose. One tap takes the photo off a page. The app never reverses a choice the owner made. When the owner moves a name to another person, a photo the story put on the first page moves with the name.

- **The chosen approach: A, store the fact.** `photo_link.origin` is `story` for a link a photo story made, and null for every other link. `photo_page_declined (photo_id, entity_id)` records each page the owner took a photo off. The card can say “added by this story”, and a move never removes a link the owner made.
- **Not chosen: B, store nothing.** The write adds the photo only for the first kept moment that names the person. The card cannot tell the story’s choice from the owner’s tap, and a move must either remove the owner’s photo or never remove one.
- **Not chosen: C, offer, do not add.** The card puts the people’s chips first with “Add to all {n}”. It does not fix the reported problem: the owner must still tap after each story.

**The eighteen decisions of the plan.**

1. The migration is `v16`. It follows `v14` (photo story) and `v15` (people and contacts). If another `v16` reaches `main` first, this one gets a new number before the PR.
2. `photo_link.origin` is text. `story` marks a link a photo story made. Null marks every other link. An owner’s tap never writes `story`.
3. `photo_page_declined` has both columns as its primary key. Each column references its table with `on delete cascade`.
4. Every public removal of a photo from an entity’s page is the owner’s action, so it records the decline. This covers the card’s chip and the page’s own photo row.
5. Every public add of a photo to an entity’s page is the owner’s action. It deletes the decline for that pair and writes a null origin.
6. Only the Keep of a card writes page links. “Same story” writes none. The people of that memory show as empty chips.
7. A person is skipped when the person is the owner, when the entity is hidden, when the page holds the photo, or when the pair is declined.
8. The link goes through the existing link write. The photo is last in the page’s order, and it is the key photo on a page with no photo.
9. “Remove the photo from this story” (`letGo`) deletes the photo’s `story` links in the same write, but only when no other session points at the photo.
10. The move acts only when the session of the moved memories has a subject photo and those memories hold it.
11. Undo of a move restores the photo links only where they are still as the move left them. A link the owner changed after the move stays.
12. The chip’s VoiceOver value is “added by this story” for a `story` link, “added” for the owner’s, and “not added” for none.
13. The UI test seed keeps its photo story through the real Keep write, so its person chips start filled. Tests that started from an empty person chip changed their first step.
14. Moments kept before this build get no link. There is no backfill.
15. Part 3: `v16` also adds `session.photo_pages_done`, boolean, not null, default 0.
16. Part 3: in the done state the card keeps a chip the owner emptied on screen until the part is closed again or the card is built again when the owner leaves the screen. The view model holds the set of such pages. The set is not stored.
17. Part 4: the picker's selection is `[PhotosPickerItem]` with `maxSelectionCount: 20` and `selectionBehavior: .ordered`. The app receives and adds the photos one after the other, never at the same time, so memory holds one image.
18. Part 4: UI tests cannot drive the picker. The launch argument `-uiTesting-pickPhoto <path>` keeps its meaning. A new launch argument, `-uiTesting-pickPhotos <path>,<path>`, gives several files to the same flow.

**The spec’s calls made without the owner.**

1. People only. Places, things and ideas stay a tap.
2. Not the owner’s own page. The “You” chip stays a tap.
3. An `assumed` name link also places the photo.
4. The chip looks the same for both kinds. The line under the heading and VoiceOver carry the difference. The chip has no “Assumed” mark.
5. Removing a moment from the photo does not take the photo off the people’s pages.
6. Moments kept before this build get no link.
7. Approach A, with one additive migration.
8. Part 3: the button reads “Done”. The state is stored for the story, in the same migration.
9. Part 3: a filled chip tapped in the done state stays on screen, empty, until the part is closed again.
10. Part 4: the limit is 20 photos. The picker is the system picker. The app asks for no photo permission.
11. Part 4: not for the start of a photo story.

**The card.** The view reads `PhotoStoryCard.pagesLine` and `Page.stateValue`. It holds no rule and no copy of the text. While a page holds the photo by a story link, the line under “Also show this photo on” reads “The people in this story have this photo on their pages. Tap to take it off, or to add it to another page.” With no such page, it reads “Tap to add. Tap again to take it off.” The chip’s remove stays on its old path, `PhotoLibrary.remove`. That path records the decline and deletes the file when the page was the photo’s last home.

**Rulings made while building (2026-11-18).** Each ruling has its cost.

- **Every name link counts, `detail` as well as `mention`.** The spec says “each person the moment names”. A kept fact about a person in a photo story is about that person. Cost if wrong: one filter in one query.
- **There is no undo of a Keep in the kit.** A deleted memory leaves the photo on the people’s pages, as the spec’s edge case for a removed moment says. The owner takes it off with the chip.
- **`PhotoStoryReader.removeFromPage` is not added.** The app removes a photo from a page through `PhotoLibrary.remove`, which records the decline and deletes the file. A second path could leave a file with no row. The plan’s line “the chip’s remove goes through `removeFromPage`” is void. Cost if wrong: none; one path remains.
- **A move removes the first person’s story link only when no memory that holds the photo names that person now, in any session.** The plan said “no memory of that session”. One photo can be the subject of two stories, and the spec forbids removing a link another story made. The same rule applies when Undo removes a link the move added. Cost if wrong: a photo stays on a page a little longer.
- **The move adds to the new person only (`only:` on `linkToPeoplePages`).** A plain call would add the photo to other people the moment names who lack it, against decision 14.
- **The session’s page reads its rows again after a move on a card there, and after its Undo** (`CardHandler.onPeopleMoved`, set by `SessionDetailViewModel`). Without it, the photo card above a kept card kept the chips from before the move. The landing already read its rows again. Cost: one more read after a move on the session’s page.
- **`shownPageGroups(keeping:)` takes `Page` values, not ids (part 3).** The kit puts back an empty copy of a kept page that left `pageGroups`: a page listed only because it held the photo. The spec says a chip must not disappear under the finger. The id-only interface was a defect of the plan. The card draws the part while it shows a kept page (`showsPagesPart(keeping:)`), also when that page was the card's only page. The open state does not change. Cost if wrong: one signature and one view-model field.
- **The open part reserves the height of the tallest line under the heading (`PhotoStoryCard.allPagesLines`).** The line changes when the last chip the story chose is taken off. With the height reserved, no chip moves under the finger.
- **A story link to a hidden page is refused in the link write itself, next to the declined check.** The Undo of a move therefore does not put the photo on a page the owner hid after the move (decision 7).
- **“Add a photo” is disabled while the shelf adds photos (part 4).** This applies on the three pages that add photos: an entity page, a memory page and You. It is the simplest rule, and the owner sees the count run. Cost if wrong: the owner waits for a pick to end before the next pick.
- **There is no `PhotoShelf.add(files:)` (part 4).** The flow adds the items one at a time between `beginAdding(count:)`, `finishedOne()` and `endAdding()`. A list of files would hold every temporary copy at one time.
- **`PhotoAddBatch` holds the count of a pick (part 4).** It counts the photos picked, the photos done and the failures. It gives the line “Adding photo {i} of {n}…” and, at the end, the one failure line.
- **The seed’s owner’s link to Maya is gone.** The photo story seed linked Maya’s page by hand after the Keep, which made the link the owner’s. Keep now puts the photo on Maya’s and Dad’s pages, so both chips start as “added by this story”. A page that held the photo before the story is in the device check. A new flag, `-uiTesting-photoStoryAssumedName`, adds “The ferry” to the first story: Sam, assumed, said “Sammy”. It is for the test of a moved name.

**Open items for the owner.**

1. **“Same story” writes no page link (decision 6).** A telling merged into an older memory does not put the photo on the people’s pages. Their chips are empty. Cost if wrong: the merge write calls the same function as Keep.
2. **The chip has no “Assumed” mark (call 4).** A photo that follows a guessed name looks the same as one the owner chose. The mark is on the memory’s people.
3. **Moments kept before this build get no link (decision 14).** The owner taps the chip for an older story.
4. **A kept fact about a person also places the photo** (the ruling above).
5. **After a kept memory is deleted, the chip still reads “added by this story”,** although no kept memory names the person.
6. **A restored link goes last.** After a move and its Undo, a photo that was the key photo is not the key photo when the page gained another photo meanwhile.
7. **Deleting a photo story leaves its photo on the people’s pages.** The link stays a `story` link with no story. “Remove the photo from this story” acts differently: it takes the story’s links away.
8. **A story link stays the story’s when the owner makes its photo the key photo.** A later move or photo removal takes it off the page.
9. **The Undo notice after a name move can sit below the screen for its 6 seconds.** The owner must scroll down to reach it. One fix is to pin it above the record bar.

The device check is `docs/plans/2026-11-18-photo-on-people-pages-device-check.md`. Its last part lists the small items the reviews deferred.

## 2026-11-18 · S6b: a pinned card with the life strip, a frame and a During line

**Status:** Decided by the builder. The owner can overrule each one. Source: `docs/plans/2026-11-18-timeline-card.md`, ledger `.superpowers/sdd/2026-11-18-timeline-card/rulings.md`.

**Decision.** The Timeline pins a card under its title. The card shows the whole life as a strip, from the birth year to now. Each dated moment is one tick. A frame covers the years of the spine rows on screen and moves as the list scrolls. One "During" line names the chapters whose stated years overlap the frame's years. A tap on the card opens the life map. The card asks for nothing and shows no count of what is missing (PRINCIPLES 9). It shows a chapter's years only when the person stated them (PRINCIPLES 5).

The eight builder's defaults:

1. The "Chapters" item stays in the Timeline's "…" menu. With no dated moment there is no card, and the life map must stay reachable.
2. The frame keeps its last years when no spine row is on screen (the waiting cards at the top, the shelf at the end). Before any spine row was on screen, the card shows no frame. When the spine's rows change and no row is on screen, the app clears the kept years.
3. A row counts as on screen when half of it is visible. Ruling R3 replaces the plan's second sentence of this default, "A row under the pinned card counts while it is in the scroll view's visible area". R3 says how the app measures this.
4. The visible "During" text is the word "During", the names joined by " · ", then "+N". VoiceOver uses the spec's sentence with at most two names and "and N more".
5. `LifeStrip` gains a choice of where a mark sits. The entity page keeps the middle of the band. The Timeline card uses the start of the range, as the spec says. The entity page does not change.
6. When two chapters are equally long, the earlier start comes first, then the name in alphabetical order. A chapter with no stated end counts as running to now.
7. The card is in the Timeline tab only.
8. One year on screen reads "On screen: 1999." Two or more years read "On screen: 1998 to 2003."

Rulings made while building:

- R3. A spine row is on screen when at least half of its frame is inside the list's own frame, measured with `onGeometryChange`. `onDisappear` clears it. The plan named two techniques and both were dropped. `onScrollVisibilityChange` reported "visible" and never "not visible" in this list. `onAppear` and `onDisappear` count a row hidden under the pinned card as visible, so the frame never moved. The app measures the frame of the SwiftUI list inside the pinned inset. That frame starts at the bottom of the inset, which is the card and 8 points below it. It ends above the record bar. The list's scroll view itself runs the full height of the screen, so the rows scroll under the card. A row under the card is outside the measured frame. A simulator probe confirmed this: the measured top was 239.7 points, and the card's bottom was 231.7 points. The area between the inset and the record bar is what "on screen" means to the person.
- R4. The "During" line decides how many names fit with `ViewThatFits(in: .vertical)` against a box one line tall. At accessibility sizes the box is two lines tall. The plan's horizontal form cannot allow a second line, because a horizontal fit measures the width of one line.
- Hysteresis. A row comes on screen when half of it is inside the list's frame. A row that is on stays on while any part of it is inside the list's frame widened by a slack at both edges. The slack is one point more than the most the card's height can change. The "During" line and the space above it make that change. Without the slack, the card froze the app. A row at the top edge turned on and brought a chapter into the "During" line. The taller card then covered the row, and the row turned off. The "During" line went, the card shrank, and the row turned on again. This repeated without end. The first rule in this build turned a row off when the card covered all of it. That rule still looped for a row shorter than twice the card's change (C1, final review). The rule is one pure function in the kit, `RowVisibility.isOnScreen`. A closed-loop test checks each row height from 1 to 400 points for three sizes of the card's change.
- R1, R2, R5 and R6 are process and test rulings. R1: the spine seed is not changed. So no UI test opens a dated story. R2: the docs are written in Task 6. The controller records the full run and the screenshots after the final review. R5 and R6: the test for the pinned card does not compare the card's top with its launch value. The large title collapses, and the card moves up with it. The test asserts that the card is hittable. It asserts that the card's top is not lower than at launch. It asserts that the middle of the first hittable spine row is below the card's bottom.
- R7 and R8 come from the final review. R7 records two known costs (below). R8 moves four small items to "After S6b" in the plan.

**Differs from the mock-up.** The mock-up `docs/design/TL_SpineStrip.dc.html` draws every tick the same. The card draws a guessed date as a hollow tick, so the shape, and not colour alone, shows that the date is a guess. The look is otherwise the mock-up's: an olive rounded frame, names in olive semibold, "+N" at the trailing edge.

**Why.** The card gives the person one look at the whole life and where the list is in it. A date overlap puts a chapter in the "During" line only. It never tags a moment (PRINCIPLES 1).

**Consequences.**

- No migration and no change under `Store/`. The card only reads.
- `SpineLayout.Stop` gains `yearSpan`, so the app does not repeat the rule for the years of a row.

**Known costs.** These stay after the final review.

- The slack also applies at the bottom edge. A row stays on until all of it is out of the widened frame. So the frame can lag by one row at each edge of the list.
- An open story's member rows do not move the frame. The story's own row decides (R7). While the person scrolls in a long open story, the frame can show the years of the story's row or of the rows below it.
- A confirmed relation's row has a tick and no years. It does not move the frame (R7).
- At the largest text size, the period label above an opened story is cut by a few points at the card's edge.
- No UI test opens a story to move the frame, because no seed has a dated story (R1). The kit tests guard the rule. The device check covers the case.

## 2026-11-18 · The photo card has one layout, and the first photo is the key photo

**Status:** Decided. Thirteen items are open for the owner. They are at the end of this entry. This entry changes the photo card of the 2026-11-16 photo story entry. It also changes the cover of S4. It replaces one ruling of the 2026-11-16 photo story entry: “The offer stays for a guessed range outside the photo’s day”.

**Source:** `docs/specs/2026-11-18-photo-card-key-photo.md` (approved by the owner on 2026-11-18) and `docs/plans/2026-11-18-photo-card-key-photo.md`, decisions 1 to 16. The screens are `docs/design/PH1_PhotoCard.dc.html`, `PH2_PhotoCardAfter.dc.html` and `KP1_KeyPhoto.dc.html`. The rulings made while building are below. There is no migration. There is no new network call.

**The four problems.** The owner told a photo story on the phone. The story made five memories. The card showed five memory rows, eight “Add to …’s page” buttons and one date offer for each memory.

1. The date offer showed many times. The owner tapped it three times for one photo.
2. Every “Add to” button looked the same. A person, a place and a thing were not told apart.
3. The owner did not find how to choose the photo that stands for a person. The control was inside the photo viewer.
4. “Use this date” replaced a guessed date and had no Undo. Two review threads on PR #29 asked for a fix.

**Decision.** The card is one view with one layout. A choice changes the state of a control. It does not change the layout.

- **The chosen approach: one card, grouped, with states.** The card has four parts: the photo and its moments row, “Also show this photo on”, “When did this happen?” and “Remove the photo from this story”. The pages are chips in groups (People, Places, Things, Ideas). A tap on a chip adds the photo to the page. A second tap takes it off. The date is one block for the story.
- **Not chosen: keep the card and remove the duplicates only.** It is the smallest change. It does not fix problem 2.
- **Not chosen: a step-by-step sheet after the story** (“Who is in it?”, “Where?”, “When?”). It adds taps that the person must do. The landing must stay light (principle 8).
- **The moments row.** The card does not show a row for each memory. One row reads “On {n} moments from this story”. A tap opens a sheet with each memory’s title and “Remove”. While a moment of the session waits, the row reads “This photo goes on each moment you keep.” and does not open.
- **A page that holds the photo is a chosen chip.** This includes a page that no kept memory names, unless the page is hidden from browsing. The person must see each page the photo is on.
- **The new date rule: origin, not band.** A memory can take the photo’s date when its origin is not `stated`, `confirmed` or `photo`. An unplaced memory and a guess (`inferred`, `derived`) can take it, inside or outside the photo’s day. This replaces the rule “outside the band” of the 2026-11-16 entry. That entry left the guessed case open for the owner. This entry closes it with Undo.
- **One write for several memories.** “Use for those {n}” sets the range of each chosen memory to `TimeRange.fromPhoto(date)` in one write (`MemoryRepository.updateRanges`). Each memory keeps the check of PR #29: the write skips a memory whose stored range is not the one the card showed. Then the resolver runs one time.
- **Undo is kept in memory.** The card’s view model keeps the old ranges while the screen is open. Undo writes them back in one write and runs the resolver one time. Undo is gone when the screen closes. The memory page then shows “from a photo”, and the person can change the date there.
- **What the resolver does to a guess with no anchor (plan decision 2).** The resolver computes each `inferred` range again from what the person said. A guess with an anchor comes back the same after Undo. A guess with no anchor does not come back: the memory becomes unplaced. No resolver run keeps such a guess, with or without the card. Only code writes it (the test seed does). This is open for the owner.
- **“Key photo” replaces “cover” in every text the person reads.** The code keeps its names: `PhotoRole.cover`, `setCover`, `makeCover`, `photo.makeCover`. The viewer reads “Make this the key photo”.
- **The first photo of a page is the key photo.** This holds for an entity’s page, a memory’s page and You. On the shelf, the person holds a photo and drags it to a new place. A line above the shelf says how. The first tile has the label “Key photo”. With VoiceOver, each tile except the first has the action “Move to front”.
- **`setCover` is a move to the front.** `PhotoRepository.reorder` and `setCover` write the whole order again as 0, 1, 2, with the cover first. A shelf from before this build agrees after its first change. There is no migration. A write that changes the cover takes the role from the old cover before it gives the role to the new one, because the store allows one cover for each page.

**The seven points agreed with `docs/specs/2026-11-18-people-contacts.md`.** That spec is written on another branch. It ships second and must follow these points.

1. **Words.** The person reads “key photo” and “Make this the key photo”, not “cover”.
2. **A contact’s picture.** The picture is stored as a photo of the person. It is the key photo only when the person has no photo. After that, it is a photo like any other.
3. **A changed contact picture.** The app replaces the picture only while it is still the key photo. After the person drags another photo to the front, the app must leave the photos alone.
4. **Photos do not move with a name.** When the person moves a moment to another person, the photo stays on the first person’s page. The card shows both chips.
5. **A guessed person.** A chip on the photo card does not carry the “Assumed” mark. The mark is on the memory’s people.
6. **Merging two people.** The joined photos keep one order. The key photo of the person that stays is first.
7. **Undo.** That spec shows Undo in the message slot for 6 seconds. The card’s date keeps its Undo in the card while the screen is open.

**Rulings made while building (2026-11-18).** Each ruling has its cost.

- **The date control is a full-width button, with “Choose moments” or “Undo” on a row under it.** PH1 and PH2 draw a pill that fits its text, with the link beside it. Why: the card keeps one layout after a choice. “Use for those 2” and “Used for those 2” differ in width, so a pill changes its frame. A full-width button keeps `photoCard.dateUsed` in the frame of `photoCard.useDate`, and “Undo” in the place of “Choose moments”, at every text size. Cost if wrong: one view file (`PhotoCardDate.swift`) changes, and the kit must give the text of both states. This is open for the owner.
- **The session’s page reloads its rows after each card action** (`PhotoCardViewModel.onAction`, set by `SessionDetailViewModel`). Why: without it, the memory page opened from the session’s page showed the date from before the tap. The landing does not set it, because its rows show no dates. Cost: the card is read twice after each action on the session’s page.
- **The moments sheet closes when its last memory is removed.** Why: the sheet stood blank, with no title and no list. Cost: none.
- **A removed key photo passes the role to the photo with the lowest `sort_order`.** After the first change of a shelf, that is the next photo shown. The S4 rule “the oldest-added photo” holds only for a shelf that no change has written yet.
- **The drag is a long press, then a drag, as a simultaneous gesture on the tile’s button.** A high-priority gesture stopped a plain tap from opening the viewer. Why: a tap must still open the viewer, and a drag must not. Cost: no system lift animation (plan decision 12).
- **A held press ends with a one-shot flag.** The flag is set when the long press succeeds. The button’s action uses the flag up and does nothing. The flag clears one run-loop turn after the hold ends. Why: an earlier half-second window depended on the order of two events and could eat a real tap. Cost: none known. The device check covers a tap right after a drop.
- **Only moments take the photo’s date.** A fact, feeling or goal is never offered it, because its page shows no date. Why: a date written there could not be seen or changed. Cost: none.
- **The slot math of the drag is in the kit with a table test** (`PhotoShelfDrag`). The row in the app calls it. Cost: none.
- **Test changes that the plan named.** `testAKeptMomentHoldsThePhoto` keeps both cards, because the moments row does not open while a moment waits (plan decision 9). The tests of the first spec that asserted one offer for each memory, or the band rule, changed with the spec. No other assertion was made weaker.
- **Test changes outside the text of the plan, of equal strength.** `aPhotoPutBackOnAPageComesBackLast` links the photo to a second page, so the photo row survives the unlink. The UI helper `openMemory` moves a row above the record bar before it taps. Why: XCUITest calls a row under the bar hittable, and the tap opens the Timeline tab.
- **Tests that fail under load, not ours.** `drainGivesUpAtItsDeadline` (kit), `testAPlayErrorLeavesAnOpenUndoInPlace` and `testHidingALineFarDownShowsUndoWithoutScrolling` (`YouUITests`) failed while another session ran tests on this Mac. Each passed on a rerun. The whole UI suite must show if they are steady.

**Open items for the owner.** Each needs a decision or a look on the device. The device check is `docs/plans/2026-11-18-photo-card-key-photo-device-check.md`. The screenshots are in `docs/screenshots/photo-card/`.

1. **The shape of the date control.** It is a full-width button with “Choose moments” or “Undo” on a row under it. PH1 and PH2 draw a pill with the link beside it. See the ruling above.
2. **Undo is kept in memory (plan decision 3).** Undo stays while the screen is in the navigation stack, also after the person opens a memory page and comes back. It goes when the screen closes. Undo is not stored. Cost if wrong: one `@State` move ends Undo at the first push. A stored Undo needs a new spec.
3. **Undo of a guess with no anchor (plan decision 2).** The memory becomes unplaced. Cost if wrong: `undoDate` skips the resolver for that memory, and the next resolver run erases the guess anyway.
4. **A second tap adds to the first (plan decision 4).** After a new memory is kept and the person taps again, “Undo” puts back the ranges of both taps. The count after the tap is the total.
5. **An unchecked memory does not bring the offer back (plan decision 5).** Only a memory kept after the tap shows the offer again. The unchecked memory gets no second offer until the screen opens again. The memory page can still set its date.
6. **While a moment waits, the moments row shows only “This photo goes on each moment you keep.” and does not open (plan decision 9).** The person cannot reach “Remove” for a kept memory until every moment of the session is sorted. Cost if wrong: the row needs a fourth state.
7. **The VoiceOver action “Move to front” has no UI test (plan decision 14).** XCUITest cannot list custom actions. The device check covers its presence and its name.
8. **The shelf stays one row that scrolls sideways.** KP1 draws a grid. The row is the shape that the app has. A grid is not in this plan.
9. **A drag on You can scroll the page to its top.** The S4 ruling “the page scrolls to its top when the cover changes” runs after each change of the key photo. The owner must say if this is wanted after a drag.
10. **The drag on the device.** A plain sideways swipe, a tile at the drop, the page under a held tile and the “Key photo” pill at a large text size need a device. See the checklist.
11. **“Choose moments” draws switches.** The spec says checkboxes. A switch is the control that iOS has.
12. **A memory dated from an age has origin `inferred`.** An example is “when I was 22”. The card counts it under “no date you said”, and a tap replaces its date. Undo covers it. But the sentence “no date you said” may not be true for it.
13. **A resolver failure after the date write leaves no Undo.** The dates are stored. The card shows the error and gives no Undo for them. Only a store failure causes this.

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

## 2026-11-18 · PC-a: rulings made while building people and contacts

**Status:** Decided by the builder, except R13, which the controller made and the owner must confirm. The owner can overrule each one. Source: `docs/plans/2026-11-18-people-contacts.md`, ledger `.superpowers/sdd/2026-11-18-people-contacts/rulings.md` (R1 to R39). Narrows two statements of the entry below and of the spec.

**Decision.**

Schema:

- R36: the migration is named `v15`. This branch registers no `v14`. Why: the unmerged photo branches register their own `v14`, and GRDB records a migration by name, so a device that ran one `v14` would skip the other. GRDB runs each unapplied id in registration order, so the gap is harmless.

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
