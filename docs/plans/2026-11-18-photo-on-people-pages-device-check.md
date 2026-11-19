# A photo story's photo on its people's pages: device check

Run this on the iPhone with the build of parts 1 to 4. Tick each line. Say what looks wrong. Each line says what to do and what must be true. Part 3 has its lines under “Done and Edit”. Part 4 (several photos at one time) has its lines under “Several photos at one time”.

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

13. [ ] Before you install this build, note two people's pages that show photos from older photo stories. Install the build. Each page must show the same photos in the same order. Each chip on the older cards must read “added”, not “added by this story”. The app must not put a photo from an older story on a page that did not show it before.

## Several photos at one time

14. [ ] On a person's page, tap “Add a photo”. Pick five photos, one of them only in iCloud (not on the phone). The line must read “Adding photo 1 of 5…”, then count up to 5. The five photos must go last on the page, in the order you picked them. No error line must show.
15. [ ] Open the picker again and try to pick 21 photos. The picker must stop at 20.
16. [ ] On a page with no photo, pick three photos. The first photo you picked must be the key photo.
17. [ ] Pick photos that the page holds already, with one new photo. The page must gain the new photo only.
18. [ ] Pick ten photos. While the line reads “Adding photo 4 of 10…”, kill the app. Open the app and the page. The photos added before the kill must be there, in order. The others must not be there. Add them again.
19. [ ] On a memory page and on You, pick two photos. Both must be added, in order.
20. [ ] Start “Tell a story about a photo” and open “All photos”. The picker must take one photo only.
21. [ ] On a person's page, pick five photos. While the line counts, open the “…” menu. “Add a photo” must be in the menu and dimmed. A tap on it must do nothing. When the line is gone, open the menu again. “Add a photo” must work again.
22. [ ] Pick two items that the app cannot add, with one good photo. The UI test uses two files that are not photos. The good photo must be added. At the end the page must show one line: “2 photos could not be added.”
23. [ ] Pick ten photos. While the line counts, go to the Home Screen for ten seconds. Open the app again. Note the photos on the page and the line. Say what you see.

## Done and Edit

24. [ ] Open a photo story whose card shows a filled chip and an empty chip. Tap “Done” under the chips. Only the filled chips must show. The empty chips and their group heading must be gone. The line under “Also show this photo on” must be gone. The button must read “Edit”.
25. [ ] Tap “Edit”. Every chip must show again, filled or empty, with the line. The button must read “Done”.
26. [ ] Tap “Done”. Close the app from the app switcher. Open the app and the same story. The part must still be done.
27. [ ] Tap “Done” on the landing. Leave the landing. Open the session's page of the same story. The part must be done there too.
28. [ ] With the part done, tap a filled chip. The chip must go to an outline and stay on screen, under your finger. Tap it again. It must fill. Tap it a third time. It must go to an outline again and stay on screen. Tap “Edit”, then “Done”. The empty chip must be gone.
29. [ ] Take the photo off every page with the chips, then tap “Done”. The part must read “This photo is on no other page.” and show “Edit”.
30. [ ] With the part open, take the last chip the story chose off. The line changes to “Tap to add. Tap again to take it off.” No chip must move.
31. [ ] Turn on VoiceOver. “Done” and “Edit” must each read as a button. After a tap on “Done”, swipe to “Edit” and tap it. Each chip must read as before: “added by this story”, “added” or “not added”.
32. [ ] Set the largest text size (Accessibility, Larger Text, the largest step). Open the card. “Done” and “Edit” must each be reachable by scrolling, and must not be cut off.
33. [ ] Open a person's page that has a photo. Open the photo and tap “Tell its story”. Tell a story that does not name that person, and keep the moment. On the card, the person's chip must be filled. Tap “Done”. Tap the person's chip. The chip must go to an outline and stay on screen, under your finger. Tap “Edit”. The person's chip must be gone, because the person is not in the story and the page no longer holds the photo.
34. [ ] Open a person's page that has a photo. Open the photo and tap “Tell its story”. Tell a story that names nobody, and keep the moment. On the card, the person's chip must be the only chip, and it must be filled. Tap “Done”. Tap the person's chip. The chip must go to an outline and stay on screen, under your finger, with “Edit” under it. Tap “Edit”, then “Done”. The part must read “This photo is on no other page.”

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
- Ruling: a move removes the first person's story link only when no memory that holds the photo names that person now, in any session. The same rule applies when Undo removes a link the move added.
- Ruling: a move adds the photo to the new person only (`only:`).
- No comment says that unlinking from the owner's own page records a harmless decline.
- No test covers `letGo` making the photo homeless after it removed story links.
- The returned order of `linkToPeoplePages` is promised in its doc and not asserted.
- `aFailedKeepWritesNothing` has no control assertion that the same card without the trigger writes the page link.
- `undoingAKeepLeavesNoLinkAndKeepsThePhoto` (`PhotoRepositoryTests`) is misnamed. It is a plain delete.
- `stateValue` trusts `byStory` without `isChosen`. Only `PhotoStory.card` builds pages.
- `PersonMoveReceipt.photoPages` is `public var`. It must be `public internal(set)`.
- No test pins what `only:` is for (the moved moment also names a person who lacks the photo).
- After a name move on the session's page, the notice with “Undo” can sit below the screen for its 6 seconds. Scroll down to reach it.
- The failure line is lost when you leave the page during a pick. The adds still finish.
- With no shelf, a failure in a pick uses the one-photo line.
- `-uiTesting-pickPhotos` splits its paths on a comma.
- The merge path of `PhotoAddBatch` (a second pick joins the first) cannot be reached from the UI now. It stays as a defence.
- `-uiTesting-slowPhotoFile` has two meanings: a slow file, and a 3-second wait in the test pick path.
- The dimmed “Add a photo” has a UI test on the entity page only. The memory page and You share `AddPhotoButton`.
