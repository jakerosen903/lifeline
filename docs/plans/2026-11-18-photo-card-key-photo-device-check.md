# Photo card and key photo: device check

Run this on the iPhone with the photo-card build. Tick each line. Say what looks wrong. Each line says what to do and what must be true. The screenshots in `docs/screenshots/photo-card/` show the simulator with the seed data.

## The photo card

1. [ ] Tell a photo story that makes five memories. Keep all five. Open the session’s page. The card must show one date block and one moments row. The row must read “On 5 moments from this story”. No memory row must show on the card.
2. [ ] On the same card, tap “Use for those {n}”. The text must read “… {N} moments now use that date.”, the button “Used for those {n}” with a tick, and “Undo” must be where “Choose moments” was. The layout must not move. Tap “Undo”. Open each memory page. Each page must show its first date again.
3. [ ] Tap “Choose moments”. The sheet must list the memories that can take the date, all on. Turn one off. Tap “Use for {n}”. The memory that you turned off must keep its old date. The offer must not come back for it.
4. [ ] Tap a chip that is not chosen. It must fill and get a tick. Open that page. The photo must be there. Go back and tap the chip again. It must go back to an outline. Open the page again. The photo must not be there.
5. [ ] Use a photo that a page held before the story. Its chip must be chosen at once. Tap it. The photo must leave that page. Tap it again. The photo must come back as the last photo, not as the key photo, unless the page has no other photo.
6. [ ] Move a moment of the story from one person to another. Open the card. Both chips must show. The chip of the first person must stay chosen.
7. [ ] Set the largest text size (Accessibility XXXL). Look at the card on the landing and on the session’s page. Each chip, the date button, “Choose moments” or “Undo”, and the moments row must be reachable and at least 44 points high. Nothing must clip. A long title must wrap to two lines, then cut with an ellipsis.
8. [ ] Turn on VoiceOver on the card. Each chip must read its name and “added” or “not added”. The used button (“Used for those {n}”) must read as text, not as a button. “Remove” in the moments sheet must read “Remove from {title}”.
9. [ ] In the moments sheet, remove each memory, one by one. When the last one goes, the sheet must close.
10. [ ] Tap “Use for those {n}”. Kill the app at once. Open it again. The memories must keep the photo’s date. Undo must be gone. Each memory page must show “from a photo”.
11. [ ] While a moment of the session waits, look at the moments row. It must read “This photo goes on each moment you keep.” and must not open (plan decision 9). Say if you want to reach “Remove” before every moment is sorted.

## The key photo

12. [ ] On a person, a memory and You, each with three photos or more: hold a photo, then drag it to the front. It must become the key photo, with the label “Key photo”. Then tap a photo. The viewer must open. Then swipe the row sideways. The row must scroll.
13. [ ] Swipe the photo row sideways with no pause. The row must scroll, and no tile must lift.
14. [ ] Drag a photo and drop it. The tile must not jump back to its old place before it settles in the new place.
15. [ ] Hold a tile and move your finger up and down. The page must not scroll under the held tile.
16. [ ] Hold a photo and drag it with a finger that leaves the row, up or down. When you let go, the order must be the one you see, and no tile must stay lifted.
17. [ ] Hold a photo, pause, and let go with no move. The viewer must not open.
18. [ ] Drop a photo, then tap a photo at once. The viewer must open.
19. [ ] Drag a photo to the front on You. Say if the page jumps to its top, and if that is wanted.
20. [ ] Set a large text size (Accessibility L or larger). The “Key photo” pill must not make the first tile wider than the others. A drag must still drop where the finger is.
21. [ ] Turn on VoiceOver on a shelf. Each tile except the first must have the action “Move to front” (plan decision 14). The first must not have it. Use the action on the third tile. That photo must become the key photo.
22. [ ] Open a photo that is not first in the viewer. Tap “Make this the key photo”. The photo must move to the front. The page header must show it.
23. [ ] Open a page whose key photo you chose before this build (with “Make this the cover”). The key photo must still be first. Drag one photo. The order must be the one you see, and the key photo must be the first photo.
24. [ ] After a drag on a person’s page, open People. The person’s tile must show the new key photo.

## Added after the final review

25. [ ] Set the largest text size (Accessibility XXXL). Open the moments sheet. Each “Remove” button must be reachable and at least 44 points high. Nothing must clip.
26. [ ] Tell a photo story that keeps a fact, a feeling or a goal with the photo, and one moment or more. Open the card. The date block must not count the fact, the feeling or the goal. With no moment left, the date block must not show.

## Known small items

These were found in the reviews and deferred. None blocks the build. Each is one line.

- If the resolver throws after the range write, the caller gets no Undo handle.
- No test pins the order of the changes that `useDate` returns.
- `StoryDateOffer` and `PhotoDatePart.Offer` have no public init.
- Some kit tests repeat the same row comparisons.
- The card is read twice after each action on the session’s page (`onAction` and the inner refresh).
- `useDate(for:)` returns with no message when the offer went away while the sheet was open.
- `keepsTallest` resets on a text-size change only, not on a width change.
- The seed guard now needs “Alder Street”. With the guess flag and no birth date, the seed skips “The picnic” with no message.
- No test checks the “Remove” buttons of the moments sheet at the largest text size.
- The tile can jump back at the drop until the write lands (line 14).
- The page can scroll under a held tile, because the page keeps its pan (line 15).
- The “Key photo” pill is capped at one line and at the xLarge text size. No test checks the slot math at a larger text size (line 20).
- Two quick drags can lose the first, because `move` builds on the order as last read.
- A drag on You scrolls the page to its top (line 19).
- The hold flag is cleared when the hold ends. A release at the exact moment that the long press is recognised can leave the flag set. The flag then swallows one tap.
- No test taps a photo right after a drop (line 18).
- The “Choose moments” sheet uses switches for the memories. The spec says checkboxes. A switch is the control that iOS has.
