# Picker scroll

**Status:** Decided by the builder. The owner can overrule it. **Date:** 2026-11-19.

**Builds on:** `docs/specs/2026-11-16-photo-story.md` (the sheet that starts a photo story).

## The report

The owner used the app on a phone with iOS 27. The owner reported: "The photos picker is a little buggy. When I swipe it sometimes just swipes uncontrollably."

We did not reproduce it. We have no device with iOS 27. The two causes below are inferences from the code. Nobody saw them happen.

## Cause 1 (inference): the grid redraws every tile for each thumbnail

- The Favorites grid (`FavoritesGridScreen`) reads each tile's image from one dictionary on `PhotoStoryStartViewModel`.
- The dictionary changes each time one thumbnail arrives.
- With `@Observable`, each change redraws every visible tile.
- During a fling, many thumbnails arrive close together. The grid then redraws in bursts while it scrolls. This can make the scroll stutter or jump.

## Cause 2 (inference): the picker and the sheet both take a downward swipe

- "All photos", and a start with no access or no photos, show the system picker inline in the sheet.
- The picker's grid runs in another process.
- A downward swipe on the picker can scroll the picker or pull the sheet down. The two can fight.

## Fix 1

- Each tile must own its image. One arrival must redraw one tile only.
- The view model must keep the thumbnails that arrived in a cache that the views do not observe.
- A tile that scrolls away and comes back must show its cached image at once.
- A tile that leaves the screen cancels its load. A cancelled load must not store anything and must not crash.

## Fix 2

- While the system picker shows, the sheet must not close with a swipe.
- The picker shows when the route is `.picker` or when "All photos" was tapped (`showsAllPhotos`).
- "Cancel" must still close the sheet.
- After "All photos", the picker is a pushed screen with "Back" and no "Cancel". "Back" returns to the grid, where "Cancel" and the swipe work.
- The explanation and the Favorites grid must keep swipe-to-dismiss.
- The rule is a pure function in `LifelineKit` with a test.

## Not known

- We do not know if either cause is the real one. The owner may have seen a third cause.
- We do not know if iOS 27 changed how an inline picker shares a swipe with its sheet.
- The UI tests cannot drive the system picker. Fix 2 is tested only as a rule.

## How the owner confirms on the phone

1. Open "Tell a story about a photo". Fling the Favorites grid up and down fast. The grid must scroll smoothly and stop where the finger leaves it.
2. Tap "All photos". Swipe down on the picker many times. The picker must scroll and the sheet must stay. "Back", then "Cancel", must close it.
3. Tell us if the uncontrolled swipe still happens, and on which screen.
