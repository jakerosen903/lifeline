# The photo picker opens with the person's name in its search

Status: approved by the owner on 2026-11-19, with the calls in "Calls made without the owner" as written. The owner can still overrule each call. The owner tried the trial build on a phone with iOS 27 on 2026-11-19 and said "Great looks good". Plan: `docs/plans/2026-11-19-photo-search-name.md`. Built on branch `photo-search-name`; the device check has not been run on the final build.

Depends on: PC-b of `docs/specs/2026-11-18-people-contacts.md` (a person can be linked to a contact) and part 4 of `docs/specs/2026-11-18-photo-on-people-pages.md` (several photos at one time). Neither is on `main` on 2026-11-19.

Sample names in this spec are invented.

## Why

The owner adds photos to a person's page. The system picker opens on the whole library. The owner must find the person's photos by hand, or type the name in the picker's search.

The owner's words on 2026-11-19: "would we be able to make it that it auto fills a search for the persons name in photos when we have linked to a contact?"

## What the system allows

These facts come from the headers of the iOS 27.2 SDK in Xcode 27.2. They are not tested on a device.

- iOS 27 adds a search text to the picker: `photosPickerSearchText(_ searchText: String?)` in SwiftUI, and `PHPickerConfiguration.searchText` with `PHPickerSearchText(string:)`.
- iOS 26 has no such control. The app's minimum stays iOS 26.0.
- The picker runs outside the app. The app gives it the text. The app does not see the results, and it does not see the library.
- The app cannot read the names of the people in the owner's Photos library. So the app cannot know if a name will find a photo.

## Goals

- On a phone with iOS 27 or later, "Add a photo" on a person's page opens the picker with a name of that person in the search.
- The owner sees the text the app put there, and can remove it.
- On iOS 26 nothing changes.

## Non-goals

- The picker that starts a photo story. It is not tied to one person.
- The pages of places, things, ideas and memories. A later spec can add a place's name.
- The owner's own page ("You").
- A search that the app runs itself. The app asks for no access to the photo library.
- A change of the app's minimum iOS version.

## Anti-goals

- The name must not leave the phone. It goes to the system picker only.
- The app must not save the name of a contact as an alias, or send it to the model. The rule of the contacts spec stays: nothing from a contact goes to the model.
- The search text must not stop the owner from seeing the whole library. One action in the picker must show every photo again.

## Behaviour

1. The text is chosen by one rule, in LifelineKit:
   - The person has a linked contact that the app can see: the text is the contact's full name, as kept at the link.
   - The person has no linked contact, or the link reads "not in your contacts": the text is the person's name on the page.
   - The page is the owner's, or the page is not a person: no text.
   - A name that is empty, or only spaces, gives no text.
2. On iOS 27 or later, "Add a photo" on a person's page gives this text to the picker.
3. On iOS 26, and when the rule gives no text, the picker opens as it does today.
4. The picker shows the text in its own search field. The owner clears it in the picker. The app adds no control of its own.
5. The text is given each time the picker opens. The app does not remember that the owner cleared it.
6. Each other rule of "Add a photo" stays: up to 20 photos, the order, the progress line, the failure line.

## Approaches

**A. Give the name to the system picker (recommended).** One pure function chooses the text. One line gives it to the picker, behind a check for iOS 27.
Cost: it works on iOS 27 only. The app cannot know if the search finds a photo.
Gain: no new permission. The library stays out of the app.

**B. A line above the picker: "Search for {name}".** The app shows the name. The owner types it.
Cost: it does not fill the search. It adds a line to the page.
Gain: it works on iOS 26.

**C. The app's own picker.** The app asks for access to the whole library and shows its own grid.
Cost: a new permission, and a second picker to build and keep. The app still cannot read the People names of Photos, so it cannot search by person.
Gain: none for this need.

The spec takes approach A.

## Before the build: one check on a device

The headers do not say how the picker behaves. One short trial on a phone or a simulator with iOS 27 must answer these questions before the plan is written:

1. Does a name that matches a person in Photos show that person's photos?
2. What does the picker show when the name matches nothing? An empty screen with no clear way back to the library fails the third anti-goal.
3. Does the full name of a contact match as well as the given name alone?
4. Does the text work with the multi-photo picker of "Add a photo" (the `photosPicker` modifier with an ordered selection)?

If answer 2 or 3 is bad, the spec changes before the build. The possible changes: use the given name only, or take approach B.

### Result of the trial on the simulator (2026-11-19)

The trial ran on the iPhone 18 Pro simulator with iOS 27.2. A throwaway change gave a fixed text to the picker of "Add a photo". The change is not in the branch.

- Question 4: yes. The multi-photo picker opens with the text in its search field.
- Question 2: with no match the picker shows "No Results" and "There were no results. Try a new search." The search field has a clear button, and a close button is next to it. One tap shows the library again. So the third anti-goal holds, but the first screen the owner sees is empty.
- The text "Sam O'Neil" showed as "Sam ONeil". The apostrophe was removed. The trial does not show where.
- Questions 1 and 3: not answered. The simulator's library has six stock photos and no named person. The word "flowers" found nothing there, so the simulator does not index its photos for search. A phone with iOS 27 and named people in Photos must answer these two questions.

## Edge cases

- The owner renames the person: the next picker uses the new name, or the contact's name when a contact is linked.
- The contact is renamed: the kept name is updated by the contact check of PC-b. The next picker uses it.
- Two people have one name: both pages give the same text. The picker shows the same results for both.
- The name has characters the search treats in a special way: the app gives the name as it is. The trial must include one name with an apostrophe.
- UI tests replace the picker with files (`-uiTesting-pickPhotos`). The text has no effect there.

## Tests the plan must have

- Kit: a table test of the rule: linked contact, contact not in contacts, no contact, the owner, a place, an empty name, a name of spaces.
- Kit or app: on a page that is not a person the flow gets no text.
- Device check: the four questions above, on iOS 27, and one line that the picker is unchanged on iOS 26.
- No UI test can drive the system picker. The device check carries the behaviour of the picker.

## Calls made without the owner

1. A person with no linked contact also gets the text, from the person's name. The owner asked for the linked case only.
2. The contact's full name is used, not the given name. The trial can change this.
3. Only "Add a photo" on a person's page. Not the start of a photo story.
4. The app does not remember a cleared search.
5. No setting turns this off.

## Left to the builder

- The name and place of the rule in LifelineKit.
- How the text reaches `AddPhotoFlow` (a new parameter of `addPhotoFlow`).
- The entry in `docs/DECISIONS.md` when the owner approves.
