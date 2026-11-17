# S4 Photos: device check

Run this on the iPhone with the S4 build. Tick each line. Say what looks wrong.

1. [ ] "Add a photo" on Maya's page opens the system picker, and no permission prompt shows, before or after.
2. [ ] Pick a HEIC photo, a screenshot (PNG) and a photo from iCloud that is not on the phone. Each shows upright as the cover, and "Adding the photo…" shows while the iCloud one downloads.
3. [ ] Pick a wide-colour (Display P3) photo. Its colours on the page match the Photos app.
4. [ ] Pick a photo taken with location on. The caption says "taken {date}". No place, map or memory changes. Export a copy, unzip it on a Mac, and check with Preview's inspector that the file in `photos/` has no GPS and no EXIF date.
5. [ ] Delete the original in the Photos app. The photo stays in Lifeline.
6. [ ] In Settings, iCloud Backup shows that Lifeline's backup size did not grow by the photos' size.
7. [ ] Remove a cover. The next photo becomes the cover. Remove the last. The tile shows its letter, and the page has no header or empty frame.
8. [ ] Scroll a People grid with 20 covers quickly. Nothing stalls.
9. [ ] With VoiceOver, the header reads "Photo of Maya, taken {date}", and a tile reads only the name and "my sister".
10. [ ] Export a copy, restore it, relaunch. Every photo is back. Restore a copy made before this build. It opens and has no photos.
11. [ ] After "Make this the cover" lower on a page, the page scrolls to its top and shows the new cover. Say if this is unwanted.
12. [ ] The photo viewer's "Done" has no glass background. Say if this is unwanted.
