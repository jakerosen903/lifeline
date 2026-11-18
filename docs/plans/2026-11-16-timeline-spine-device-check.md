# Device check: the Timeline spine (S6a)

Use the owner's iPhone with the owner's real archive, on branch `sections-timeline`. Tick each line when it is true.

- [ ] 1. Back up the archive, then install. Every earlier memory that had a date is on the spine.
- [ ] 2. The three old chapters with no moments do not show. No "Untitled chapter". No "Outside any chapter".
- [ ] 3. The spine is one unbroken line from the first moment to the last, through every gap and waypoint.
- [ ] 4. A long quiet stretch is visibly longer than a short one, and its label gives the right number of years.
- [ ] 5. A date you are unsure of looks different from a date you stated, without relying on colour.
- [ ] 6. The waypoints match your age at the time.
- [ ] 7. At the largest text size nothing clips, and each date is readable.
- [ ] 8. VoiceOver reads a row as title, date, people, and the chapter when there is one. It reads each waypoint and each gap label.
- [ ] 9. Dark appearance: the spine and the marks are visible. There is no dark palette yet. Report what you see.
- [ ] 10. Open a story on the spine. Its moments show under it, and the spine continues beside them.

## Added while building

- [ ] 11. Open a story with two or more moments. Press and hold the second moment. The menu must act on that moment. Check with "Hide from timeline", then show hidden memories and unhide it.
- [ ] 12. Open a story. The list scrolls so its moments are above the record bar. Say if the jump feels wrong.
- [ ] 13. Open the last story on the Timeline. Its last moment must sit above the record bar, and the spine must end at that moment.
- [ ] 14. Open a story on the shelf ("Somewhere in your story"). The list must scroll to that story.
- [ ] 15. Turn on Reduce Motion. Open a story. The list must move with no animation.
- [ ] 16. Find a moment with a relation date ("before ..."). Its margin must be empty and its row must show the full text.
- [ ] 17. Find a moment placed by age. Its row must show the age ("age ~7").
- [ ] 18. At the largest text size, the date must sit above the title on every row, moments and stories.
- [ ] 19. Tap the empty right side of a row. It must open the moment, or open the story.
- [ ] 20. A long Check-this tag must wrap, not push the "..." menu off the screen.
- [ ] 21. Find a moment whose date is a guess over two years ("around 1999–2000"). The margin must say "around".
- [ ] 22. Find a moment with a relation date. The gaps above and below it must show no "years" label.

## Screenshots

Screenshots are in `docs/screenshots/timeline-spine/`. All were taken on the iPhone 17 Pro simulator (iOS 26.3) with the invented `-uiTesting-seedSpine` seed. "Before" is `origin/main` with the seed added. Earlier screenshot folders have no README, so this table lives here.

| File | What it shows |
| --- | --- |
| `before-top.png` | The Timeline at the top, before the spine. |
| `before-gap.png` | The Timeline scrolled to a long quiet stretch, before. |
| `before-largest-text.png` | The Timeline at the largest text size, before. |
| `before-row-menu.png` | A row's "..." menu, before. |
| `after-top.png` | The spine at the top: marks, margin years, waypoints. |
| `after-gap.png` | The spine scrolled to a gap: dashed spine and "{n} years" label. |
| `after-largest-text.png` | The spine at the largest text size: the date above the title. |
| `after-row-menu.png` | A spine row's "..." menu. |
| `after-open-story.png` | An open story with its moments under it and the spine beside them. |
