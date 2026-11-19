# A photo story's photo goes on the pages of its people

Status: approved by the owner on 2026-11-18, with approach A (the stored fact, one migration) and the calls in "Calls made without the owner" as written. The owner can still overrule each call. Plan: `docs/plans/2026-11-18-photo-on-people-pages.md`.

Changes: `docs/specs/2026-11-18-photo-card-key-photo.md` (the photo card). It reverses one rule of that spec: "a page link is always the person's tap".

Depends on: PR #31 (photo card and key photo) for part 1. Part 2 also needs PC-a of `docs/specs/2026-11-18-people-contacts.md` (the "Who is this?" sheet and the move).

## Why

The owner told a photo story about a person. Afterward the person's page did not show the photo. This happened two times on the phone:

1. The first story about a nephew. His page had no photo.
2. A story about a roommate. The owner changed the name to "Someone new". The new person's page had no photo.

The card waits for a tap on a chip each time. The owner expects the photo to be on the page of the person the story is about.

The owner's rule, said on 2026-11-18: the app can make an assumption, but it must be clear that it made the assumption, and it must be easy to change.

## Goals

- When the owner keeps a moment of a photo story, the photo goes on the page of each person the moment names.
- The card shows which pages the app chose. One tap takes the photo off a page.
- A choice the owner made is never reversed by the app.
- When the owner moves a name to a different person, a photo that the app put on the first person's page moves with the name.

## Non-goals

- Places, things and ideas. Their chips stay as they are: a tap adds the photo. A photo of a person at a beach is not always a photo for the page of the beach.
- The owner's own page ("You"). Most stories name the owner. The app does not put each photo on that page. The "You" chip stays a tap.
- Photos added from a page, and not from a photo story. Nothing changes for them.
- A rule that looks at the photo. The app does not see who is in the photo.

## Anti-goals

- The app must not put a photo on a page a second time after the owner took it off.
- The app must not take a photo off a page that the owner put it on.
- The app must not put a photo on the page of a hidden person.

## Behaviour

### Part 1: a kept moment puts the photo on its people's pages

1. The trigger is the same write that puts the photo on a kept moment of a photo story.
2. For each person the kept moment names, the write also puts the photo on the person's page. The link records that the story made it (see "The stored fact").
3. The write skips a person when one of these is true:
   - The person is the owner.
   - The person is hidden.
   - The page holds the photo already.
   - The owner took this photo off this page before.
4. The photo goes last in the page's order. On a page with no photo it is the first photo, so it is the key photo. The owner can drag a different photo to the front.
5. A name link with the origin `assumed` counts. The person chip on the moment shows "Assumed" already, and the photo follows that guess. Part 2 moves the photo when the owner corrects the guess.

### The card

1. A chip for a page that the story chose looks the same as a chip the owner tapped: filled, with a tick.
2. While the card shows a page the story chose, the line under "Also show this photo on" reads: "The people in this story have this photo on their pages. Tap to take it off, or to add it to another page."
3. With no such page, the line stays "Tap to add. Tap again to take it off."
4. VoiceOver reads a chip the story chose as "{name}, added by this story". A chip the owner tapped stays "{name}, added".
5. A tap on a filled chip takes the photo off the page, as today. The app records that the owner took it off.
6. A tap on an empty chip adds the photo, as today. The link is now the owner's.

### Part 2: the photo follows a moved name

This part applies when the owner changes who a name means in a photo story ("Who is this?", then a different person or "Someone new").

1. After the move, for the photo of that story:
   - The photo goes on the new person's page by the rules of part 1.
   - The photo comes off the first person's page when all of these are true: the story made that link; no kept moment of the story names the first person now; the owner did not change the link.
2. A link the owner made stays. A photo the first person's page held before the story stays.
3. The move's Undo puts the photo links back with the name links, in the same write.
4. "Not a person" removes the story's link from the first person's page by the same test. It adds no link.

## The stored fact

The app must know two things that it does not store today: which link a story made, and which page the owner took a photo off.

### Approaches

**A. Store both (recommended).** A new migration adds one column and one table:
- `photo_link.origin`: `story` for a link a photo story made. Empty for every other link, old and new.
- `photo_page_declined (photo_id, entity_id)`: the owner took this photo off this page.

Cost: one migration. It is additive. No existing row changes. It must be numbered after the last migration on `main` when it merges; PC-b can add one too, so the two builds must agree on the numbers.
Gain: every rule above is exact. The card can say "added by this story". The move never removes a link the owner made.

**B. Store nothing.** The write adds the photo only when the kept moment is the first kept moment of the story that names the person. A later moment that names the same person adds nothing, so a photo the owner took off does not come back.
Cost: the card cannot tell a story's choice from the owner's tap. Part 2 cannot tell either, so a move can remove a photo the owner put on a page, or must never remove. If the owner removes the first moment and keeps another, the photo can come back.
Gain: no migration.

**C. Offer, do not add.** The card puts the people's chips first with a button "Add to all {n}". Nothing is added without a tap.
Cost: it does not fix the reported problem. The owner must still tap after each story.
Gain: the old rule stays.

The spec takes approach A. The owner's rule needs the app to show its assumption and to respect a correction. Both need the stored fact.

## Edge cases

- A moment names a person two times: one link.
- Two moments of the story name the same person: the first keep adds the link, the second finds it.
- The owner removes a kept moment from the photo (the moments sheet): the photo stays on the people's pages. The owner takes it off with the chip.
- The owner removes the photo from the story: links the story made are removed in the same write. Links the owner made stay.
- A moment is kept, then the session is deleted: the photo's links follow the rules that exist today for a deleted session.
- A person is merged or deleted later: the link follows the entity, as every photo link does today.
- A kill between the keep and the page link cannot happen: they are one write.
- A story with no photo: nothing changes.
- A moment kept before this build: no link is added for it. The owner can tap the chip.

## Tests the plan must have

- Kit: a kept moment that names a person puts the photo on the page with origin `story`; the owner, a hidden person and a declined page are skipped; a page that holds the photo is not written; the order rule (last, or key photo on an empty page).
- Kit: take off then keep another moment that names the same person: no link.
- Kit: the move adds to the new person and removes the story's link from the first; it leaves the owner's link; Undo restores both.
- Kit: the migration on a populated database keeps every row, and old links have an empty origin.
- UI: after Keep, the person's chip is filled and the line changes; the person's page shows the photo; a tap takes it off and it stays off after the next Keep.

## Calls made without the owner

1. People only. Places, things and ideas stay a tap.
2. Not the owner's own page.
3. An `assumed` name link also places the photo.
4. The chip looks the same for both kinds; the line of text and VoiceOver carry the difference. No "Assumed" mark on the chip.
5. Removing a moment from the photo does not take the photo off the people's pages.
6. Moments kept before this build get no link.
7. Approach A, with one additive migration.

## Left to the builder

- The names of the column, the table and the migration number.
- Where the write lives. Today the memory insert links the session's subject photo to the kept memory (`PhotoRepository`, the link of a segment's subject photo). The page links belong in that same write. The move is in `PersonLinkWrites`.
- How the receipt of a move carries the photo links for Undo.
