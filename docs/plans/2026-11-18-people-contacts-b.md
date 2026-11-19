# PC-b: A Person Can Be Linked to a Contact — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Approved by the owner on 2026-11-18, with the ten plan decisions as written. Each decision stays open to an overrule.

**Goal:** The owner can link a person to one of their contacts, and the app can do it for a new name that fits exactly one contact. A linked person shows the contact's name and picture. The link stays correct when the contact changes. The app works with full, limited or no access to contacts.

**Architecture:** The kit gets one protocol, `ContactsDirectory`, and one actions type, `ContactLinkActions`. The app target has the only file that imports the Contacts framework. Keep already runs the seven rules of `PersonGuess`; this plan gives it real contacts through a cache, and builds the person that rules 3 and 5 call for. The sheet and the person's page get their contact rows. No migration: `v15` already has every column and table.

**Tech Stack:** Swift 6, SwiftUI on iOS 26, GRDB, Swift Testing, XCUITest, Contacts and ContactsUI (`CNContactStore`, `ContactAccessButton`). No new dependency. No network call. No prompt change.

**Spec:** `docs/specs/2026-11-18-people-contacts.md`, section "Contacts" and the contact parts of "Matching a said name", "Settling a guess", "Edge cases" and "Test plan". Mock-ups: `docs/design/PC2_WhoIsThis.dc.html`, `PC3_PersonLinked.dc.html`, `PC4_NoContact.dc.html`.

**Not this plan:** PC-c (merge two people, the drag) and PC-d (extractor handles).

**Worktree and branch:** `.claude/worktrees/people-contacts-16241d`. A new branch `claude/people-contacts-b`, cut from the tip of `claude/people-contacts-16241d` (PC-a with `main` merged in). Never push. Never open a PR without the owner's word. No AI attribution in a commit.

---

## What the owner gets

The owner asked on the phone: "How do I link it to a contact though?" After this plan:

1. A person's page has a row. It reads "Not linked to a contact" with the button "Link to a contact", or "Linked to {contact name} in your contacts" with "Change".
2. "Link to a contact" opens a search of the owner's contacts. One tap links.
3. The "Who is this?" sheet lists the contacts that fit the said name, and has "Search your contacts".
4. A new name that fits exactly one contact is linked on Keep, with the mark "Assumed · new, from your contacts".
5. The contact's picture becomes the person's first picture when the person has none.

## Decisions made in this plan

The spec leaves these open. The owner can overrule each one before work starts.

1. **No migration.** `v15` has the columns (`contact_identifier`, `contact_name`, `contact_state`, `contact_photo_id`, `name_origin`) and the tables (`contact_declined`, `candidate_person_choice`). The phone has `v14` and `v15` recorded. A later migration, if one is ever needed, comes after `v15`.
2. **This plan does not need the `photo-card` branch (PR #31).** The contact's picture goes in with `PhotoLibrary.add`, which puts a photo last. A person with no photo therefore gets it as the first photo. A new contact picture replaces the old copy with `add`, `setCover`, then `remove`. All three exist on `main`. When PR #31 merges, `setCover` moves a photo to the front through the same order, and the owner can drag another photo in front. No code in this plan sets `sort_order` itself.
3. **Contacts are read into a cache, not on each guess.** `ContactsCache` holds the names of the contacts the app can see. The app fills it off the main thread at launch, after access is given, and when the system says contacts changed. Keep and the card preview read the cache. The spec says "once for each recording"; a cache that follows the system's change notice is simpler and is never older than that.
4. **The forced merge waits for PC-c.** When the owner picks a contact that another person holds, the app refuses and says who holds it. The spec's "Same person?" question needs the merge of two people, which is PC-c.
5. **The line for a new person has three forms.** "New · not in your contacts" when the app can see contacts and none fits the said name. "New · not linked yet" when one or more fit. "New" when the app cannot see contacts. The app works the line out when it shows the chip. It stores nothing new.
6. **The system prompt shows by itself, once, on the landing** of the first recording with a kept person, as the spec says. The app keeps "asked" in `UserDefaults`. If the owner finds an unasked system prompt abrupt, the other option is a line on the landing with a button.
7. **After access is given on the landing, the app looks again at that recording only.** For each link with origin `new` whose person the app made and nobody edited: when exactly one free contact fits the said name, the app links that person to the contact and the link becomes `assumed`. An `assumed` link to a person on file does not change (rule 4).
8. **The contact picker is the app's own list**, built from `ContactsDirectory`, not Apple's `CNContactPickerViewController`. The sheet's search and the page's "Link to a contact" share it. Under limited access it shows `ContactAccessButton`.
9. **Search matches** the contact's full name, given name, family name and nickname, by the comparison in the spec (case, outer whitespace and diacritics ignored), on a prefix of any word.
10. **A changed picture is found by the photo store.** The app stores the contact's current picture. When the store returns the photo the person already has as the contact's copy, nothing changed.

### Limits found while planning

- **The simulator has no real prompt path for limited access in tests.** The UI tests use a scripted directory. The device check covers the system prompt, limited access and `ContactAccessButton`.
- **`CNContact.identifier` is valid on one phone.** After a restore to another phone the app links again by an exact, single name match (spec call 12).
- **`guessInputs` reads every person for every segment** (a PC-a deferred minor). With contacts on this path it must read the cache, never the contact store. Task 2 holds this.
- **PC-a's open points stay open:** the old "Who's this?" card for a name no memory carries, and the parked ruling R40.

---

## Global Constraints

- The app reads only the name fields, the nickname and the picture of a contact. `SystemContactsDirectory` must request no other key.
- **Nothing from a contact goes to the model.** A contact's name is never saved as an alias. For a person with `name_origin` `contact`, the context packet's `name` is the oldest alias. A test reads the packet and fails on any contact name.
- A name the owner said or typed is never replaced by a contact's name.
- One contact belongs to one person. The unique index holds it; the app must refuse before the index does.
- Unlink and a missing contact remove nothing but the link fields. The person, moments, names and pictures stay.
- The app replaces or removes only a photo it recorded in `contact_photo_id`.
- Only one file imports `Contacts`: `ios/Lifeline/Contacts/SystemContactsDirectory.swift`. `ContactAccessButton` lives in one view file. The kit imports neither.
- Contact fetches run off the main thread. Pictures are read only for a link or the check.
- The app must not ask for contacts at first launch.
- Every rule of PC-a's Global Constraints still binds (`docs/plans/2026-11-18-people-contacts.md`): origins, aliases only from `said` or `confirmed`, one transaction for a move, ochre with a word, 44-point controls, Dynamic Type.
- Copy, exact (drafts until the owner writes final copy):
  - Usage string (`NSContactsUsageDescription`): "Lifeline matches the names in your stories to your contacts. It reads names and pictures only, and they stay on this phone."
  - Chip lines: "Assumed · new, from your contacts", "New · not in your contacts", "New · not linked yet".
  - Sheet rows: "In your contacts · not in a story yet"; "Search your contacts".
  - Linked row: "Linked to {contact name} in your contacts"; "The app reads the name and picture only."; "Change"; menu "Link to another contact", "Unlink".
  - Not linked: "Not linked to a contact"; "That is fine. {name} has a page and stories either way."; "Link to a contact".
  - Suggestion: "{contact name} is in your contacts"; "Is this the same person?"; "Yes, link them"; "No, someone else".
  - Missing: "This contact is not in your contacts now"; "Link to a contact"; "Unlink".
  - No access: "If the app cannot see your contacts"; "People still work. Names are matched to the people in your stories only, and each guess is still marked."; "Allow contacts in Settings".
  - Held by another: "{name} is already linked to this contact."
  - Picture caption on a linked person's first picture, while it is the contact's copy: "picture from your contacts".
- Accessibility identifiers, new: `entity.contact.row`, `entity.contact.link`, `entity.contact.change`, `entity.contact.unlink`, `entity.contact.suggestion`, `entity.contact.suggestion.yes`, `entity.contact.suggestion.no`, `entity.contact.settings`, `contacts.search`, `contacts.result`, `contacts.accessButton`, `who.contact`, `who.search`. Keep every existing identifier.
- Sample names in tests and seeds are invented.
- Add each ruling made while building to `.superpowers/sdd/2026-11-18-people-contacts-b/rulings.md` and keep `progress.md` current. Commit both.

## Review Focus

1. **Two people on file and one contact share a first name.** Expected: rule 4 picks a person on file, and the contact shows in the sheet as a row. No person is made. Test in Task 2.
2. **The owner links a person to a contact that another person holds.** Expected: a refusal with that person's name, and no row changes. Test in Task 3.
3. **A kill between the picture's file and its row.** Expected: the S4 sweep removes the file, and the next check copies the picture again. Test in Task 4.
4. **Access goes from full to denied.** Expected: nothing is unlinked, each linked person shows the missing state with the Settings link, and Keep still marks every guess. Test in Tasks 4 and 7.
5. **A contact's name reaches the model.** Expected: never. A person made from a contact appears in the packet under the said name. Test in Task 2.

---

### Task 1: `ContactsDirectory`, the scripted directory and the cache

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Contacts/ContactsDirectory.swift`, `Contacts/ScriptedContactsDirectory.swift`, `Contacts/ContactsCache.swift`, `Contacts/ContactSearch.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/ContactsCacheTests.swift`, `ContactSearchTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum ContactsAccess: String, Sendable { case full, limited, notAsked, denied }   // restricted reads as denied
  public struct ContactCard: Sendable, Equatable, Identifiable {
      public var identifier: String; public var fullName: String; public var givenName: String
      public var familyName: String; public var nickname: String; public var hasPicture: Bool
      public var id: String { identifier }
      public var forGuess: PersonGuess.Contact { get }
  }
  public protocol ContactsDirectory: Sendable {
      func access() -> ContactsAccess
      func requestAccess() async -> ContactsAccess
      func all() async throws -> [ContactCard]                       // names only
      func cards(identifiers: [String]) async throws -> [ContactCard]  // the unified card for each stored identifier
      func picture(identifier: String) async throws -> Data?
  }
  public final class ContactsCache: Sendable {          // lock inside; safe from any thread
      public init()
      public var cards: [ContactCard] { get }
      public var forGuess: [PersonGuess.Contact] { get }
      public func replace(with cards: [ContactCard])
      public func refresh(from directory: any ContactsDirectory) async   // empty when access is notAsked or denied; a thrown read keeps the old cards
  }
  public enum ContactSearch { public static func results(_ text: String, in cards: [ContactCard]) -> [ContactCard] }
  public final class ScriptedContactsDirectory: ContactsDirectory { /* cards, pictures, access and the answer to requestAccess are settable */ }
  ```

- [ ] **Step 1: Write the failing tests.** `ContactSearchTests`: "rob" finds "Robyn Vale" and "Tomas Robles"; "róbyn" finds "Robyn Vale"; an empty text gives no result; a nickname matches; the order is by full name. `ContactsCacheTests`: `refresh` with access `denied` leaves the cache empty; with `limited` it holds the shared cards; a directory that throws keeps the old cards; `forGuess` maps every field.
- [ ] **Step 2: Run them.** `cd ios/LifelineKit && swift test --filter Contact`. Expected: they fail to compile.
- [ ] **Step 3: Write the four files.** `ContactSearch` uses `SaidName.key` for the comparison and matches a prefix of any word of the four name fields.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Kit: a contacts directory, a scripted one, a cache and a search"`

### Task 2: Keep links a new name to the one contact that fits

**Files:**
- Modify: `Confirmation/PersonGuessOnKeep.swift` (the `.contact` branch at the comment "PC-b replaces `.contact`"), `Confirmation/CandidateActions.swift`, `Confirmation/PersonLinkActions.swift` (`PreviewChip`), `Store/EntityRepository.swift` (`Write` carries the contact fields of a planned person), `Domain/PersonChipLine.swift`, `Extraction/ContextPacket.swift`
- Test: `PersonGuessOnKeepTests.swift`, `PersonChipLineTests.swift`, `ContextPacketTests.swift`

**Interfaces:**
- Consumes: `PersonGuess.guess`, `ContactsCache.forGuess`, the existing closure `contactsForGuess: @Sendable () -> [PersonGuess.Contact]` on `CandidateActions` and `PersonLinkActions`.
- Produces:
  ```swift
  // PersonChipLine
  public enum ContactsSeen: Sendable { case none, noMatch, someMatch }
  public static func text(origin: LinkOrigin?, saidName: String?, fromContact: Bool, contacts: ContactsSeen) -> String?
  // PreviewChip gains: public var fromContact: Bool
  // PersonLink gains:  public var personFromContact: Bool   // the person has name_origin contact and created_by_guess
  ```
  A person planned from a contact has: `displayName` the contact's full name, `nameOrigin` `.contact`, `createdByGuess` true, `contactIdentifier`, `contactName`, `contactState` "linked", and the said name as an alias. The link's origin is `assumed` (rules 3 and 5).

- [ ] **Step 1: Write the failing tests.**
  - Rule 5: one contact "Robyn Vale", no person, said "Robyn". Keep makes one person named "Robyn Vale" with that contact, alias "Robyn", link `assumed`.
  - Rule 3 for a contact: said "Robyn Vale", two contacts "Robyn Vale" and "Robyn Hale". The person is linked to "Robyn Vale".
  - Rule 6: two contacts "Robyn Vale" and "Robyn Okafor", said "Robyn". One person "Robyn", no contact, link `new`.
  - Review Focus 1: two persons "Robin" on file and a contact "Robin Okafor". No person is made; the link is `assumed` to the most recently linked person.
  - A contact that a person already holds is not a second candidate.
  - A second card in the same recording with the same said name reaches the same new person, not a second one.
  - The preview of a waiting card shows the same chip Keep writes, and writes no person.
  - `PersonChipLine.text`: `assumed` with `fromContact` → "Assumed · new, from your contacts"; `new` with `.noMatch` → "New · not in your contacts"; `new` with `.someMatch` → "New · not linked yet"; `new` with `.none` → "New".
  - Review Focus 5: `ContextPacket.build` with a person whose `nameOrigin` is `.contact`, name "Robyn Vale" and aliases "Robyn" (older) and "my roommate". The entry's `name` is "Robyn" and its aliases are ["my roommate"]. The encoded packet does not contain "Vale".
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code.** The picture is not read in the Keep transaction; Task 3's `copyPicture` runs after Keep.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, and `noExtractionPathCallsFindPerson` still passes.
- [ ] **Step 5: Commit.** `git commit -m "Keep links a new name to the one contact that fits, and no contact name reaches the model"`

### Task 3: Link, unlink and the picture

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Contacts/ContactLinkActions.swift`, `Store/ContactLinkWrites.swift`
- Modify: `Store/PeopleRepository.swift` (reads: `person(holding identifier:)`, `linkedPersons()`)
- Test: `ContactLinkActionsTests.swift`

**Interfaces:**
- Consumes: `ContactsDirectory`, `PhotoLibrary.add(fileAt:assetLocalID:to:now:)`, `PhotoLibrary.setCover`, `PhotoLibrary.remove`, `PhotoRepository.photos(of:)`.
- Produces:
  ```swift
  public struct ContactLinkActions: Sendable {
      public enum Error: Swift.Error, Equatable { case heldByAnother(PersonID, name: String), notFound }
      public init(store: ExtractionStore, photos: PhotoLibrary, directory: any ContactsDirectory)
      public func link(_ person: PersonID, to card: ContactCard) async throws     // then copyPicture
      public func unlink(_ person: PersonID) throws                               // clears identifier, name, state; keeps contact_photo_id's photo, clears the column
      public func copyPicture(for person: PersonID) async throws                  // no-op when the person has contact_photo_id or the contact has no picture
  }
  ```
  `link` on a person on file keeps their name and `name_origin`. It sets `created_by_guess` false: the owner acted.

- [ ] **Step 1: Write the failing tests.** Link sets the three fields; a person with no photo gets the picture as the first photo and `contact_photo_id`; a person with two photos gets it third; a contact with no picture adds no photo; a picture whose bytes are already one of the person's photos links nothing new and leaves `contact_photo_id` null; Review Focus 2 (`heldByAnother` with the holder's name, no row changes); a link to a second contact replaces the first and removes only the photo in `contact_photo_id` when it is still the app's copy; unlink keeps the person, the moments, the aliases and the picture; unlink of a person with no contact does nothing.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code.** `copyPicture` writes the data to a temporary file, calls `PhotoLibrary.add`, and records `contact_photo_id` only when the store made a new photo. The field writes are one transaction.
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Kit: link a person to a contact, unlink, and copy the contact's picture"`

### Task 4: The check at launch, a contact that changes, and suggestions

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Contacts/ContactCheck.swift`, `Contacts/ContactSuggestion.swift`
- Modify: `Contacts/ContactLinkActions.swift`, `Store/ContactLinkWrites.swift`
- Test: `ContactCheckTests.swift`, `ContactSuggestionTests.swift`

**Interfaces:**
- Produces:
  ```swift
  extension ContactLinkActions {
      public func check() async throws                    // linked persons only; fetches by the stored identifiers
      public func suggestion(for person: PersonID, in cards: [ContactCard]) throws -> ContactCard?
      public func decline(_ card: ContactCard, for person: PersonID) throws
      public func reguess(session: SessionID, contacts: [PersonGuess.Contact]) async throws -> Int   // plan decision 7; returns the links changed
  }
  public enum ContactSuggestion {   // pure
      public static func pick(name: String, aliases: [String], cards: [ContactCard], linked: Set<String>, declined: Set<String>) -> ContactCard?
  }
  ```

- [ ] **Step 1: Write the failing tests.**
  - Renamed contact: `contact_name` changes. The person's name changes only when `name_origin` is `contact`. A person with a said or typed name keeps it.
  - New picture while the person's first photo is `contact_photo_id`: the new picture is first, the old copy is gone, `contact_photo_id` points at the new one.
  - New picture while the owner's own photo is first: nothing changes.
  - The same picture: nothing changes.
  - The identifier does not resolve and exactly one contact has the kept full name: the person is linked to it again. With none or two: `contact_state` is "missing" and nothing else changes.
  - A contact that the system merged into another card: the stored identifier becomes the one the system returns.
  - Review Focus 3: a person with a contact, a picture and no `contact_photo_id` gets the picture at the next check.
  - Review Focus 4: with access `denied`, the check marks nothing as missing and unlinks nothing.
  - `ContactSuggestion.pick`: exactly one free, not declined card whose name equals the person's name or an alias → that card; two → nil; a linked card → nil; a declined card → nil and it stays nil after a second call.
  - `reguess`: a `new` link to a person the app made, with one free contact that fits → the person is linked and the link is `assumed`; a person the owner renamed is not touched; a link in another session is not touched; an `assumed` link to a person on file is not touched.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code.**
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Kit: check linked contacts, follow a changed contact, suggest one, and look again after access"`

### Task 5: The system directory, access and the wiring

**Files:**
- Create: `ios/Lifeline/Contacts/SystemContactsDirectory.swift`, `ios/Lifeline/Contacts/ContactsAccessPrompt.swift`
- Modify: `ios/project.yml` (`NSContactsUsageDescription`), `ios/Lifeline/Dependencies.swift` (`contacts: any ContactsDirectory`, `contactsCache`, `contactLinks`; every `CandidateActions` and `PersonLinkActions` gets `contactsForGuess = { cache.forGuess }`), `ios/Lifeline/LifelineApp.swift` (the check at launch and on `CNContactStoreDidChange`), `Screens/Landing/LandingViewModel.swift`, `LandingScreen.swift`, the five call sites that build `PersonLinkActions(store:)`, `ios/Lifeline/UITestSeed.swift`
- Test: kit test `ContactsAccessPromptRuleTests.swift` for the pure rule below

**Interfaces:**
- Consumes: everything from Tasks 1 to 4.
- Produces:
  ```swift
  // Kit, pure: when the landing may show the system prompt.
  public enum ContactsPromptRule {
      public static func shouldAsk(access: ContactsAccess, askedBefore: Bool, keptPeopleInSession: Int) -> Bool   // notAsked, not asked before, and one or more
  }
  // App
  struct SystemContactsDirectory: ContactsDirectory   // keys: given, family, middle, nickname, imageDataAvailable, thumbnailImageData / imageData for a picture only
  ```
  `Dependencies` gets one factory, `personLinkActions()`, so no call site forgets the closure.
  Launch arguments for UI tests: `-uiTesting-contacts <full|limited|notAsked|denied>` selects the scripted directory's access; the seed gives it invented cards ("Robyn Vale" with a picture, "Tomas Reyes", "Robyn Okafor").

- [ ] **Step 1: Write the failing test** for `ContactsPromptRule` (all four statuses, asked before, no kept people).
- [ ] **Step 2: Write the code.** After `requestAccess` returns full or limited on the landing: refresh the cache, run `reguess(session:)`, then `copyPicture` for each person it linked, then reload the landing's chips. The launch check runs in a detached task after the first screen shows; a failure is logged and never stops launch.
- [ ] **Step 3: Run `xcodegen generate`, `swift test`, and build the app.** Expected: PASS and BUILD SUCCEEDED. A scripted launch (`-uiTesting`) must never touch `CNContactStore`.
- [ ] **Step 4: Commit.** `git commit -m "App: the system contacts directory, the one prompt on the landing, and the launch check"`

### Task 6: Contact rows and search in the "Who is this?" sheet

**Files:**
- Create: `ios/Lifeline/Screens/People/ContactSearchList.swift` (the list, the field, and `ContactAccessButton` under limited access)
- Modify: `Confirmation/WhoIsThisOptions.swift`, `Confirmation/PersonLinkActions.swift`, `Store/PersonLinkWrites.swift`, `Screens/People/WhoIsThisSheet.swift`, `WhoIsThisViewModel.swift`
- Test: `WhoIsThisOptionsTests.swift`, `PersonLinkActionsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  // PersonLinkActions.Target gains: case contact(ContactCard)
  // WhoIsThisOptions.build gains: contacts: [ContactCard]   // the free contacts that fit the said name, after the people on file
  // Row.id for a contact: "contact:\(identifier)"; its line: "In your contacts · not in a story yet"
  ```
  A move to `.contact(card)`: when a person holds that contact, it is a move to that person. Otherwise the move makes a person as Task 2 does, with origin `confirmed`, and Undo removes that person. On a waiting card, `choose` stores choice `contact` with `contact_identifier`, and Keep applies it.

- [ ] **Step 1: Write the failing tests.** Options: contacts that fit come after people on file and before "Someone new"; a linked contact is not listed (its person is); no access gives no contact row. Move to a contact: a new linked person, `confirmed`, the said name as alias; Undo restores every row and removes the person; a move to a contact that a person holds goes to that person; a stored `contact` choice is applied by Keep with `confirmed`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code and the views.** "Search your contacts" opens `ContactSearchList` inside the sheet. With access `notAsked` the tap asks first. With `denied` the row is replaced by "Allow contacts in Settings". After a move to a contact the app calls `copyPicture`.
- [ ] **Step 4: Run `swift test` and build the app.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "The sheet lists the contacts that fit and searches the rest"`

### Task 7: The person's page: linked row, link, change, unlink, suggestion, no access

**Files:**
- Create: `ios/Lifeline/Screens/Entities/PersonContactRow.swift`, `PersonContactViewModel.swift`
- Modify: `Screens/Entities/EntityScreen.swift`, `EntityViewModel.swift`
- Test: kit test for the row's state, `PersonContactStateTests.swift`

**Interfaces:**
- Produces:
  ```swift
  // Kit, pure: what the row shows.
  public enum PersonContactState: Equatable {
      case linked(contactName: String)
      case missing(contactName: String, canSeeContacts: Bool)
      case notLinked(suggestion: ContactCard?)
      case noAccess          // denied, and the person has no contact
      public static func of(_ person: Person, access: ContactsAccess, suggestion: ContactCard?) -> PersonContactState
  }
  ```
  The row shows on a person's page only, never on the owner's page, a place or a thing.

- [ ] **Step 1: Write the failing test** for `PersonContactState.of` (each case; a linked person under `denied` is `missing` with `canSeeContacts` false).
- [ ] **Step 2: Write the views.** Layout as PC3 and PC4. "Link to a contact" and "Link to another contact" open `ContactSearchList`. "Unlink" asks nothing and shows no Undo: the owner can link again. "Yes, link them" links; "No, someone else" declines and the card goes. A held contact shows "{name} is already linked to this contact." in the page's message slot. The first picture shows "picture from your contacts" while it is `contact_photo_id`.
- [ ] **Step 3: Run `swift test` and build the app.** Expected: PASS.
- [ ] **Step 4: Commit.** `git commit -m "A person's page shows its contact, links one, changes it and unlinks it"`

### Task 8: UI tests

**Files:**
- Create: `ios/LifelineUITests/PeopleContactsUITests.swift`
- Modify: `ios/Lifeline/UITestSeed.swift`, `ios/LifelineUITests/UITestHelpers.swift`

- [ ] **Step 1: Write the tests.** With `-uiTesting-contacts full`:
  1. A person with no contact shows "Not linked to a contact"; "Link to a contact", a search for "rob", a tap on "Robyn Vale"; the row reads "Linked to Robyn Vale in your contacts" and the page shows a picture.
  2. "Change", "Unlink": the row reads "Not linked to a contact" and the picture stays.
  3. A person named "Tomas" shows the suggestion for "Tomas Reyes"; "No, someone else" removes it, and it is still gone after the page is opened again.
  4. "Yes, link them" links.
  5. The sheet for a guessed "Robin" lists a contact row; choosing it and "Done" shows "Changed to Robyn Okafor." and Undo restores the chip.
  6. A kept story with a new name that fits one contact shows the chip line "Assumed · new, from your contacts".
  7. A contact held by another person: the refusal sentence shows and nothing changes.
  With `-uiTesting-contacts denied`: 8. the page shows the no-access card with `entity.contact.settings`; the sheet has no contact row.
  With `-uiTesting-contacts limited`: 9. the search list shows `contacts.accessButton`.
- [ ] **Step 2: Run `PeopleContactsUITests`, then the whole UI suite and `swift test`.** Expected: PASS. Rerun a class that another session's load cut off; never stop another session's run.
- [ ] **Step 3: Commit.** `git commit -m "UI tests: link, unlink, suggest, the sheet's contact rows, and no access"`

### Task 9: Docs, ledger and the device check

**Files:**
- Modify: `docs/OVERVIEW.md` (contacts: what is read, what is kept, the check), `docs/DECISIONS.md` (one entry: this plan's ten decisions and the rulings made while building), `README.md` (the new launch argument), the spec where the work moved away from it
- Create: `docs/plans/2026-11-18-people-contacts-b-device-check.md`

The device check list, exact items:

1. Record a story with a new name that fits one contact. The landing shows the system prompt with the usage string. Allow full access. The chip reads "Assumed · new, from your contacts" and the person has the contact's picture.
2. Open a person with no contact. "Link to a contact" finds a contact by first name, by family name and by nickname.
3. "Change", then "Unlink". The person, the moments and the picture stay.
4. Change the contact's name and picture in the Contacts app. Open Lifeline again. The linked row shows the new name. The picture changes only when the first picture was the contact's copy.
5. Delete the contact in the Contacts app. The row reads "This contact is not in your contacts now". Nothing else is lost.
6. Add a contact with the name of a person on file. That person's page asks "Is this the same person?".
7. Set contacts to "Limited Access" in Settings. The search shows the button that shares one more contact, and one tap shares it.
8. Set contacts to "None" in Settings. People and guesses still work. A person's page shows "Allow contacts in Settings".
9. Make a backup, then restore it on this phone. The linked rows still resolve.
10. With the photo card build (PR #31): drag another photo in front of the contact's picture. It stays first after the next launch.
11. Largest text size and VoiceOver on the linked row, the suggestion card and the contact search.

- [ ] **Step 1: Write the docs.** ASD-STE100 style.
- [ ] **Step 2: Run `swift test` and the whole UI suite once more.** Expected: PASS.
- [ ] **Step 3: Commit.** `git commit -m "Docs: contacts, the decisions and the device check"`
- [ ] **Step 4: Stop.** Tell the owner the branch is ready for the device check. Do not push. Do not open a PR.

---

## After PC-b

- **PC-c, merge:** the button, the confirm, Undo, then the drag. It also turns plan decision 4's refusal into "Same person?".
- **PC-d, extractor handles.**
- **Flagged for the owner:** decisions 4 (a held contact is refused until merge exists), 5 (the three "New" lines), 6 (the prompt shows by itself on the landing) and 8 (the app's own contact list, not Apple's picker).
