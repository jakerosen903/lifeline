# Device check: chapters as names with stated years (S6c)

Use the owner's iPhone with the owner's real archive, on branch `sections-chapters`. Tick each line when it is true. Kit tests and UI tests are recorded in the ledger.

- [ ] 1. Back up the archive with "Your copy", then install.
- [ ] 2. Open the Timeline's "…" menu and tap "Chapters". The life map opens with the title "Chapters".
- [ ] 3. Find a chapter that had dates before this build. It must show "No dates yet". It must sit under "Not placed in time yet", with a "Say when" button.
- [ ] 4. The life map shows no number for what is missing, and no empty frame.
- [ ] 5. Tap a tag on a Timeline row. The chapter's sheet opens, and it is the right chapter.
- [ ] 6. In the chapter's sheet, tap "Rename". Give the chapter a new name. The tag on the Timeline shows the new name.
- [ ] 7. Rename a chapter to the name of another chapter. The sheet must say "You already have a chapter with this name." Neither chapter changes. Cancel, and the message goes.
- [ ] 8. Clear the name in the rename field. Save must be disabled.
- [ ] 9. Tap "Say when it was" and state years, for example 2008 to 2012. The chapter shows those years and moves out of "Not placed in time yet". Its bar sits at the right place on the axis.
- [ ] 10. Open a moment's "…" menu and tap "Add to a chapter…". Type a new name. The moment shows the new tag, and the life map shows the new chapter.
- [ ] 11. Tap "Add to a chapter…" on another moment and choose an existing chapter by name. The moment shows that tag. No second chapter with the same name shows.
- [ ] 12. Open the "…" menu of a tagged moment and tap "Take out of “{name}”". The tag goes and the moment stays. Then check the chapter on the life map. There are two cases:
  - The moment was the only moment in a chapter with no name and no years. The chapter must go from the life map.
  - The moment was the only moment in a named chapter. The chapter must stay on the life map, with no moments.
- [ ] 13. Remove a real chapter: open its sheet, tap "Remove chapter…". The question says "Removing a chapter never removes a memory. Its moments stay on your timeline." Confirm. Every moment stays on the Timeline, with no tag.
- [ ] 14. After the removal the notice "Removed “{name}”." shows with "Undo". Tap "Undo" within 6 seconds. The chapter and its tags come back, with its years.
- [ ] 15. Remove a chapter again and wait. The notice must leave after 6 seconds.
- [ ] 16. Remove a chapter, then tag one of its moments to another chapter inside the 6 seconds, then tap "Undo". The moment must keep the other chapter.
- [ ] 17. A chapter with no name shows as "No name yet" on the life map. It shows nowhere on the Timeline. "Untitled chapter" does not show anywhere. If your archive has none, skip this line and say so.
- [ ] 18. Find a moment whose date is inside a chapter's years. It must have no tag unless you added it.
- [ ] 19. Find a moment you put in a chapter whose date is outside the chapter's years. It must keep its tag.
- [ ] 20. A chapter that you named with a long name: the name on the life map must be readable. It must not be cut to "…" or hidden.
- [ ] 21. Open the life map with your real number of chapters. It scrolls, it reads in order, and each bar sits where its years are.
- [ ] 22. With no chapters (use a spare copy if you have one), the life map shows only "A chapter is a name you gave to a stretch of your life."
- [ ] 23. VoiceOver reads a life map row as the name, then the years, then the number of moments. A chapter with no years reads "No dates yet".
- [ ] 24. VoiceOver reads a tag on a Timeline row as the chapter's name and the word "button". The hint is "Opens this chapter".
- [ ] 25. At the largest text size the life map, the chapter's sheet and the add sheet show nothing clipped. Each name and each year is readable.
- [ ] 26. The tag's tap area does not take a tap meant for the memory. Tap the right end of a row's text, near the tag, and check which one opens.
- [ ] 27. Turn on Dark appearance. Open the Timeline and the life map. Each tag, each bar and each chapter name must be readable against its background. There is no dark palette yet, so report what you see.
- [ ] 28. Turn on Reduce Motion. Remove a chapter and wait 6 seconds. The notice must show and go with no fade. Open and close the life map and a chapter's sheet. They must open and close as the other sheets in the app do, with no extra motion.

## Screenshots

Screenshots are in `docs/screenshots/timeline-chapters/`. All were taken on the iPhone 17 Pro simulator (iOS 26.3) with the invented `-uiTesting-seedSpine` seed. They are "after" only: the sheets and the life map did not exist before, so a "before" shows nothing (ruling R6 in the ledger).

| File | What it shows |
| --- | --- |
| `after-timeline-tag.png` | The Timeline with a chapter tag on a row. |
| `after-add-to-chapter.png` | The "Add to a chapter…" sheet. |
| `after-chapter-sheet.png` | The chapter's sheet: Rename, Say when it was, Remove chapter…. |
| `after-life-map.png` | The life map with a chapter that has years and one under "Not placed in time yet". |
| `after-removed-notice.png` | The notice "Removed “{name}”." with Undo. |
| `after-life-map-largest-text.png` | The life map at the largest text size. |
