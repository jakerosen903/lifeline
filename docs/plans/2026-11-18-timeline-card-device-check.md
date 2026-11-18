# Device check: the Timeline's pinned card (S6b)

Use the owner's iPhone with the owner's real archive, on branch `sections-strip`. Tick each line when it is true. Kit tests and UI tests are recorded in the ledger.

- [ ] 1. Back up the archive with "Your copy", then install.
- [ ] 2. Open the Timeline. A card must sit under the title. It must show a strip, a start year, and "now".
- [ ] 3. The strip must start at your birth year. A moment dated before your birth year must move the start to that moment. With no birth date, the strip must start at your earliest dated moment.
- [ ] 4. Each dated moment must have one tick. A moment with a range must have a tick at the start of its range.
- [ ] 5. A guessed date must have a hollow tick. A date you stated must have a solid tick. The two must differ by shape, not by colour alone.
- [ ] 6. A frame must cover part of the strip. It must cover the years of the rows on screen.
- [ ] 7. Scroll the list slowly. The frame must move with the list and must follow it without a jump.
- [ ] 8. Turn on Reduce Motion. Scroll again. The frame must move without animation.
- [ ] 9. Scroll to the top, where the waiting cards show. The card must stay over them. The frame must keep its last years.
- [ ] 10. Scroll to the end of the list, over the shelf "Not placed in time yet". The card must stay. The frame must keep its last years.
- [ ] 11. Leave the Timeline tab and come back. The frame must still cover the years of the rows on screen.
- [ ] 12. Open a story that has two or more moments. The frame must follow the rows now on screen, with no scroll.
- [ ] 13. Open the life map from the "…" menu. State years for two chapters that overlap, for example 2008 to 2012 and 2010 to 2014. Close the map. Scroll until the frame covers those years. The card must show the line "During" with both names, the longer chapter first, joined by " · ".
- [ ] 14. Scroll to years that no chapter covers. The "During" line must go. No word "During" and no empty line must show. The card must show the strip alone.
- [ ] 15. Use a chapter that has stated years. Scroll slowly across the card's edge, where a row is half under the card. The app must stay responsive. The scroll must not stop or stutter.
- [ ] 16. Give the app many chapters over the same years (use a spare copy if you have one). The "During" line must show the names that fit and "+N" at the trailing edge. The card must not grow past two lines of names.
- [ ] 17. A chapter with no name must never show in the "During" line.
- [ ] 18. A moment whose date is inside a chapter's years must have no tag unless you added it. The "During" line must not tag a moment.
- [ ] 19. A chapter whose years hold no moment must still show in the "During" line when the frame covers its years. No row must get a tag.
- [ ] 20. The card must show no count of what is missing. It must ask for nothing. A chapter's years must show only when you stated them.
- [ ] 21. Tap the card. The life map must open with the title "Chapters". "Done" must return to the Timeline with the card in place.
- [ ] 22. Put a finger on the strip and drag up and down. The list must scroll as it does anywhere else. The strip must not act as a scrubber.
- [ ] 23. Open the Timeline's "…" menu. "Chapters" must still be there and must still open the life map.
- [ ] 24. With a spare copy that has no dated moment, the Timeline must show no card. "Chapters" in the "…" menu must still open the life map.
- [ ] 25. Turn on VoiceOver. The card must read as one element, in one sentence, for example "Your life from 1998 to now. On screen: 1998 to 2003. During Maple Street, Summers at the lake and 2 more." With one year on screen it must read "On screen: 1999." With no chapter it must have no "During" sentence. The hint must be "Opens your chapters", and the trait must be "button".
- [ ] 26. With VoiceOver on, move through the list. The rows under the card must stay reachable.
- [ ] 27. Set the text to the largest accessibility size. The card must be under half the screen. The "During" line must wrap to two lines before it truncates. The first row of the spine must be reachable after at most one swipe.
- [ ] 28. At the largest text size, open a story and look at the period label above it. Report any cut at the card's edge. The label may lose a few points (a known cost).
- [ ] 29. Turn on Dark appearance. The card, the frame, the ticks and the names must be readable. There is no dark palette yet, so report what you see.

## Screenshots

The controller makes these on the iPhone 17 Pro simulator (iOS 26.3) with the invented `-uiTesting-seedSpine` seed, after the final review. They go in `docs/screenshots/timeline-card/`. `before-top.png` comes from `main`. The others come from this branch.

| File | What it shows |
| --- | --- |
| `before-top.png` | The top of the Timeline on `main`, with no card. |
| `after-top.png` | The top of the Timeline with the card. |
| `after-during.png` | The card with a "During" line. |
| `after-end.png` | The end of the list, with the card over the shelf. |
| `after-largest-text.png` | The card at the largest text size. |
