# The photo picker opens with the person's name: device check

Spec: `docs/specs/2026-11-19-photo-search-name.md`. Run these lines on a phone. Lines 1 to 7 need iOS 27 or later. Sample names are invented.

1. [ ] Open the page of a person who is linked to a contact, and who has a name in Photos. Tap “…”, then “Add a photo”. The picker's search must hold the contact's full name.
2. [ ] The picker must show photos of that person. If it shows “No Results”, write down the name in the search and the name in Photos.
3. [ ] Tap the clear button in the search. The picker must show the whole library.
4. [ ] Pick two photos and confirm. Both must be on the page, in the order you picked them.
5. [ ] Open the page of a person with no linked contact. Tap “Add a photo”. The search must hold the name on the page.
6. [ ] Open the page of a person whose name has an apostrophe or an accent. Tap “Add a photo”. Write down the text in the search. On the simulator “Sam O'Neil” showed as “Sam ONeil”.
7. [ ] Open You, a place and a memory. Tap “Add a photo” on each. The search must be empty.
8. [ ] On a phone or a simulator with iOS 26: tap “Add a photo” on a person's page. The picker must open on the library, with no search text.

## Known small items

- With no match the first screen is “No Results”. The owner taps the clear button to see the library.
- The app cannot know if a name finds a photo. The picker runs outside the app.
