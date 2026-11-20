# Device check: the Things shelf (S7)

**No check on this list has been run.** The owner runs it on the iPhone, with the real archive, on branch `sections-things`. Tick each line when it is true. Kit tests and UI tests are recorded in the ledger (`.superpowers/sdd/2026-11-20-things-shelf/`).

This build adds no migration. It only reads. You do not need a backup for this build's own changes. Keep your usual "Your copy" habit.

## The shelf

- [ ] 1. Things opens on the shelf, not on a list. The tiles in each row are one height. The title, the count and the quote read without clipping at the default text size.
- [ ] 2. The shelf opens without a visible wait on the full archive. Switch to Things from another tab five times. If you see a hitch, write down the number of memories in the archive.
- [ ] 3. The shelf shows no number of things, no "add" button, no empty photo slot and no "add a date" prompt.
- [ ] 4. No tile shows a year, a year range or a date.
- [ ] 5. A long title is cut with "…" at the default text size. At the largest accessibility text size it reads in full.
- [ ] 6. At the largest accessibility text size the grid is one column, and nothing is cut.
- [ ] 7. After the check at the largest size, set the text size back to your usual size.

## Photos

- [ ] 8. A thing with a key photo shows the photo on its tile.
- [ ] 9. Change the key photo on a thing's page. Go back. The tile shows the new key photo.
- [ ] 10. A thing whose key photo cannot load shows a sand area. The title and the count stay.

## Periods and guesses

- [ ] 11. The headings are the Timeline's waypoint text, for example "Teens · by your age". "Not placed in time yet" is the last group, when it has a tile.
- [ ] 12. A thing whose only dated moment has a date the app guessed shows "Placed by a guess". Open the moment's memory, use "Tell me when" and say a year. Go back. The line goes.
- [ ] 13. A thing whose only date is "before" or "after" something (you answered "Was this before or after…?") shows "Placed by a guess" (ruling R4).
- [ ] 14. Use "Add dates" on a thing's page, for example 1996 to 2002. Go back. The tile sits in the period of those years and has no "Placed by a guess" (ruling R5).
- [ ] 15. Tell a new story that names the same thing, with a date the app guesses in another period. Go back to Things. The tile stays in the years you gave and still has no "Placed by a guess" (ruling R5).
- [ ] 16. A thing that you dated with your own "around 1998" shows no "Placed by a guess".

## Quotes

- [ ] 17. A quote never shows filler words ("um", "uh").
- [ ] 18. A thing whose only line came from a session where something hard was said, or a session you stopped, shows no quote.
- [ ] 19. Hide the memory that gave a tile its quote. Go back. The quote goes (another line can take its place).
- [ ] 20. Use a thing with no "Add dates". Hide the memory that dates it. Go back. The tile moves to the period of its next dated moment, or to "Not placed in time yet" when it has none.

## VoiceOver

- [ ] 21. With VoiceOver on, swipe through the shelf. Each tile is one element. VoiceOver reads the title, then the count, the guess line and the quote. It does not step into the texts inside a tile (ruling R3).
- [ ] 22. VoiceOver does not describe a photo.
- [ ] 23. Set the rotor to Headings. Swipe up and down. The rotor moves between the periods and "Not placed in time yet".

## Taps, tags and sessions

- [ ] 24. Tap a tile. The thing's page opens. The record bar reads "Tell a story about {title}". Back returns to the shelf, and the bar reads "Tell a story".
- [ ] 25. Start a story from the shelf. After it lands, a new thing from it shows on the shelf without leaving the tab.
- [ ] 26. The tag filter on Things narrows the shelf. "Everything" brings every tile back. A tag that matches nothing shows "Nothing tagged “{tag}”."

## Appearance and privacy

- [ ] 27. With Reduce Transparency on, and in dark appearance, the sand tiles and the ochre "Placed by a guess" line stay readable. Write down what you see: the dark colour values have no PR yet.
- [ ] 28. In Airplane Mode the shelf looks the same.
