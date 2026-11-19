# A photo story's photo on its people's pages: device check

Run this on the iPhone with the build of parts 1 and 2. Tick each line. Say what looks wrong. Each line says what to do and what must be true. Part 3 has its lines under “Done and Edit”. Part 4 (several photos at one time) has its lines under “Several photos at one time”.

## Part 1: a kept moment puts the photo on its people's pages

1. [ ] Tell the first photo story about a person who is new to the app. Keep the moment. Look at the card. The person's chip must be filled, with a tick. The line under “Also show this photo on” must read “The people in this story have this photo on their pages. Tap to take it off, or to add it to another page.” Open the person's page. The photo must be there. On a page with no other photo, it must be the key photo.
2. [ ] On the same card, tap the person's chip. It must go back to an outline. Keep another moment of the same story that names the same person. The chip must stay an outline. Open the person's page. The photo must not be there.
3. [ ] Tap the chip again. It must fill. VoiceOver must read “{name}, added”, not “added by this story”.
4. [ ] Take each person the story chose off with the chip. The line must read “Tap to add. Tap again to take it off.”
5. [ ] Use a photo that a person's page held before the story. Tell a story that names that person and keep the moment. The chip must be filled. VoiceOver must read “{name}, added”. The photo must stay where it was in the page's order.
6. [ ] Tell a story that names you and a place. Keep the moment. The “You” chip and the place's chip must be outlines.
7. [ ] Turn on VoiceOver on the card. A chip the story chose must read “{name}, added by this story”. A chip you tapped must read “{name}, added”. An empty chip must read “{name}, not added”.

## Part 2: the photo follows a moved name

8. [ ] Tell a photo story that names a person by a guess (the chip on the moment shows “Assumed”). Keep the moment. Tap the person chip on the moment. In “Who is this?”, choose “Someone new”, then “Done”. The card must show the new person's chip filled, at once. The first person's chip must be gone or an outline. Open the new person's page. The photo must be there.
9. [ ] Within 6 seconds, tap “Undo”. The card must show the first person's chip filled, at once, and the new person's chip must be gone. Do this on the landing and on the session's page.
10. [ ] Repeat line 8 on a person whose page held the photo before the story. After the move, the first person's page must still show the photo.
11. [ ] Move a name to another person on file. On the card, tap that person's chip to take the photo off. Tap “Undo” within 6 seconds. That person's page must not show the photo.
12. [ ] Move a name. On the card, tap the first person's chip to put the photo back by hand. Tap “Undo” within 6 seconds. The chip must read “{name}, added” with VoiceOver, and the photo must stay on that page.

## After the update

13. [ ] Before you install this build, note two people's pages that show photos from older photo stories. Install the build. Each page must show the same photos in the same order. Each chip on the older cards must read “added”, not “added by this story”. No older story must put a photo on a new page.

## Several photos at one time

14. [ ] On a person's page, tap “Add a photo”. Pick five photos, one of them only in iCloud (not on the phone). The line must read “Adding photo 1 of 5…”, then count up to 5. The five photos must go last on the page, in the order you picked them. No error line must show.
15. [ ] Open the picker again and try to pick 21 photos. The picker must stop at 20.
16. [ ] On a page with no photo, pick three photos. The first photo you picked must be the key photo.
17. [ ] Pick photos that the page holds already, with one new photo. The page must gain the new photo only.
18. [ ] Pick ten photos. While the line reads “Adding photo 4 of 10…”, kill the app. Open the app and the page. The photos added before the kill must be there, in order. The others must not be there. Add them again.
19. [ ] On a memory page and on You, pick two photos. Both must be added, in order.
20. [ ] Start “Tell a story about a photo” and open “All photos”. The picker must take one photo only.

## Done and Edit

21. [ ] Open a photo story whose card shows a filled chip and an empty chip. Tap “Done” under the chips. Only the filled chips must show. The empty chips and their group heading must be gone. The line under “Also show this photo on” must be gone. The button must read “Edit”.
22. [ ] Tap “Edit”. Every chip must show again, filled or empty, with the line. The button must read “Done”.
23. [ ] Tap “Done”. Close the app from the app switcher. Open the app and the same story. The part must still be done.
24. [ ] Tap “Done” on the landing. Leave the landing. Open the session's page of the same story. The part must be done there too.
25. [ ] With the part done, tap a filled chip. The chip must go to an outline and stay on screen, under your finger. Tap it again. It must fill. Tap it a third time. Tap “Edit”, then “Done”. The empty chip must be gone.
26. [ ] Take the photo off every page with the chips, then tap “Done”. The part must read “This photo is on no other page.” and show “Edit”.
27. [ ] With the part open, take the last chip the story chose off. The line changes to “Tap to add. Tap again to take it off.” No chip must move.
28. [ ] Turn on VoiceOver. “Done” and “Edit” must each read as a button. After a tap on “Done”, swipe to “Edit” and tap it. Each chip must read as before: “added by this story”, “added” or “not added”.
29. [ ] Set the largest text size (Accessibility, Larger Text, the largest step). Open the card. “Done” and “Edit” must each be reachable by scrolling, and must not be cut off.

## Known small items

These were found in the reviews and deferred, or are open for the owner. None blocks the build. Each is one line.

- Open for the owner: “Same story” (a telling merged into an older memory) writes no page link. Its people show as empty chips.
- Open for the owner: the chip has no “Assumed” mark. A photo that follows a guessed name looks like one you chose.
- Open for the owner: moments kept before this build get no link. Tap the chip for an older story.
- Open for the owner: a kept fact about a person also places the photo.
- Open for the owner: after a kept memory is deleted, the chip still reads “added by this story”, although no kept memory names the person.
- Open for the owner: a restored link goes last. After a move and its Undo, a photo that was the key photo is not the key photo when the page gained another photo meanwhile.
- Ruling: every name link counts, `detail` as well as `mention`.
- Ruling: there is no undo of a Keep. A deleted memory leaves the photo on the people's pages.
- Ruling: there is no `PhotoStoryReader.removeFromPage`. The chip removes through `PhotoLibrary.remove`.
- Ruling: a move removes the first person's story link only when no memory that holds the photo names that person now, in any session.
- Ruling: a move adds the photo to the new person only (`only:`).
- `v16FromV13` does not assert `photo_pages_done = 0` or that `photo_page_declined` exists.
- No comment says that unlinking from the owner's own page records a harmless decline.
- No test covers `letGo` making the photo homeless after it removed story links.
- The returned order of `linkToPeoplePages` is promised in its doc and not asserted.
- `aFailedKeepWritesNothing` has no control assertion that the same card without the trigger writes the page link.
- `undoingAKeepLeavesNoLinkAndKeepsThePhoto` (`PhotoRepositoryTests`) is misnamed. It is a plain delete.
- `stateValue` trusts `byStory` without `isChosen`. Only `PhotoStory.card` builds pages.
- Undo of a move restores a story link to a page the owner hid after the move.
- `PersonMoveReceipt.photoPages` is `public var`. It must be `public internal(set)`.
- No test pins what `only:` is for (the moved moment also names a person who lacks the photo).
