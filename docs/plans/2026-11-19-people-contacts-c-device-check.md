# Device check: two people can be merged (PC-c)

Do these on a real iPhone, with real contacts where an item says so. The simulator ran the UI tests, but nobody has seen the drag, the motion, VoiceOver or the largest text size by hand. Use invented people. Tick each item when it works.

The phone branch must have this branch merged in first, with the owner's word.

## The button path

- [ ] 1. Open a person's page. Tap "Same as another person…". A list opens with the title "Who is {name} the same as?". The list does not hold this person and does not hold you.
- [ ] 2. Pick another person. "Same person?" shows both pictures and both names, with an arrow from the person that goes to the person that stays. The person you picked is the one that stays. The text reads "{leaving} joins {staying}. Every story, name and photo moves to {staying}." and "You can undo this for a few seconds only."
- [ ] 3. Tap "Cancel". The sheet closes. Nothing changes, and no line shows.
- [ ] 4. Do item 2 again and tap "Merge". The sheet closes. The page shows "Merged into {staying}." with "Undo". The page reads only: "Same as another person…" does nothing.
- [ ] 5. Wait. The line stays for 6 seconds. Then the page closes to the People grid. The grid shows the person that stayed and not the other. That person's page has the stories of both.
- [ ] 6. Merge two other people. Tap "Undo" inside the 6 seconds. The line goes. The page is live again and stays up. The People grid shows both people, each with their own stories.
- [ ] 7. Merge two other people. Tap Back inside the 6 seconds. The People grid shows only the person that stayed. No "Merged into" line and no Undo show. The merge stays. This is the known limit: Undo is lost when you leave the page.

## What joins

- [ ] 8. Give each of two people a few photos, each with a key photo. Merge them. The page of the person that stayed shows that person's photos first, with their key photo at the front, then the other person's photos. The tile on People shows the same key photo.
- [ ] 9. Keep one person from the AI, and not the other. Merge them. The confirm has the line "{staying} stays out of the AI's view, because one of them is." After the merge, the person that stayed is kept from the AI. Do the same with "hidden": the line reads "{staying} stays hidden, because one of them is."
- [ ] 10. Merge "Robin" into "Robyn Vale" (invented names). Record a new story that says "Robin". The chip on the card names "Robyn Vale".

## Contacts

- [ ] 11. With a real contact: link person A to that contact. Open person B's page and link B to the same contact. "Same person?" opens for B and A. Tap "Merge". The line reads "Merged into {A}.". A keeps the contact, and its row still reads "Linked to {contact} in your contacts".
- [ ] 12. Link person A to one contact and person B to another. On B's page, "Same as another person…", pick A. No confirm opens. The page shows "They are linked to two different contacts." Both people stay. Do the same through "Link to another contact" on B with A's contact: the same line shows.
- [ ] 13. Let a person be made from a contact (a new name in a story that fits one contact). Merge that person into a person with no contact. The person that stayed now holds the contact, and its picture is on their page. The person that stayed keeps their own name. The contact's name does not become one of their names.

## The drag on the People grid

- [ ] 14. Long-press one face on the People grid and drag it onto another. A ring shows on the face under your finger. Drop. "Same person?" opens. The face you dropped onto is the one that stays.
- [ ] 15. Tap "Merge". The dragged tile shrinks toward the other tile and fades. Then the grid shows "Merged into {name}." with "Undo". Check that the motion looks right and is not too fast or too slow.
- [ ] 16. Tap "Undo" inside the 6 seconds. Both tiles come back.
- [ ] 17. Watch the tile that you drag. Note whether the drop ring also shows on that tile itself. This is a known open item.
- [ ] 18. Drag a tile out of Lifeline into another app, for example a note. Note what the other app receives. The known behaviour is the plain text "lifeline-person:{id}".
- [ ] 19. Turn on Reduce Motion in Settings. Merge two people by drag. The tile only fades. It does not shrink or move.
- [ ] 20. A tap on a tile, with no long press, still opens the person's page.

## Large text and VoiceOver

- [ ] 21. Set the largest text size. The People grid is a list, and a long press does not drag. "Same as another person…" on a person's page still works. On the confirm, scroll to "Merge" and tap it.
- [ ] 22. Turn on VoiceOver. Do items 1 to 6 with VoiceOver. On the confirm, VoiceOver reads each picture with that person's name, once each. VoiceOver reads the "Merged into {name}." line when it shows.

## Also look at

- The held page (its person is gone and the line is up) cannot scroll. This is older behaviour (R34). Say whether "reads only" should still let you scroll.
- The copy on every screen of this check is a draft.

## If an item fails

Report the item number and what you saw to the builder session. When a PR exists, report it in the PR.
