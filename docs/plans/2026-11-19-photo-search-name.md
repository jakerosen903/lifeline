# The photo picker opens with the person's name: implementation plan

Spec: `docs/specs/2026-11-19-photo-search-name.md` (approved by the owner on 2026-11-19). The owner tried the trial build on a phone with iOS 27 and said "Great looks good" on 2026-11-19. The owner then chose "plan and build it" with the full name, as the spec says.

Goal: on iOS 27 or later, "Add a photo" on a person's page opens the system picker with a name of that person in its search.

Branch: `photo-search-name`, cut from `phone/photos-contacts` (PC-b and photo-on-people-pages). Local only. The branch `photo-search-trial` is the throwaway trial and is not merged.

Execution: in the main session, one task after the other. The change is small: one pure rule, one parameter, three docs.

## Decisions made in this plan

1. The rule is `PhotoSearchName.text(type:isOwner:title:contact:)` in `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoSearchName.swift`. It is pure. It takes the page's `EntityType`, `isOwner`, the page's title and the page's `PersonContactState?`.
2. The contact's name is used only for the state `.linked(contactName:)`. The states `.missing`, `.notLinked`, `.noAccess` and `nil` use the page's title. This is the spec's "a linked contact that the app can see".
3. The text is trimmed of spaces and new lines at its ends. An empty result is nil.
4. `addPhotoFlow` gains a parameter `searchText: String? = nil`. Only `EntityScreen` passes a value. The memory page and You pass nothing.
5. The check for iOS 27 is in one private view extension in `AddPhotoFlow.swift`. The app's minimum stays iOS 26.0.
6. No UI test: the picker runs outside the app and the UI tests replace it with files. The device check carries the picker.
7. No migration. Nothing is stored.

## Global constraints

- The name goes to the system picker only. No log, no request, no alias.
- A view holds no rule: the view passes what the kit returns.
- Docs under `docs/` are in ASD-STE100 style. Sample names are invented.
- Commits: one imperative line. No AI attribution. Nothing is pushed.

## Review focus

1. A contact that is not in the owner's contacts now: the page's name is used, not the stale contact name.
2. The owner's page and a place: no text.
3. A name of spaces: no text, so the picker opens on the library.
4. iOS 26: the picker opens as before.
5. An apostrophe in a name: the simulator trial showed "Sam ONeil" for "Sam O'Neil". The app passes the name as it is. The device check has a line for it.

## Task 1: the rule (kit)

Files: create `ios/LifelineKit/Sources/LifelineKit/Photos/PhotoSearchName.swift`; test `ios/LifelineKit/Tests/LifelineKitTests/PhotoSearchNameTests.swift`.

- [ ] Write the table test `searchName` first. Rows (type, isOwner, title, contact, expected):
  - person, false, "Robin", `.linked(contactName: "Robin Okafor")` → "Robin Okafor"
  - person, false, "Robin", `.missing(contactName: "Robin Okafor", canSeeContacts: true)` → "Robin"
  - person, false, "Robin", `.missing(contactName: "Robin Okafor", canSeeContacts: false)` → "Robin"
  - person, false, "Robin", `.notLinked(suggestion: nil)` → "Robin"
  - person, false, "Robin", `.noAccess` → "Robin"
  - person, false, "Robin", nil → "Robin"
  - person, true, "Jordan", nil → nil
  - place, false, "Alder Street", nil → nil
  - person, false, "   ", nil → nil
  - person, false, "Robin", `.linked(contactName: "  ")` → "Robin"
  - person, false, " Sam O'Neil ", nil → "Sam O'Neil"
- [ ] Run it; it must fail to compile or fail on its assertions.
- [ ] Implement the rule. Run the test; it must pass.
- [ ] Commit.

## Task 2: the picker (app)

Files: `ios/Lifeline/Screens/Photos/AddPhotoFlow.swift`, `ios/Lifeline/Screens/Entities/EntityScreen.swift`, `ios/Lifeline/Screens/Entities/EntityViewModel.swift`.

- [ ] `EntityViewModel.photoSearchName: String?` returns `PhotoSearchName.text(type: entity.type, isOwner: isOwner, title: entity.title, contact: contact.state)`.
- [ ] `addPhotoFlow(... searchText: String? = nil ...)` passes the text to `AddPhotoFlow`. The real-picker branch applies `photosPickerSearchText(text)` when iOS is 27 or later and the text is not nil.
- [ ] `EntityScreen` passes `viewModel.photoSearchName`.
- [ ] Build the app. Run `PhotosUITests` (the add-photo flow) from a clean build.
- [ ] Commit.

## Task 3: docs

- [ ] `docs/DECISIONS.md`: an entry "2026-11-19 · The photo picker opens with the person's name", with the calls of the spec, the decisions of this plan and the open items.
- [ ] `docs/OVERVIEW.md`, "Photos": two sentences on the search text and on what leaves the app (nothing).
- [ ] `docs/plans/2026-11-19-photo-search-name-device-check.md`: the lines for the phone.
- [ ] The spec's status line says what is built.
- [ ] Run the kit tests and the guards. Commit.
