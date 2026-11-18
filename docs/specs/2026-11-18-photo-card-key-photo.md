# Photo card and key photo

**Status:** Draft for the owner's approval. **Date:** 2026-11-18.

**Builds on:** `docs/specs/2026-11-16-photo-story.md` (branch `photo-story`, PR #29). This spec changes the photo card of that spec and the cover of S4. It replaces the section "The photo's date" and the section "The photo card" of that spec where they differ.

**Screens:** `docs/design/PH1_PhotoCard.dc.html`, `PH2_PhotoCardAfter.dc.html`, `KP1_KeyPhoto.dc.html`. The owner approved them on 2026-11-18.

## Why

The owner told a photo story on the phone. The story made five memories. The card showed five memory rows, eight "Add to …'s page" buttons of the same shape, and one date offer for each memory. The owner found three problems:

1. The date offer shows many times. The owner tapped it three times for one photo.
2. Every "Add to" button looks the same. A person, a place and a thing are not told apart.
3. The owner did not find how to choose the photo that stands for a person. The control is inside the photo viewer.

Two review threads on PR #29 are open for a fourth problem: "Use this date" replaces a guessed date and has no Undo.

## Goals

- The card has one date offer for the story, with Undo.
- The card shows pages by kind. A tap adds the photo to a page. A second tap takes it off.
- The card looks the same before and after a choice. Only the state of a control changes.
- The person changes the key photo of a page on the page itself.

## Not goals

- The card does not suggest a person or a place that the memories do not name.
- This spec does not change how a photo starts a story, or the access screens.
- This spec does not add a "declined" state. An offer that the person does not use stays an offer.
- This spec does not change the people model. `docs/specs/2026-11-18-people-contacts.md` does that.

## Must not happen

- A tap must not replace a date that the person said or confirmed.
- A date change from the card must not be final at the moment of the tap. The person must be able to undo it on the same screen.
- The screen after a choice must not have a different layout from the screen before it.

## Approaches

1. **One card, grouped, with states (chosen).** The card keeps one layout. Pages are chips in groups. The date is one block. A choice changes the state of its control. The owner chose this from the screens PH1 and PH2.
2. **Keep the card and remove the duplicates only.** One date offer, and the buttons stay full-width in one list. This is the smallest change. It does not fix the second problem.
3. **A step-by-step sheet after the story** ("Who is in it?", "Where?", "When?"). It reads well for one memory. It adds taps that the person must do, and the landing must stay light (principle 8).

## The card

The card is one view. The landing and the session's page in Sessions both use it. It reads the store each time it appears. It has four parts, in this order.

### 1. The photo and its moments

- The photo, small, with its caption (`PhotoCaption`).
- One row beside it:
  - While a moment of the session is not yet kept: "This photo goes on each moment you keep." The row does not open.
  - With one kept memory that holds the photo: "On 1 moment from this story".
  - With more: "On {n} moments from this story".
- A tap on the row opens the list of those memories in a sheet. Each line has the memory's title and a "Remove" button. The accessibility label of the button is "Remove from {title}". "Remove" unlinks the photo from that memory, as it does today.
- The card does not show the memory rows itself.
- With no kept memory that holds the photo and no moment pending, the row does not show.

### 2. "Also show this photo on"

- Title: "Also show this photo on". Line under it: "Tap to add. Tap again to take it off."
- The pages are the entities that the kept memories of the session name, with the same rules as today (`PhotoStory.card`): not hidden from browsing, each one time.
- A page that already holds the photo is in the list too, in the chosen state. Today the card leaves such a page out.
- A page that holds the photo and that no kept memory names is in the list too, in the chosen state, unless it is hidden from browsing. The person must always see each page the photo is on. Example: the person moves a moment from one person to another; the photo stays on the first person's page, and the card still shows that chip.
- The pages are in groups, in this order: People, Places, Things, Ideas. A group with no page does not show. Each group has its name and a small symbol.
- In a group, the owner's page is first and its chip reads "You". The other pages follow by title.
- Each page is a chip with the entity's title.
  - Not chosen: an outline. The accessibility value is "not added".
  - Chosen: filled, with a tick. The accessibility value is "added".
- A tap on a chip that is not chosen adds the photo to the page with the cover rule of S4: the photo becomes the key photo only when the page has no photo.
- A tap on a chosen chip takes the photo off the page (`PhotoLibrary.remove(_:from:)`). When it was the key photo, the next photo of the page becomes the key photo, as S4 does.
- The tap cannot delete the photo. The card shows only while the session points at the photo, and the session is a home for it.
- Two pages with the same title have chips that read the same. `docs/specs/2026-11-18-people-contacts.md` tells such people apart; this spec adds nothing for it.
- With no page to show, this part does not show.

### 3. "When did this happen?"

- This part shows when the photo has a date and at least one kept memory can take it, or when the card set dates and the screen is still open.
- A memory can take the date when its date has an origin other than `stated`, `confirmed` and `photo`. An unplaced memory and a guessed date (`inferred`, `derived`) can take it. This replaces the rule "outside the band" of the first spec.
- A memory dated from another photo cannot take the date from the card. The person changes it on the memory's page.
- Before the tap:
  - Text: "The photo is dated {date}. {N} moments have no date you said." For one: "One moment has no date you said."
  - Button: "Use for those {n}". For one: "Use for that one". When every memory that holds the photo can take the date: "Use for all {n}".
  - Link: "Choose moments". It opens a sheet with the memories that can take the date, each with a checkbox, all on. The sheet's button is "Use for {n}".
- A tap sets each chosen memory's range to `TimeRange.fromPhoto(date)`. All the memories change in one write. Each memory has the check that PR #29 added: the write skips a memory whose stored range is not the one the card showed. The write returns the memories that it changed. Then the resolver runs one time.
- The counts after the tap are the memories that this tap changed. They do not change while the screen is open.
- After the tap:
  - Text: "The photo is dated {date}. {N} moments now use that date."
  - The button reads "Used for those {n}", filled, with a tick. It is not a control.
  - Link: "Undo".
- "Undo" puts back each memory's range from before the tap, in one write. A memory whose range changed after the tap, or that is gone, is left alone. Then the resolver runs one time. The part goes back to the state before the tap.
- The resolver computes a guessed date again from what the person said. After Undo, a guessed date is the same as before the tap unless the thing it was guessed from changed in between. A memory that was placed relative to a changed memory is placed again by the same run.
- A guessed date that has nothing the person said behind it does not come back after Undo. The memory is then unplaced. No resolver run keeps such a date, with or without this card.
- When a new memory that can take the date is kept after the tap, the part shows the state before the tap for that memory, and "Undo" stays for the earlier tap.
- The card keeps the old ranges in memory. When the person leaves the screen, Undo is gone. The memory page then shows "from a photo", and the person can change the date there.
- A memory that keeps a date the person said has no line on the card. The count in the text is the only sign.

### 4. "Remove the photo from this story"

No change. It shows on the session's page only, and it asks first.

## Key photo

- The app says "key photo" where it said "cover". The code keeps its names (`PhotoRole.cover`, `setCover`).
- The first photo of a page is its key photo. This holds for an entity's page, a memory's page and You.
- The photo shelf is the row of photos that the three pages share (`PhotoRow`). It stays one row that scrolls sideways. KP1 draws a grid; the row is the same idea in the shape the app has.
- On the shelf, the person holds a photo and drags it to a new place. The new order is stored (`photo_link.sort_order`). The photo in the first place becomes the key photo. Moving the key photo away from the first place makes the next first photo the key photo.
- A line above the shelf reads: "The first photo is the key photo. Hold a photo and drag it to the front to change it." It shows when the page has two or more photos.
- The key photo has the label "Key photo" on its tile.
- The photo viewer keeps a button for the same move. It reads "Make this the key photo". It moves the photo to the first place.
- With VoiceOver, each photo on the shelf except the first has the action "Move to front".
- Today a cover can be a photo that is not first in `sort_order`. A read already shows the cover first, so the person sees no difference. `reorder` and `setCover` write the whole order again as 0, 1, 2 and so on, with the cover first, so a shelf agrees after its first change. `setCover` becomes "move to the front". No migration.
- The store allows one cover for each page. A write that changes the cover must take the role from the old cover before it gives the role to the new one.
- A drag must not start the photo viewer, and a tap must still open it.

## Together with the people and contacts spec

`docs/specs/2026-11-18-people-contacts.md` is written at the same time on another branch. These points keep the two specs in agreement. The spec that ships second must follow them.

1. **Words.** That spec says "cover" and "Make this the cover". With this spec the person reads "key photo" and "Make this the key photo".
2. **A contact's picture.** That spec stores the contact's picture as a photo of the person, and it is the key photo only when the person has no photo. That is the add rule of this spec. The picture is then a photo like any other: the person can drag another photo to the front.
3. **A changed contact picture.** That spec replaces the picture only while it is still the key photo. After the person drags another photo to the front, the app must leave the photos alone.
4. **Photos do not move with a name.** When the person moves a moment to another person, the photo stays on the first person's page. Part 2 of the card shows both chips, so the person can take the photo off one page and put it on the other.
5. **A guessed person.** That spec marks a person the app assumed. A chip on the photo card does not carry the mark. The mark is on the memory's people, where the person settles it.
6. **Merging two people.** That spec joins the photos of two people and keeps the key photo of the person that stays. The joined photos keep one order, with that key photo first.
7. **Undo.** That spec shows Undo in the message slot for 6 seconds. The date on the photo card keeps its Undo in the card while the screen is open, because the card is where the person reads the result.

## Data

- No migration. `photo_link.sort_order` and `role` exist.
- New in the kit:
  - `PhotoRepository.reorder(_ photos: [PhotoID], of subject: PhotoSubject)`: one write; sets `sort_order` from the array and the cover to the first. It ignores an id that the page does not hold. A photo of the page that is not in the array goes to the end.
  - `MemoryRepository.updateRanges`: one write for several memories, each with its `ifCurrently` check and its chapter refresh. It returns the memories that it changed.
  - `PhotoStory.card` returns the pages in groups with a chosen flag, and one date offer with the memories that can take it.
  - `PhotoStoryReader.useDate` takes the date and several memories, and returns the old range of each memory that it changed. It replaces today's `useDate(_ offer:)`. `PhotoStoryReader.undoDate` takes those ranges back.
- `PhotoStory.offersDate(_:for:)` loses the band rule.

## Edge cases

- **Zero memories can take the date.** Part 3 does not show.
- **The person removes the photo from a memory after "Use for those".** The memory keeps the date. Undo still puts its old date back.
- **A memory's date changes on another screen while the card shows the offer.** The write skips that memory. The card reads the store again and the count is correct.
- **The person taps a chosen chip of a page where the photo was the key photo, then taps it again.** The photo comes back as the last photo, not as the key photo, unless the page has no other photo.
- **A page held the photo before this story.** Its chip is chosen. A tap takes the photo off that page. The tap is the person's own, and a second tap puts it back.
- **A long title.** A chip wraps to two lines and then cuts with an ellipsis. Chips wrap to more rows.
- **The largest text size.** Each chip, the date button, "Undo" and the moments row are reachable and at least 44 points high.
- **One photo on a page.** No drag, no line above the shelf.
- **A drag that ends where it started.** No write.
- **A kill between the date write and the resolver.** The dates are stored. The resolver runs at the next launch, as it does today.

## Tests

- Kit: the card's groups and their order; a page that already holds the photo is chosen; the owner's chip is first; a memory with a said, confirmed or photo date cannot take the date; a guessed date inside or outside the day can; one write for several memories; Undo puts back each range and skips a memory that changed; `reorder` sets the order and the cover; a shelf whose cover is not first is repaired by the next change.
- UI (`PhotoCardUITests`, and the shelf's class): one date block for two memories; the button and Undo; a chip adds and takes off; the moments sheet and "Remove from {title}"; the layout holds at the largest text size; a drag to the front changes the key photo on the page header; "Make this the key photo" in the viewer; the VoiceOver action exists.
- The tests of the first spec that assert one offer for each memory, or the band rule, change with this spec. No other assertion is made weaker.

## Left to the builder

- The sheet for the moments list and the sheet for "Choose moments" can be one view with two modes.
- The drag can use SwiftUI's reorder support for a grid or a custom gesture, as long as a tap still opens the viewer.
- The symbols for the groups.

## Calls made in this spec without the owner

1. A guessed date whose band holds the photo's day can now take the photo's date. The first spec did not offer it there. Undo covers a wrong tap.
2. Undo lasts while the screen is open. It is not stored.
3. A memory that keeps a said date has no line on the card. The second version of PH2 had such a line; the approved one does not.
4. A page that already holds the photo shows as a chosen chip, and a tap takes the photo off that page.
5. A photo that is put back on a page does not come back as the key photo.
6. The moments list is a sheet. No screen shows it yet.
7. "Key photo" replaces "cover" in every text the person reads.
8. The groups include Ideas when a memory names one.
9. The photo shelf stays one row that scrolls sideways. KP1 draws a grid.
10. Moving the key photo away from the front changes the key photo, with no question.
11. A chip for a guessed person has no "Assumed" mark on the photo card.
12. The card lists every page that holds the photo, also a page that no memory of the story names.
