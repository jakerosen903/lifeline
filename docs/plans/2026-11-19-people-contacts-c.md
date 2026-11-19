# PC-c: Two People Can Be Merged — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Approved by the owner on 2026-11-19 ("Yes, build both"), without a review of each decision. Each decision stays open to an overrule.

**Goal:** The owner can say that two people on file are one person. The app joins them into one, asks first, and gives Undo for 6 seconds.

**Architecture:** The kit gets one actions type, `PersonMergeActions`, and one file of writes, `Store/PersonMergeWrites.swift`. A merge is one transaction. It returns a receipt that holds every row it changed, and Undo puts each row back. The app gets a row on the person's page, a picker, a confirm sheet, and a drag on the People grid. The forced case of PC-b (a contact that another person holds) now asks "Same person?" where it refused before. No migration.

**Tech Stack:** Swift 6, SwiftUI on iOS 26, GRDB, Swift Testing, XCUITest. No new dependency. No network call. No prompt change.

**Spec:** `docs/specs/2026-11-18-people-contacts.md`, section "Merging two people", and the merge lines of "Edge cases" and "Test plan". No mock-up exists for the confirm sheet; Task 4 builds it from the parts of `docs/design/PC2_WhoIsThis.dc.html`.

**Not this plan:** PC-d (extractor handles). A merge of two places or two things by drag (spec call 2 is open: the owner said "two things").

**Worktree and branch:** `.claude/worktrees/people-contacts-16241d`. Branch `people-contacts-c`, cut from the tip of `people-contacts-d` (5bf37b2), which is cut from `people-contacts-b` (PR #35). So the stack is PC-b, PC-d, PC-c. That tip already holds `main`'s photo order, migration `v16` and the extractor handles of PC-d. **Task 1 is only "the branch exists"**: its merge of `origin/main` is not needed, `PhotoRepository.writeOrder` is already visible inside the kit, and `photo_page_declined` is a real table (decisions 8 and 9 need no hand-made table in tests). A link's `person_handle` (PC-d) moves with the link. (revised 2026-11-19) No AI attribution in a commit or in PR text.

---

## What the owner gets

1. A person's page has the row "Same as another person…". It opens a list of the other people.
2. The app asks "Same person?" with both names and both pictures. Nothing changes before the owner taps "Merge".
3. After the merge, one person has every story, detail, name and photo of the two.
4. The line "Merged into {name}." shows for 6 seconds with "Undo".
5. On the People grid, the owner can drag one face onto another. The same question follows.
6. When the owner links a person to a contact that another person holds, the app asks "Same person?" for those two.

## Decisions made in this plan

The spec leaves these open, or this plan differs from the spec. The owner can overrule each one before work starts.

1. **Hidden and kept-from-AI stay on.** The spec says the staying person's flags win (call 21, never discussed). This plan differs: when either person is hidden from the timeline, the result is hidden. When either person is kept from the AI, the result is kept from the AI. Reason: with the spec's rule, a merge can send to the model the stories of a person the owner kept from it, and the owner sees no sign. The merge of places and things already works this way. The confirm sheet says it in one line when it applies. Undo restores both flags. The spec gets a "narrowed" note.
2. **The person the owner picks is the one that stays.** On the page of "Robin", the owner taps "Same as another person…" and picks "Robyn Vale". "Robyn Vale" stays. This matches the drag, where the person dropped onto stays. The confirm sheet names which one stays. The page of "Robin" then shows "Merged into Robyn Vale." with Undo, reads only, and closes to the People grid when the line goes. A page whose person a move removed works this way today. The other option: the page's person stays.
3. **The other person's name becomes an alias of the one that stays**, so "Robin" said in a later story still finds the merged person. A name that came from a contact (`name_origin` `contact`) does not become an alias: no contact name may reach the model.
4. **The forced case merges into the holder.** On the page of A, the owner picks a contact that B holds. The app asks "Same person?". On "Merge", A joins B, and B keeps the contact. When A also has a contact of its own, the app refuses with "They are linked to two different contacts."
5. **The owner is never merged.** The picker does not list the owner, and the grid does not accept a drop on or of the owner.
6. **A merge counts as the owner's act.** The staying person's `created_by_guess` is cleared. Undo sets it again.
7. **Undo lives in memory only.** A kill inside the 6 seconds leaves the merged state. The confirm sheet says that the merge cannot be taken back later.
8. **PC-c is built on `main`'s photo order.** Task 1 merges `origin/main` (the photo card, PR #31, and the sections strip, PR #32) into the branch, because the merge writes the photo order through `PhotoRepository`'s one order function, which exists only there.
9. **The receipt copies rows by `select *`.** The phone branch has migration `v16` (a photo on a person's page: `photo_link.origin`, `photo_page_declined`). That work is not on `main`. A receipt that copies whole rows carries any column a later migration adds. The merge also moves `photo_page_declined` rows when that table exists. A test makes the table by hand.
10. **The drag has a plain motion in this plan.** The dragged tile shrinks into the other and fades. With Reduce Motion the tile fades only. The spec says the motion is tuned on the device; the device check lists it.

### Limits found while planning

- **No mock-up for the confirm sheet or the picker.** The copy below is a draft.
- **The People grid has no message slot today**, and the app has no drag or drop anywhere. Task 6 adds both.
- **Undo is lost when the owner leaves the page inside the 6 seconds.** A move's Undo works this way today.
- **At the largest text sizes the grid is a list**, and it has no drag. The button path is the way there, and for VoiceOver and Switch Control.
- **A drag may not run in a UI test on the simulator.** Task 6 tries one test. When the simulator cannot drive it, the device check covers the drag, and the button path has the UI tests.
- **Screens that hold the id of the person that went** (an open "Who is this?" sheet, a stale page) show "That person is not here any more.", as today.

---

## Global Constraints

- A merge is one transaction. A kill in the middle leaves the old state or the new state.
- Nothing changes before the owner taps "Merge" on the confirm sheet.
- The app must refuse a merge of: a person with themself, a person that is gone, the owner, and two persons that both hold a contact.
- The person that stays keeps their name, and their value wherever both have one: notes, birth date, the detail line, stated dates. Where the staying person has none, the other's value is taken.
- Each link keeps its origin. A memory linked to both keeps one link, with the stronger origin.
- Photos keep one order: the staying person's photos first, with their key photo at the front, then the other person's. No code in this plan sets `sort_order` itself; it calls `PhotoRepository`'s order function.
- **Nothing from a contact goes to the model.** A contact's name is never saved as an alias. The packet test of PC-b must still pass after a merge.
- One contact belongs to one person. The app must refuse before the unique index does.
- Undo restores every row as it was. Undo is refused when a row the merge left has changed since.
- Every rule of the Global Constraints of PC-a and PC-b still binds (`docs/plans/2026-11-18-people-contacts.md`, `docs/plans/2026-11-18-people-contacts-b.md`): origins, ochre with a word, 44-point controls, Dynamic Type, one message slot.
- Copy, exact (drafts until the owner writes final copy):
  - Row on the person's page: "Same as another person…"
  - Picker title: "Who is {name} the same as?"; empty state: "No other people yet."
  - Confirm title: "Same person?"; body: "{leaving name} joins {staying name}. Every story, name and photo moves to {staying name}."; second line: "You can undo this for a few seconds only."; flag line, when decision 1 applies: "{staying name} stays hidden, because one of them is." or "{staying name} stays out of the AI's view, because one of them is."; buttons: "Merge", "Cancel".
  - Notice: "Merged into {name}." with "Undo".
  - Refusals: "They are linked to two different contacts."; "That person is not here any more." (existing); a stale or failed Undo uses the existing lines `PersonChipLine.staleUndo` and `PersonChipLine.failedUndo`.
  - VoiceOver label on the confirm's pictures: "{name}".
- Accessibility identifiers, new: `entity.merge`, `merge.picker`, `merge.picker.person`, `merge.confirm`, `merge.confirm.text`, `merge.confirm.merge`, `merge.confirm.cancel`. The notice keeps `person.notice` and `notice.undo`. Keep every existing identifier.
- Sample names in tests and seeds are invented.
- Add each ruling made while building to `.superpowers/sdd/2026-11-19-people-contacts-c/rulings.md` and keep `progress.md` current. Commit both.

## Review Focus

1. **A waiting card holds the owner's choice of the person that goes** (`candidate_person_choice.person_id`, which cascades on the person). Expected: the choice points at the staying person after the merge, and Keep links that person. Test in Task 2.
2. **Both persons are linked to one memory, one `assumed` and one `confirmed`.** Expected: one link, `confirmed`, and Undo brings back both rows with their own origins and role texts. Tests in Tasks 2 and 3.
3. **The person that goes was made from a contact, and the one that stays has no contact.** Expected: the stayer holds the contact and its copied picture; the contact's name is not an alias; the packet holds no contact name. Test in Task 2.
4. **Something changes in the 6 seconds** (the contacts check renames the stayer, a photo story adds a link). Expected: Undo is refused, says so, and changes nothing. Test in Task 3.
5. **One photo is on both pages, and each person has a key photo.** Expected: one link to the photo, the stayer's key photo stays the key photo, and exactly one key photo exists. Test in Task 2.

---

### Task 1: The branch, with `main` merged in

**Files:**
- Conflicts expected (found with `git merge-tree`): `docs/DECISIONS.md`, `docs/design/README.md`, `docs/design/canvas.json`, `ios/Lifeline/UITestSeed.swift`, `ios/LifelineKit/Sources/LifelineKit/Store/PhotoRepository.swift`

**Interfaces:**
- Produces, in `PhotoRepository` (both visible inside the kit):
  ```swift
  static func writeOrder(_ wanted: [PhotoID], of subject: PhotoSubject, in db: Database) throws   // main's function, no longer private
  static func setCover(_ photo: PhotoID, of subject: PhotoSubject, in db: Database) throws        // PC-b's function, now a call to writeOrder
  static func firstPhoto(of subject: PhotoSubject, in db: Database) throws -> PhotoID?            // PC-b's function, kept
  ```

- [ ] **Step 1: Cut the branch.** `git switch -c claude/people-contacts-c claude/people-contacts-b`
- [ ] **Step 2: Merge.** `git merge origin/main`. Keep both sides' entries in the three docs files. In `UITestSeed.swift` keep both sides' seeds and flags. In `PhotoRepository.swift` keep `main`'s `reorder` and `writeOrder`, keep PC-b's in-transaction `setCover` and `firstPhoto`, and make the in-transaction `setCover` call `writeOrder([photo], of: subject, in: db)` after its "the page holds this photo" guard. The public `setCover` calls the in-transaction one.
- [ ] **Step 3: Regenerate and run.** `cd ios && xcodegen generate`, then `swift test` in `ios/LifelineKit`. Expected: PASS, except the known timing flake `ExtractionQueueTests.drainGivesUpAtItsDeadline`, which passes alone.
- [ ] **Step 4: Run the UI classes that the merge touches** on the simulator "Lifeline People": `PeopleContactsUITests`, `PeopleUITests`, `EntityPageUITests`, `PhotosUITests`, `PhotoCardUITests`. Expected: PASS, except `PhotoCardUITests.testRemoveTakesThePhotoOffOneMemory` and `.testUseThisDateDatesTheMemory`, which fail on `main` too. A test that cannot find the "Photos" row on a person's page must scroll to it with `app.reveal`; the contact row makes that page longer.
- [ ] **Step 5: Commit the merge.** `git commit` with the message "Merge main (photo card, sections strip) into people-contacts-c".

### Task 2: The merge, in one transaction

**Files:**
- Create: `ios/LifelineKit/Sources/LifelineKit/Confirmation/PersonMergeActions.swift`, `ios/LifelineKit/Sources/LifelineKit/Store/PersonMergeWrites.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/PersonMergeActionsTests.swift`

**Interfaces:**
- Consumes: `PersonLinkRepository` (it holds the database; `PersonMergeWrites.swift` is an extension of it, as `PersonLinkWrites.swift` is), `MomentEntity.raiseOrigin`, `PhotoRepository.writeOrder`, `PeopleRepository.insertAlias`, `PeopleRepository.normalize`, `Person.selectSQL`.
- Produces:
  ```swift
  /// What the confirm sheet shows. Made by `check`, which throws every refusal before the owner is asked.
  public struct PersonMergePreview: Sendable, Equatable {
      public var leaving: Person
      public var staying: Person
      public var staysHidden: Bool        // decision 1: true when the result is hidden and the two differed
      public var staysOutOfAI: Bool       // decision 1: true when the result is kept from the AI and the two differed
  }

  public struct PersonMergeReceipt: Sendable, Equatable {
      public var staying: PersonID
      public var leaving: PersonID
      public var stayingName: String      // for the notice
      // internal: the rows before and after (Task 3 reads them)
  }

  public struct PersonMergeActions: Sendable {
      public enum Error: Swift.Error, Equatable { case samePerson, notFound, owner, twoContacts, stale }
      public init(store: ExtractionStore)
      /// Every person but this one and the owner, most recently linked first (`PeopleRepository.peopleByRecentLink`).
      public func others(than person: PersonID) throws -> [Person]
      public func check(_ leaving: PersonID, into staying: PersonID) throws -> PersonMergePreview
      @discardableResult public func merge(_ leaving: PersonID, into staying: PersonID) throws -> PersonMergeReceipt
      public func undo(_ receipt: PersonMergeReceipt) throws      // Task 3
  }
  ```

What the transaction does, in this order. `S` is the staying person, `L` the one that goes. A person and their entity share one id.

1. Refuse as `check` does: `.samePerson`, `.notFound` (either is gone), `.owner` (either is the owner), `.twoContacts` (both have a `contact_identifier`).
2. Copy the rows for the receipt (Task 3 defines the copy; this task may leave it empty and fill only the three public fields).
3. `moment_entity`: for each row of `L`, raise the origin of `S`'s row for the same memory and relation; then move `L`'s rows to `S` with `update or ignore`. Rows left on `L` go with `L`.
4. `entity_span` (first tellings): `L`'s spans follow `S`'s, in their order, as `EntityRepository.merge` does.
5. `alias`: each alias of `L` goes to `S` (`insert or ignore`), oldest first. Then `L`'s name, by decision 3, unless it equals `S`'s name under `PeopleRepository.normalize`.
6. `photo_link`: read `S`'s photo ids in page order, then `L`'s. Move `L`'s rows to `S` with `update or ignore` after setting their role to `attached`. Call `writeOrder(S's ids + L's ids, of: .entity(S))`.
7. `photo_page_declined`, when the table exists: `L`'s rows go to `S` with `update or ignore`.
8. `mention.person_id`, `candidate_person_choice.person_id`, `curiosity_item.entity_id`, `session.subject_entity_id`: each row of `L` points at `S`.
9. `domain_tag` (kind `entity`): `L`'s tags go to `S` with `update or ignore`.
10. `contact_declined`: `L`'s rows go to `S` with `insert or ignore`. This also carries the picture-removal markers of `ContactPictureRemoval`.
11. The contact: when only `L` has one, clear `L`'s four contact fields first, then set them on `S` (`contact_identifier`, `contact_name`, `contact_state`, `contact_photo_id`). The unique index is checked per statement.
12. `S`'s own values: take `L`'s notes, birth date with its origin, detail line and stated dates only where `S` has none. Hidden and kept-from-AI by decision 1. Clear `created_by_guess` (decision 6). `S` keeps `name_origin` and the name.
13. Delete `L`'s entity. The person row and every row left on `L` go by cascade.

- [ ] **Step 1: Write the failing tests.** Each test builds its people with Keep or the repositories, as `PersonLinkActionsTests` does.
  - Links: `L` has two memories and a detail, `S` has one. After the merge `S` has all four links, each with its origin and role text; `L` is gone.
  - Review Focus 2: both linked to one memory, `L` `confirmed` and `S` `assumed`. One link, `confirmed`.
  - Aliases: `L` "Robin" with aliases "Rob" and "my roommate" joins `S` "Robyn Vale". `S` has "Rob", "my roommate" and "Robin". `S`'s name is "Robyn Vale".
  - Review Focus 3: `L` made by Keep from the contact "Robyn Vale" (alias "Robyn", a copied picture), `S` "Robin" with no contact. `S` holds the identifier, the kept name, the state and `contact_photo_id`; the picture is on `S`'s page; "Robyn Vale" is not an alias of `S`; `ContextPacket.build` does not contain "Vale".
  - `.twoContacts` when both hold a contact, and no row changes. `.owner` for the owner on either side. `.samePerson`. `.notFound`.
  - Values: `S` has notes and no birth date; `L` has notes and a birth date. `S` keeps its notes and takes the birth date with its origin. The same for the detail line and stated dates.
  - Decision 1: `L` kept from the AI, `S` not. `S` is kept from the AI, and the preview's `staysOutOfAI` is true. The same for hidden. With equal flags both preview fields are false.
  - Review Focus 5: one photo on both pages and a key photo on each. `S`'s page: `S`'s photos in their order, then `L`'s others; one link to the shared photo; `S`'s key photo is first; one row has role `cover`.
  - `S` has no photo and `L` has two. `L`'s key photo is `S`'s key photo.
  - Review Focus 1: a waiting card with a stored choice of `L` for "Robin". After the merge and Keep, the memory is linked to `S`.
  - A mention resolved to `L`, a curiosity item about `L`, a session whose subject is `L`, a tag on `L`, a declined contact of `L` and a picture-removal marker of `L`: each belongs to `S` after the merge.
  - `photo_page_declined`: the test creates the table as `v16` does, with one row for `L`. After the merge the row is `S`'s.
  - The first telling: `S` has one and `L` has one. `S` has both, its own first.
  - `created_by_guess` of `S` is false after the merge.
  - `others(than:)` leaves out the person and the owner.
  - A failure inside the transaction (the test drops `domain_tag` first, so step 9 throws) leaves both persons as they were.
- [ ] **Step 2: Run them.** `swift test --filter PersonMergeActionsTests`. Expected: FAIL, the types do not exist.
- [ ] **Step 3: Write the code.**
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Merge two people in one transaction"`

### Task 3: The receipt and Undo

**Files:**
- Modify: `Confirmation/PersonMergeActions.swift`, `Store/PersonMergeWrites.swift`
- Create: `ios/LifelineKit/Sources/LifelineKit/Store/RowCopy.swift`
- Test: `ios/LifelineKit/Tests/LifelineKitTests/PersonMergeUndoTests.swift`, `RowCopyTests.swift`

**Interfaces:**
- Produces:
  ```swift
  /// Whole rows of one table, read with `select *`, so a column a later migration adds is carried (decision 9).
  struct RowCopy: Sendable, Equatable {
      var table: String
      var rows: [[String: DatabaseValue]]
      static func read(_ table: String, where condition: String, arguments: StatementArguments, in db: Database) throws -> RowCopy   // ordered by rowid
      func insert(in db: Database) throws
  }
  ```
  `PersonMergeReceipt` gains, inside the kit: `before: [RowCopy]` (the rows of both persons in the owned tables), `after: [RowCopy]` (the rows of `S` in the same tables, as the merge left them), `personBefore`/`personAfter` and `entityBefore`/`entityAfter` for `S`, `leavingPerson` and `leavingEntity`, and `repointed: [String: [String]]` (table name to the row ids, or for `session` the session ids, that the merge pointed at `S`).
- The owned tables, keyed by the person's id: `moment_entity`, `entity_span`, `alias`, `photo_link` (rows with `entity_id`), `domain_tag` (kind `entity`), `contact_declined`, and `photo_page_declined` when it exists.

Undo, in one transaction:

1. Refuse with `.stale`, and change nothing, when: `S`'s person row or entity row differs from `personAfter` or `entityAfter`; any owned table's rows of `S` differ from `after`; a person with `L`'s id exists; a repointed row is gone or no longer points at `S`; another person holds a contact that `L` held.
2. Delete `S`'s rows in the owned tables. Write `S`'s person and entity rows back from `personBefore` and `entityBefore` with an update, so no cascade runs.
3. Insert `L`'s entity, then `L`'s person. `S`'s contact fields are already cleared by step 2, so the unique index holds.
4. Insert every row of `before`.
5. Point each repointed row back at `L`.

- [ ] **Step 1: Write the failing tests.**
  - `RowCopy`: read two rows, delete them, insert, read again: equal. A column added with `alter table` after the type was written is carried.
  - Undo after each merge test of Task 2 that changes rows: every table's rows of both persons equal the rows before the merge. Compare with `RowCopy.read` over the owned tables, both person rows, both entity rows and the repointed rows.
  - Review Focus 2: Undo brings back both links with their own origins and role texts.
  - Review Focus 4: after the merge, rename `S`. Undo throws `.stale` and no row changes. The same after a new link to `S`, after a new photo on `S`'s page, and after a memory of `L` is deleted.
  - Undo twice: the second throws `.stale`.
  - `L` held a contact. After the merge, the test unlinks `S` and links a third person to that contact. Undo throws `.stale`.
  - `photo_page_declined` made by hand: Undo puts `L`'s row back.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the code.** Merge step 2 of Task 2 now fills the receipt.
- [ ] **Step 4: Run `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Undo a merge of two people from its receipt"`

### Task 4: The person's page: the row, the picker, the confirm and the notice

**Files:**
- Create: `ios/Lifeline/Screens/Entities/PersonMergeViewModel.swift`, `ios/Lifeline/Screens/Entities/PersonMergeSheet.swift`
- Modify: `ios/Lifeline/Screens/People/PersonMoveUndo.swift`, `ios/Lifeline/Screens/Entities/EntityViewModel.swift`, `ios/Lifeline/Screens/Entities/EntityScreen.swift`, `ios/Lifeline/Dependencies.swift`
- Run `xcodegen generate` in `ios/` after adding the files.

**Interfaces:**
- Consumes: `PersonMergeActions` (Tasks 2 and 3), `PersonFace`, `NoticeSlot`, `PersonMoveNoticeSlot`, `CardHandler.undoWindow`, `PersonChipLine.staleUndo`, `PersonChipLine.failedUndo`.
- Produces:
  ```swift
  // Dependencies
  func personMergeActions() -> PersonMergeActions

  // PersonMoveUndo: the one message slot can hold any Undo. `note(_:)` for a move calls this.
  func offer(_ text: String, undo: @escaping @MainActor () throws -> Void)

  // PersonMergeViewModel (@MainActor @Observable)
  init(deps: Dependencies)
  var others: [Person]                       // the picker's rows
  var preview: PersonMergePreview?           // set when a pair passed `check`; the confirm shows it
  var refusal: String?                       // the sentence for a pair that `check` refused
  func openPicker(for person: PersonID)
  func ask(_ leaving: PersonID, into staying: PersonID)   // runs `check`; sets `preview` or `refusal`
  func merge() -> PersonMergeReceipt?        // merges the previewed pair; nil and `refusal` on failure
  func cover(of person: PersonID) -> Photo?

  // PersonMergeSheet: one sheet. `picker` true shows the list first; a tap runs `ask` and pushes the confirm.
  struct PersonMergeSheet: View { init(viewModel: PersonMergeViewModel, leaving: Person?, picker: Bool, onMerged: @escaping (PersonMergeReceipt) -> Void) }
  ```
- `EntityViewModel` gains `let merge: PersonMergeViewModel` and `func merged(_ receipt: PersonMergeReceipt)`, which calls `personMove.offer("Merged into {name}.", undo:)` and then `refresh()`. Undo calls `PersonMergeActions.undo` and then `refresh()`, so the page is alive again.

Rules for the screen:

- The row sits in the contact `Section` of `EntityScreen`, under `PersonContactRow`. That section shows only for a person who is not the owner. The row is a plain button with a 44-point target.
- The picker lists `others` with `PersonFace` (size 40) and the name. It has a "Cancel" button. With no other person it shows the empty line.
- The confirm shows both faces (size 64) side by side with an arrow from the one that goes to the one that stays, the names under them, the body lines, and the two buttons. "Merge" is the prominent button. The sheet scrolls at large text sizes.
- A refusal from `check` shows in the page's message slot through `personMove.say`, and no confirm opens.
- After "Merge" the sheet closes. The page shows the notice. `shouldClose` already keeps the page up, read only, while the notice shows.

- [ ] **Step 1: Write the code.** UI tests come in Task 7; this task has no kit test, because it adds no kit code.
- [ ] **Step 2: Build.** `xcodebuild build` for the scheme `Lifeline` on the simulator "Lifeline People" (`9EFE1D73-E4D4-461E-B971-170BE3F22BA2`). Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Run `PeopleGuessUITests` and `PeopleContactsUITests`.** Expected: PASS. They prove that a move's notice and Undo still work through `offer`.
- [ ] **Step 4: Commit.** `git commit -m "Same as another person: the row, the picker, the confirm and Undo"`

### Task 5: A contact that another person holds asks "Same person?"

**Files:**
- Modify: `ios/Lifeline/Screens/Entities/PersonContactViewModel.swift`, `ios/Lifeline/Screens/Entities/EntityViewModel.swift`, `ios/Lifeline/Screens/Entities/EntityScreen.swift`
- Test (changed): `ios/LifelineUITests/PeopleContactsUITests.swift` (`testAContactAnotherPersonHoldsIsRefused`)

**Interfaces:**
- Consumes: `ContactLinkActions.Error.heldByAnother(PersonID, name:)`, `PersonMergeViewModel.ask`.
- Produces: `PersonContactViewModel.onHeldByAnother: (PersonID) -> Void`. `EntityViewModel` sets it to `merge.ask(page person, into: holder)` and opens `PersonMergeSheet` with `picker: false`.

- `PersonContactViewModel.link` no longer says "{name} is already linked to this contact." for `.heldByAnother`. It calls `onHeldByAnother`.
- The link is not made by itself. The merge gives the contact to the one person (decision 4).
- When the page's person has a contact of their own, `check` throws `.twoContacts` and the page says "They are linked to two different contacts."
- The search row keeps its line "In a story as {name}".

- [ ] **Step 1: Change the UI test.** `testAContactAnotherPersonHoldsIsRefused` becomes `testAContactAnotherPersonHoldsAsksSamePerson`: the pick opens `merge.confirm` with both names; "Cancel" changes nothing and both people are on the grid.
- [ ] **Step 2: Write the code.**
- [ ] **Step 3: Run `PeopleContactsUITests`.** Expected: PASS.
- [ ] **Step 4: Commit.** `git commit -m "A contact another person holds asks Same person?"`

### Task 6: Drag one face onto another on the People grid

**Files:**
- Create: `ios/Lifeline/Screens/Entities/PersonDrag.swift`
- Modify: `ios/Lifeline/Screens/Entities/PeopleGridScreen.swift`, `ios/Lifeline/Screens/Entities/PersonTile.swift`, `ios/Lifeline/Screens/Entities/EntitiesViewModel.swift`

**Interfaces:**
- Produces: `struct PersonDrag: Transferable` that carries the person's id as plain text with the prefix `lifeline-person:`. `init?(text: String)` returns nil for any other text, so a drop from another app does nothing.
- `EntitiesViewModel` (for type `.person` only) gains `let merge: PersonMergeViewModel` and `let notice: PersonMoveUndo`.

- Each `PersonTile` in the `LazyVGrid` is `.draggable(PersonDrag)` and a `.dropDestination(for: PersonDrag.self)`. The list at the largest text sizes has neither.
- A drop of A on B runs `merge.ask(A, into: B)` and opens `PersonMergeSheet` with `picker: false`. A drop of a tile on itself does nothing.
- While a drag is over a tile, that tile shows a 2-point accent ring.
- After "Merge": the tile of A shrinks toward B and fades (0.25 s), then the grid refreshes. With Reduce Motion it only fades.
- The grid gets the message slot, in `.safeAreaInset(edge: .bottom)` as on `EntityScreen`: "Merged into {name}." with Undo. Undo refreshes the grid.
- A tap on a tile still opens the page. A drag starts after the system's long press.

- [ ] **Step 1: Write the code.**
- [ ] **Step 2: Build and run `PeopleUITests`.** Expected: PASS; a tap still opens a page.
- [ ] **Step 3: Try one UI test of the drag** in Task 7's file: `press(forDuration: 1.0, thenDragTo:)` from the tile "Sam" to the tile "Maya", then `merge.confirm` exists. When the simulator does not deliver the drop in three tries, delete the test, write a ruling, and leave the drag to the device check.
- [ ] **Step 4: Commit.** `git commit -m "Drag one face onto another to merge two people"`

### Task 7: UI tests

**Files:**
- Create: `ios/LifelineUITests/PeopleMergeUITests.swift`
- Modify: `ios/Lifeline/UITestSeed.swift` only when a test needs a seed that does not exist.

All tests launch with `launchWithPeople` (Maya, Dad, Sam, Lena) and, where contacts matter, `-uiTesting-contacts full`.

- [ ] **Step 1: Write the tests.**
  - `testSameAsAnotherPersonMergesByTheButton`: open "Sam", tap `entity.merge`, pick "Maya", the confirm shows both names, tap "Merge". The notice reads "Merged into Maya." After it goes, the grid has "Maya" and no "Sam". Maya's page has Sam's moment.
  - `testUndoBringsBothPeopleBack`: the same, then `notice.undo`. The page of "Sam" is live again, and the grid has both.
  - `testCancelOnTheConfirmChangesNothing`.
  - `testThePickerLeavesOutThisPersonAndTheOwner`: on Sam's page the picker has no "Sam" and no "Jordan".
  - `testTwoDifferentContactsRefuse`: link Sam to "Dara Quinn" and Lena holds "Robyn Okafor" (`-uiTesting-seedContactLink`); "Same as another person…" on Sam with Lena says "They are linked to two different contacts." and both stay.
  - `testTheConfirmScrollsAtTheLargestTextSize`: with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`, `merge.confirm.merge` is reachable with `app.reveal`.
  - The drag test of Task 6, when it runs.
- [ ] **Step 2: Run the class, then `PeopleContactsUITests`, `PeopleGuessUITests`, `PeopleUITests`, `EntityPageUITests`.** Expected: PASS.
- [ ] **Step 3: Commit.** `git commit -m "UI tests for merging two people"`

### Task 8: Docs, ledger and the device check

**Files:**
- Modify: `docs/specs/2026-11-18-people-contacts.md`, `docs/DECISIONS.md`, `docs/OVERVIEW.md`, this plan ("What changed while building")
- Create: `docs/plans/2026-11-19-people-contacts-c-device-check.md`

- [ ] **Step 1: The spec.** Add "(narrowed 2026-11-19, PC-c plan decision N)" notes: point 4 of "Merging two people" for the flags (decision 1) and the name as an alias (decision 3); point 3 for who stays on the button path (decision 2); point 8 for the forced case (decision 4). Change call 21 to match.
- [ ] **Step 2: `DECISIONS.md`.** One PC-c section: the ten plan decisions as approved, and each ruling's number range.
- [ ] **Step 3: `OVERVIEW.md`.** In the people part: two people can be merged, what joins, and Undo.
- [ ] **Step 4: The device check.** Items: the row and the picker; the confirm with two pictures; the merge and the notice; Undo; the drag on the grid and its motion, also with Reduce Motion and at the largest text size where the grid is a list; VoiceOver on the button path; the forced case with a real contact; two different contacts; a merge where one person is kept from the AI; a merge after which a new story says the old name.
- [ ] **Step 5: Run everything.** `swift test` in `ios/LifelineKit` and the whole UI suite. Record the counts and every failure in the ledger.
- [ ] **Step 6: Commit** the docs and the ledger.

---

## After PC-c

- The owner runs the device check. The phone branch needs a merge of this branch first, with the owner's word. On that branch the hand-made `photo_page_declined` table of the tests is the real one.
- PC-d (extractor handles) gets its own plan.
- Open from the spec: whether places and things merge by drag too (call 2).

## What changed while building

(Empty until work starts.)
