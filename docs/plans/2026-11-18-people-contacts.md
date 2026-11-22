# PC-a: Guesses About People Are Marked and Can Be Changed — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A link between a memory and a person records how it was made. A link the app chose from a name alone shows the "Assumed" mark. One sheet changes who a name means, with Undo. A guess teaches the app no name. This PR alone fixes the reported bug (a story filed under the wrong person with no sign and no repair).

**Architecture:** Tasks 1 to 5 are kit code. Migration v15 adds the columns. `PersonGuess` is a pure function with the seven matching rules. Keep calls it in place of `findPerson`. `PersonLinkActions` settles and moves links with a receipt. Tasks 6 to 8 are the views: one chip, one sheet, and their places on the cards, the landing, the memory page and the person's page. Task 9 is UI tests. Task 10 is docs.

**Tech Stack:** Swift 6, SwiftUI on iOS 26, GRDB, Swift Testing, XCUITest. One migration (v15). No new dependency. No Contacts framework in this PR. No network call. No prompt change.

**Spec:** `docs/specs/2026-11-18-people-contacts.md`. This plan builds "Origin of a link", "Matching a said name", "Where the mark shows", "Settling a guess", "Moving a name to another person" and the whole of "Data model". `docs/DECISIONS.md`, entry of 2026-11-18. Mock-ups: `docs/design/PC1_Assumed.dc.html`, `PC2_WhoIsThis.dc.html`, `PC3_PersonLinked.dc.html`.

**Later plans, not this one:** PC-b (contacts), PC-c (merge two people), PC-d (extractor handles). Each gets its own plan after this PR ships.

**Worktree and branch:** `.claude/worktrees/people-contacts-16241d`, branch `claude/people-contacts-16241d`, from `main`. Never push. Never open a PR without the owner's word. No AI attribution in a commit.

---

## Decisions made in this plan

The spec leaves these open. The owner can overrule each one before work starts.

1. **v15 adds every column of the spec's data model now.** PC-b then needs no migration. The contact columns stay null in this PR. The migration was first built as `v14` and renamed to `v15` after the final review (R36): the photo story registered its own `v14` first.
2. **`PersonGuess` has all seven rules now, with tests.** The app passes an empty contact list until PC-b, so rules 5 and 6 cannot fire on the phone yet.
3. **The line for a new person is "New" in this PR.** "New · not in your contacts" would be a claim the app has not checked. PC-b adds the second half.
4. **The relation phrase for a said name** comes from two places: the comma form of the ref ("my mom, Marcel"), and the `relation_text` of a person mention in the same segment with the same text.
5. **A said name that a kept card carries makes no "Who's this?" follow-up chip.** The kept card shows the person chip in its place. The follow-up chip stays for a group phrase and for a name no memory carries.
6. **The landing shows chips on the rows it already shows,** and the count in its sub-line covers the whole recording. The landing gains no rows.
7. **"Someone else" lists every person on file** after the candidates, as today's card does behind its menu. Search comes with contacts in PC-b.
8. **The old "Who's this?" card stays** for mentions that are unresolved at upgrade, for group phrases, and for a name no memory carries. For that last case it keeps its four choices; it does not open the new sheet in this PR. The spec says it opens the sheet. This is a smaller first step, flagged for the owner.
9. **`created_by_guess` is cleared** when the owner settles a link to that person or renames them.
10. **Step 1's group** is: links in the same session, to the same person, whose `role_text` is equal by `PeopleRepository.normalize`.

### Limits found while planning

- **Rule 1 trusts old aliases** (spec call 20). An alias a wrong guess saved before this PR can still make an unmarked link. The owner removes it on the person's page.
- **A memory card's chips change from plain words to buttons.** `ExtractionUITests` and `FollowUpUITests` assert the old chips and the person follow-up. Task 9 moves them.
- **The photos branch (`photo-card`) also edits `EntityScreen.swift` and `docs/design/README.md`.** Expect a small conflict in the second branch to merge. Keep both sides.
- **Two simulators.** UI tests time out when another worktree uses the same simulator. Create one for this worktree: `xcrun simctl create "Lifeline People" "iPhone 17 Pro"`.

---

## Global Constraints

- Migration v15 is additive. It must not drop a column, delete a row or rewrite an existing row.
- The key of `moment_entity` stays (`memory_id`, `entity_id`, `relation`). A memory has at most one link to a person.
- Keep must not change an origin. Only an owner's action writes `confirmed`.
- An alias is saved only from a link with origin `said` or `confirmed`.
- An answer never changes a link in another session.
- No extraction path may call `PeopleRepository.findPerson` or `findPersonOrOwner`. They stay for a name the owner types.
- The owner is never a candidate for a said name.
- A move is one transaction. A kill leaves the old state or the new state.
- Ochre always comes with a word. The mark is a dashed outline plus "Assumed"; it never uses reduced opacity.
- Copy, exact (drafts until the owner writes final copy):
  - Chip lines: "Assumed · you said “{said name}”", "New".
  - Landing sub-line: "I made one guess about who you meant." / "I made {n} guesses about who you meant." No line when n is 0.
  - Sheet: title "Who is “{said name}” here?"; row lines "In {n} of your stories · my guess", "In {n} of your stories", "Not in a story yet"; "Someone new"; "Someone else"; "Not a person"; checkbox "Also change the {n} other moments from this recording" (singular: "Also change the 1 other moment from this recording"); button "Done"; foot "Nothing is deleted. You can change this again at any time."
  - Person's page: "Yes, this {name}", "Someone else…".
  - Notice: "Changed to {name}." with "Undo"; "Not a person." with "Undo"; a refused undo: "That changed since. Open the name to change it again."
  - VoiceOver label of a marked chip: "{name}, assumed, you said {said name}. Change who this is." Unmarked: "{name}. Change who this is."
- Accessibility identifiers, new: `person.chip`, `person.chip.assumed`, `who.sheet`, `who.option`, `who.new`, `who.else`, `who.notAPerson`, `who.group`, `who.done`, `entity.moment.assumed`, `entity.moment.confirm`, `entity.moment.someoneElse`, `landing.guesses`, `notice.undo` (reuse the existing one if `NoticeSlot` has it). Keep every existing identifier.
- Text colours: `Theme.ink`, `Theme.secondaryText`, `Theme.ochreText`, `Theme.olive`. The dashed outline uses `Theme.ochre`. No new colour value.
- Every control is at least 44 by 44 points. Dynamic Type must not clip; the chip's two lines wrap.
- Pure logic lives in `LifelineKit` with Swift Testing tests. One responsibility for each file. Sample names in tests are invented.
- Kit tests: `cd ios/LifelineKit && swift test`. UI tests: `xcodebuild test -project ios/Lifeline.xcodeproj -scheme Lifeline -destination 'id=<simulator id>' -only-testing:LifelineUITests/<Class>`. Run `xcodegen generate` in `ios/` after adding or deleting app or UI-test files.
- Add each ruling made while building to `.superpowers/sdd/2026-11-18-people-contacts/rulings.md` and keep `progress.md` current. Commit both.

## Review Focus

1. **A recording names one person twice in one moment** ("Robin" and "my roommate"). Expected: one chip, one link, the strongest origin. Test in Task 3.
2. **The owner moves a name to a person who is already in that moment.** Expected: one link, `confirmed`, no error, and Undo restores both rows. Test in Task 5.
3. **Undo after the moved link changed again.** Expected: Undo is refused with the notice, and nothing is overwritten. Test in Task 5.
4. **An upgraded archive.** Expected: every old link shows with no mark and still opens the sheet; no row count changes. Tests in Tasks 1 and 4.
5. **A retelling kept with "Same story"** runs the same link code as Keep. Expected: its people are guessed and marked by the same rules, and an existing `confirmed` link is not downgraded. Test in Task 3.

---

## File structure

Paths are under `ios/`. Kit paths are under `LifelineKit/Sources/LifelineKit/`.

| File | Responsibility |
| --- | --- |
| `Store/Migrations.swift` (modify) | v15 |
| `Domain/LinkOrigin.swift` (create) | `LinkOrigin` and its order of strength |
| `Domain/Entity.swift`, `Domain/Memory.swift`, `Domain/Profile.swift`, `Store/AppDatabase.swift`, `Store/EntityRepository.swift` (modify) | The new fields on `MomentEntity`, `MemoryPerson`, `Person` and their row mapping |
| `Confirmation/PersonGuess.swift` (create) | The seven rules. Pure |
| `Confirmation/SaidName.swift` (create) | A ref split into name and relation phrase. Pure |
| `Confirmation/CandidateActions.swift`, `Extraction/ExtractionQueue.swift`, `Confirmation/MergeActions.swift` (modify) | Keep writes guesses; no extraction path calls `findPerson` |
| `Domain/PersonLink.swift` (create) | A link as the views read it, and `PersonChipLine` |
| `Store/PersonLinkRepository.swift` (create) | Reads and writes of person links, groups, `candidate_person_choice` |
| `Confirmation/PersonLinkActions.swift` (create) | Preview, choose before Keep, settle, move, not a person, undo |
| `Confirmation/WhoIsThisOptions.swift` (create) | The sheet's rows. Pure |
| `Lifeline/Screens/People/PersonChip.swift` (create) | The chip |
| `Lifeline/Screens/People/WhoIsThisSheet.swift`, `WhoIsThisViewModel.swift` (create) | The sheet |
| `Lifeline/Screens/Cards/MemoryCard.swift`, `KeptCard.swift`, `CardHandler.swift`; `Screens/Landing/*`; `Screens/Memory/*`; `Screens/Entities/EntityScreen.swift`, `EntityViewModel.swift` (modify) | Where chips and marks show |
| `Lifeline/UITestSeed.swift`, `LifelineUITests/PeopleGuessUITests.swift` (modify, create) | Seed and UI tests |

---

### Task 1: Migration v15 and the origin of a link

**Files:**
- Modify: `Store/Migrations.swift`, `Domain/Entity.swift`, `Domain/Memory.swift`, `Domain/Profile.swift`, `Store/AppDatabase.swift` (`Person.selectSQL` and the `Person` row mapping), `Store/EntityRepository.swift` (`MomentEntity` mapping and `insertIgnoringDuplicate`)
- Create: `Domain/LinkOrigin.swift`
- Test: `LifelineKit/Tests/LifelineKitTests/MigrationsTests.swift`, `LinkOriginTests.swift` (create)

**Interfaces:**
- Produces:
  - `public enum LinkOrigin: String, Codable, Sendable, CaseIterable { case assumed, said, confirmed, new }` with `var strength: Int` (`confirmed` 3, `said` 2, `assumed` 1, `new` 0) and `static func stronger(_ a: LinkOrigin?, _ b: LinkOrigin?) -> LinkOrigin?` (nil is weaker than every case).
  - `public enum NameOrigin: String, Codable, Sendable { case said, typed, contact }` in the same file.
  - `MomentEntity.origin: LinkOrigin?` and `MomentEntity.personHandle: String?`, both defaulting to nil in `init`.
  - `MemoryPerson.origin: LinkOrigin?`, default nil; `MemoryPerson.link` carries it.
  - `Person.nameOrigin: NameOrigin?`, `Person.createdByGuess: Bool` (default false), `Person.contactIdentifier: String?`, `Person.contactName: String?`, `Person.contactState: String?`, `Person.contactPhotoID: PhotoID?`, all with defaults in `init` so no call site changes.
- v15, exact:
  - `person`: add `contact_identifier` text, `contact_name` text, `contact_state` text, `contact_photo_id` text references `photo` on delete set null, `name_origin` text, `created_by_guess` boolean not null default false. Unique index `person_contact_identifier` on `contact_identifier` where it is not null.
  - `moment_entity`: add `origin` text, `person_handle` text.
  - Table `contact_declined` (`person_id` text not null references `person` on delete cascade, `contact_identifier` text not null, primary key on both).
  - Table `candidate_person_choice` (`candidate_id` text not null references `candidate` on delete cascade, `said_name` text not null, `choice` text not null, `person_id` text references `person` on delete cascade, `contact_identifier` text, primary key (`candidate_id`, `said_name`)). `said_name` is stored normalized.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func v15KeepsEveryRowAndAddsNothingToOldLinks() throws {
    // Build a database at v13 with the test file's existing helper, with one person, one memory and one link.
    // Migrate to the latest.
    #expect(try count("person") == 1); #expect(try count("moment_entity") == 1)
    #expect(try String.fetchOne(db, sql: "select origin from moment_entity") == nil)
    #expect(try Bool.fetchOne(db, sql: "select created_by_guess from person") == false)
    #expect(try tableExists("contact_declined")); #expect(try tableExists("candidate_person_choice"))
}

@Test func oneContactBelongsToOnePerson() throws {
    // Two persons, the same contact_identifier: the second update throws a unique-constraint error.
    // Two persons with a null contact_identifier: no error.
}

@Test func aLinkRoundTripsItsOrigin() throws {
    // insert MomentEntity(..., origin: .assumed, personHandle: "p1"); fetch; #expect equal.
    // insertIgnoringDuplicate writes origin and person_handle.
}

@Test func strongerOrigin() {
    #expect(LinkOrigin.stronger(.assumed, .confirmed) == .confirmed)
    #expect(LinkOrigin.stronger(.new, .assumed) == .assumed)
    #expect(LinkOrigin.stronger(nil, .new) == .new)
    #expect(LinkOrigin.stronger(nil, nil) == nil)
}
```

- [ ] **Step 2: Run `swift test --filter "Migrations|LinkOrigin"`.** Expected: FAIL, the types and columns do not exist.
- [ ] **Step 3: Write v15, `LinkOrigin.swift`, and the new fields with their row mapping.** `Person.selectSQL` must select the six new columns. The backup round-trip test in `BackupTests` must still pass with no change to it.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, the whole suite.
- [ ] **Step 5: Commit.** `git commit -m "Migration v15: a link records how it was made"`

---

### Task 2: `PersonGuess`, the seven rules

**Files:**
- Create: `Confirmation/PersonGuess.swift`, `Confirmation/SaidName.swift`
- Test: `LifelineKit/Tests/LifelineKitTests/PersonGuessTests.swift`, `SaidNameTests.swift` (create)

**Interfaces:**
- Consumes: `LinkOrigin`, `PeopleRepository.normalize`, `PeopleRepository.parts(of:)`, `GroupPhrase.isGroup`.
- Produces:

```swift
public struct SaidName: Sendable, Equatable {
    public var name: String?        // "Marcel"; nil when only a relation phrase was said
    public var relation: String?    // "my mom"
    public var raw: String          // the ref as the extractor gave it
    /// `mentionRelation` is the relation_text of a person mention in the same segment with this text.
    public init(ref: String, mentionRelation: String? = nil)
    /// Lowercased, trimmed, diacritics folded. The key every comparison in this feature uses.
    public static func key(_ text: String) -> String
}

public enum PersonGuess {
    public struct Known: Sendable, Equatable {
        public var id: PersonID; public var name: String; public var aliases: [String]
        public var lastLinked: Date?; public var contactIdentifier: String?
    }
    public struct Contact: Sendable, Equatable {
        public var identifier: String; public var fullName: String; public var givenName: String; public var nickname: String
    }
    public enum Choice: Sendable, Equatable, Hashable { case person(PersonID), contact(String), newPerson }
    public struct Result: Sendable, Equatable {
        public var choice: Choice; public var origin: LinkOrigin; public var rule: Int
        /// Every other candidate, persons first, in the order the sheet shows them.
        public var others: [Choice]
    }
    public static func guess(_ said: SaidName, people: [Known], contacts: [Contact]) -> Result
}
```

- Rules, exact (spec "Matching a said name"): a relation phrase is a text that starts with "my " or "our ". A contact with an identifier that a `Known` holds is not a candidate. In rule 4, "most recently linked" is the greatest `lastLinked`, nil last, then the name by `caseInsensitiveCompare`, so the choice never varies. A group phrase never reaches `guess`; the caller filters it.

- [ ] **Step 1: Write the failing tests.** One test for each row. Names are invented.

| Test | Input | Expected |
| --- | --- | --- |
| `rule1NameAndRelationPointToOne` | said "Danielle" + "my sister"; Danielle A (aliases "my sister"), Danielle B | `.person(A)`, `.said`, rule 1, others `[.person(B)]` |
| `rule1NeedsBothOnOnePerson` | said "Danielle" + "my sister"; Danielle A, and Kira with alias "my sister" | rule 4, `.assumed` |
| `rule2RelationAlone` | said "my mom"; Marcel with alias "my mom" | `.person(Marcel)`, `.said`, rule 2 |
| `rule2RelationHeldByTwo` | said "my roommate"; two persons with that alias, different `lastLinked` | the later one, `.assumed`, rule 4 |
| `rule3FullerNameFitsThePersonOnly` | said "Robin Okafor"; person "Robin Okafor", contact "Robin Vale" | `.person`, `.assumed`, rule 3 |
| `rule3FullerNameFitsTheContactOnly` | said "Robyn Vale"; person "Robyn" , contact "Robyn Vale" | `.contact("c1")`, `.assumed`, rule 3 |
| `rule4PersonBeatsContact` | said "Robin"; person "Robin Okafor" with alias "Robin", contact given name "Robin" | `.person`, `.assumed`, rule 4, others `[.contact]` |
| `rule4TwoPersonsMostRecentWins` | said "Robin"; two persons named "Robin" | later `lastLinked`, `.assumed`, others holds the other |
| `rule4KnownNameNewRelation` | said "Robin" + "my roommate"; one Robin without that alias | `.person`, `.assumed`, rule 4 |
| `rule5OneContact` | said "Priya"; no person; one contact given name "Priya" | `.contact`, `.assumed`, rule 5 |
| `rule6TwoContacts` | said "Sam"; no person; two contacts "Sam …" | `.newPerson`, `.new`, rule 6, others both contacts |
| `rule7Nothing` | said "Tomas"; nothing | `.newPerson`, `.new`, rule 7, others empty |
| `aLinkedContactIsThatPerson` | said "Robin"; person with `contactIdentifier` "c1"; contact "c1" given name "Robin" | `.person`, others empty |
| `caseAndDiacritics` | said "josé"; person "José" | `.person`, rule 4 |
| `nicknameFitsAContact` | said "Bee"; contact nickname "Bee" | `.contact`, rule 5 |
| `saidNameParts` | `SaidName(ref: "my mom, Marcel")` | name "Marcel", relation "my mom" |
| `saidNameFromMention` | `SaidName(ref: "Robin", mentionRelation: "my roommate")` | name "Robin", relation "my roommate" |
| `saidRelationOnly` | `SaidName(ref: "my mom")` | name nil, relation "my mom" |

- [ ] **Step 2: Run `swift test --filter "PersonGuess|SaidName"`.** Expected: FAIL, the types do not exist.
- [ ] **Step 3: Implement both files.** `guess` builds the candidate list once, then applies rules 1 to 7 in order and returns at the first that applies.
- [ ] **Step 4: Run the filter again.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "PersonGuess: the rules that choose who a said name means"`

---

### Task 3: Keep writes guesses, and no extraction path calls `findPerson`

**Files:**
- Modify: `Confirmation/CandidateActions.swift` (`Edges`, `edges(of:)`, `finishEdges`, `aboutEntity`, `resolveMention`, remove `resolveIfKnown`), `Extraction/ExtractionQueue.swift` (the `knownMentions` path, lines near 209, 258 and 285), `Confirmation/MergeActions.swift` (`people(named:)`), `Confirmation/EntityActions.swift` (unchanged call to `findPersonOrOwner`: the owner chose "a person" there; set the link's origin to `confirmed`), `Store/MemoryRepository.swift` (`insert` writes `origin`; `link(_:to:roleText:)` gains `origin: LinkOrigin? = .confirmed`)
- Create: `Store/PersonLinkRepository.swift` (only `known()` and `choices(for:)` in this task)
- Test: `LifelineKit/Tests/LifelineKitTests/PersonGuessOnKeepTests.swift` (create); update `CandidateActionsTests.swift`, `ExtractionQueueTests.swift`, `V7PeopleRulesTests.swift` where they assert the old silent link

**Interfaces:**
- Consumes: `PersonGuess.guess`, `SaidName`, `LinkOrigin`, `EntityRepository.Write.persons`.
- Produces:
  - `PersonLinkRepository(_ db: AppDatabase)`, reached as `store.personLinks` on `ExtractionStore`.
  - `func known() throws -> [PersonGuess.Known]`: every person but the owner, with aliases and the latest `memory.created_at` over their links.
  - `struct PersonChoice { var saidKey: String; var choice: PersonGuess.Choice?; var notAPerson: Bool }` and `func choices(for candidate: CandidateID) throws -> [PersonChoice]`.
  - `Edges.people` rows carry `origin`. `Edges.unknown` holds only group phrases after this task.
  - `CandidateActions.contactsForGuess: @Sendable () -> [PersonGuess.Contact]`, a stored property that defaults to `{ [] }`. PC-b sets it.

Behaviour, exact:

1. In `edges(of:)`, for each `people_refs` entry that is not the owner's name: a group phrase goes to `unknown` as today. Every other ref becomes a `SaidName` (decision 4) and goes through `PersonGuess.guess`, unless `candidate_person_choice` holds a choice for its key; a stored choice is applied with origin `confirmed`, and "not a person" writes no link.
2. `.person(id)`: a `MemoryPerson` with the result's origin and `roleText` the ref. `.newPerson`: a `Person` with `nameOrigin: .said`, `createdByGuess: true`, added to `entityWrite.persons` with its entity, and a link with origin `new`. A new person's name is `said.name ?? said.relation`. `.contact` cannot occur in this PR; treat it as `.newPerson` and leave a one-line comment that PC-b replaces it.
3. Two refs in one card that reach one person make one link: the first ref's `roleText`, and `LinkOrigin.stronger` of the two origins.
4. Two refs in one card with the same key reach the same planned new person, not two.
5. Aliases: the relation half is saved (`roleAliases`) only when the origin is `said` or `confirmed`. A new person's own name is their alias, as `insertPerson` does today.
6. A link that already exists on the memory (Same story, a retelling) keeps the stronger origin. `insertIgnoringDuplicate` leaves the old row; when the new origin is stronger, update the row's `origin`.
7. `aboutEntity`: a fact about a person named in the segment uses the same guess for that name, and the `detail` link carries the same origin.
8. `ExtractionQueue`: a person mention whose text a memory candidate of the same pass carries (`Self.carried`) is stored with status `accepted` and shows no card. A person mention nothing carries shows its card, as an unknown name does today. The `knownMentions` list and the call to `resolveIfKnown` go.
9. `MergeActions.people(named:)` reads the memory's own links whose `role_text` equals a ref by `SaidName.key`. It does not look a person up by name.
10. `resolveMention`: the loop over "the same name waiting in other segments" is limited to segments of the same session.

- [ ] **Step 1: Write the failing tests** in `PersonGuessOnKeepTests.swift`. Use `StoreFixtures` and the scripted candidates the existing `CandidateActionsTests` use.

```swift
@Test func aKnownBareNameIsLinkedAsAssumed()        // Robin on file; card says "Robin" → one link, origin .assumed
@Test func keepDoesNotSaveARelationFromAGuess()     // "my roommate, Robin" → Robin's aliases do not gain "my roommate"
@Test func nameWithAKnownRelationIsSaid()           // Danielle has alias "my sister"; a second Danielle exists → link to the first, origin .said
@Test func anUnknownNameMakesAPersonMarkedNew()     // "Tomas" → person created, createdByGuess true, nameOrigin .said, link origin .new, no unresolved mention row
@Test func aGroupPhraseStillMakesAMention()         // "our parents" → mention row unresolved, no person
@Test func theOwnersNameIsNeverACandidate()
@Test func onePersonNamedTwiceInOneCardIsOneLink()  // refs "Robin" and "my roommate, Robin" → one row, roleText "Robin"   (Review Focus 1)
@Test func aStoredChoiceWinsOverTheGuess()          // candidate_person_choice says person B → link to B, origin .confirmed
@Test func aStoredNotAPersonWritesNoLink()
@Test func aRetellingDoesNotDowngradeAConfirmedLink() // link confirmed; Same story adds the name again → still .confirmed   (Review Focus 5)
@Test func aFactAboutAGuessedPersonCarriesTheOrigin()
@Test func aCarriedPersonNameShowsNoCard()          // ExtractionQueue: the mention row is accepted, not shown
@Test func anAnswerStaysInItsRecording()            // two sessions say "Robin"; answering one mention leaves the other unresolved
@Test func noExtractionPathCallsFindPerson()        // walk the kit sources as PersonSplitTests does: only PeopleRepository.swift, EntityActions.swift and the
                                                    // typed-name functions linkNewPerson / resolveMention(.new) may contain "findPerson"
```

- [ ] **Step 2: Run `swift test --filter PersonGuessOnKeep`.** Expected: FAIL.
- [ ] **Step 3: Implement** the ten behaviours. Update the older tests that assert a silent link so they assert the origin.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, the whole suite.
- [ ] **Step 5: Commit.** `git commit -m "Keep links a said name as a marked guess, never silently"`

---

### Task 4: Reading links for the views

**Files:**
- Create: `Domain/PersonLink.swift`
- Modify: `Store/PersonLinkRepository.swift`
- Test: `LifelineKit/Tests/LifelineKitTests/PersonLinkRepositoryTests.swift`, `PersonChipLineTests.swift` (create)

**Interfaces:**
- Produces:

```swift
public struct PersonLink: Sendable, Equatable, Identifiable {
    public var memoryID: MemoryID; public var person: Person
    public var saidName: String?; public var origin: LinkOrigin?; public var relation: EntityRelation
    public var id: String { "\(memoryID.rawValue)|\(person.id.rawValue)|\(relation.rawValue)" }
    public var isGuess: Bool { origin == .assumed }
}
public enum PersonChipLine {
    /// nil for a link with no line (said, confirmed, older).
    public static func text(origin: LinkOrigin?, saidName: String?) -> String?
    public static func accessibilityLabel(name: String, origin: LinkOrigin?, saidName: String?) -> String
    public static func landingLine(guesses: Int) -> String?
}
extension PersonLinkRepository {
    func links(of memory: MemoryID) throws -> [PersonLink]                 // relation .mention, by person name; never the owner
    func links(to person: PersonID) throws -> [PersonLink]                 // both relations
    func group(of link: PersonLink) throws -> [PersonLink]                 // plan decision 10; includes `link`
    func guessCount(in session: SessionID) throws -> Int                   // links with origin .assumed
}
```

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func chipLines() {
    #expect(PersonChipLine.text(origin: .assumed, saidName: "Robin") == "Assumed · you said “Robin”")
    #expect(PersonChipLine.text(origin: .new, saidName: "Tomas") == "New")
    #expect(PersonChipLine.text(origin: .said, saidName: "Danielle") == nil)
    #expect(PersonChipLine.text(origin: .confirmed, saidName: "Robin") == nil)
    #expect(PersonChipLine.text(origin: nil, saidName: "Maya") == nil)          // an older link: no mark (Review Focus 4)
    #expect(PersonChipLine.landingLine(guesses: 0) == nil)
    #expect(PersonChipLine.landingLine(guesses: 1) == "I made one guess about who you meant.")
    #expect(PersonChipLine.landingLine(guesses: 2) == "I made 2 guesses about who you meant.")
    #expect(PersonChipLine.accessibilityLabel(name: "Robin Okafor", origin: .assumed, saidName: "Robin")
            == "Robin Okafor, assumed, you said Robin. Change who this is.")
}
@Test func theGroupIsTheSameNameAndPersonInOneSession()   // three moments say "Robin" → group of 3; a "Robin" in another session is not in it;
                                                          // a "robin " with other case and spaces is in it; a link to another person is not
@Test func guessCountCountsAssumedOnly()
@Test func anOlderLinkReadsWithNoOrigin()
```

- [ ] **Step 2: Run the two filters.** Expected: FAIL.
- [ ] **Step 3: Implement.** A link's session is the session of the segment of the memory's first span.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Read a person link with its origin, its group and its line"`

---

### Task 5: Settle, move, and Undo

**Files:**
- Create: `Confirmation/PersonLinkActions.swift`
- Modify: `Store/PersonLinkRepository.swift` (the writes), `Store/PeopleRepository.swift` (`rename` clears `created_by_guess` and sets `name_origin` to `typed`)
- Test: `LifelineKit/Tests/LifelineKitTests/PersonLinkActionsTests.swift` (create)

**Interfaces:**
- Consumes: `PersonLink`, `PersonLinkRepository.group(of:)`, `PersonGuess.Choice`.
- Produces:

```swift
public struct PersonMoveReceipt: Sendable, Equatable {
    public var before: [MomentEntity]      // every link row the move touched, as it was
    public var after: [MomentEntity]       // as the move left them
    public var removedPerson: Person?      // an empty guessed person the move removed, with its entity, aliases and first telling
    public var addedAliases: [Alias]
    public var createdPerson: PersonID?    // "Someone new"
    public var newName: String             // for the notice
}
public struct PersonLinkActions: Sendable {
    public enum Error: Swift.Error, Equatable { case stale, notFound }
    public enum Target: Sendable, Equatable { case person(PersonID), someoneNew, notAPerson }
    public init(store: ExtractionStore)
    /// "Yes, this Robyn", and "Done" with the choice unchanged. Origin becomes .confirmed for the link, or its group.
    public func settle(_ link: PersonLink, wholeGroup: Bool) throws
    /// The sheet's "Done" with another choice. One transaction.
    @discardableResult public func move(_ link: PersonLink, to target: Target, wholeGroup: Bool) throws -> PersonMoveReceipt
    public func undo(_ receipt: PersonMoveReceipt) throws
    /// The sheet used on a card that waits: stored, applied on Keep.
    public func choose(_ target: Target, for saidName: String, on candidate: CandidateID) throws
    /// What Keep would do for each said name of a waiting memory card. Writes nothing.
    public func preview(_ candidate: Candidate) throws -> [PreviewChip]
}
public struct PreviewChip: Sendable, Equatable, Identifiable {
    public var saidName: String; public var name: String; public var origin: LinkOrigin; public var person: PersonID?
    public var id: String { SaidName.key(saidName) }
}
```

Behaviour, exact (spec "Moving a name to another person"):

1. `settle`: sets `origin` to `confirmed`; saves the said name and, when the card gave one, its relation phrase as aliases of the person (never a group phrase); clears `created_by_guess`.
2. `move` to `.person(p)`: for each link in scope, delete the old row and write a row for `p` with the same `role_text` and `relation`, origin `confirmed`. When `p` already has that row, keep it and set its origin to `confirmed`.
3. Details: a `detail` link of the same session to the old person moves too when its card's `about_ref` points at a mention with the same said key. A detail the owner placed with `moveDetail` has no such card ref and stays. A detail of the old person in a memory whose mention is in the move also moves (R38, after the final review).
4. First telling: when the old person's `entity_span` of order 0 came from a moved memory, replace it with the first span of their oldest remaining moment, or delete it when none remains. Give `p` a first telling only when `p` has none (`EntityRepository.giveFirstTelling` already has that rule).
5. Aliases: the said name and its relation become aliases of `p`. The old person's aliases do not change.
6. The empty guess: when the old person has `created_by_guess` true and now has no link, no photo link and no `contact_identifier`, delete the person and their entity. Put them in the receipt. After the final review (R39), the person must also have `name_origin` `said`, no stated range, and default hidden and excluded flags.
7. `.someoneNew`: create a person named by the said name (`nameOrigin: .said`, `createdByGuess: false`), then as `.person`.
8. `.notAPerson`: delete the links in scope; rule 6 applies. No alias is saved.
9. `undo`: refuse with `.stale` unless every row in `receipt.after` is in the database exactly as recorded and every row the move deleted is still absent. Then restore `before`, the removed person, and delete `addedAliases` and `createdPerson`. One transaction.
10. `preview`: for each said name of the card, the stored choice when one exists (origin `confirmed`), else `PersonGuess.guess`. A group phrase gives no chip.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func settleConfirmsOneLinkOrTheGroup()
@Test func settleSavesTheRelationOnlyNow()                 // "my roommate, Robin" kept as a guess; after settle the alias exists
@Test func moveRepointsTheLinkAndKeepsTheSaidName()
@Test func moveCarriesTheGroupInOneRecordingOnly()         // wholeGroup true: 3 links move; the same name in another session does not
@Test func moveWithoutTheGroupMovesOne()
@Test func moveOntoAPersonAlreadyInTheMomentLeavesOneConfirmedLink()   // Review Focus 2
@Test func moveTakesTheFactsAboutThatNameAndLeavesHandPlacedOnes()
@Test func moveGivesTheOldPersonAnotherFirstTelling()
@Test func moveRemovesAnEmptyGuessedPersonOnly()           // created_by_guess with nothing left → gone; a person with a photo, or one not made by a guess → stays
@Test func someoneNewMakesAPersonThatIsNotAGuess()
@Test func notAPersonRemovesTheLinkAndSavesNoAlias()
@Test func undoRestoresEveryRowAndTheRemovedPerson()
@Test func undoIsRefusedWhenALinkChangedSince()            // Review Focus 3: move, then settle or move again, then undo → throws .stale, rows unchanged
@Test func aKillMidMoveLeavesOneState()                    // run the move inside a transaction that throws at the end; every row is as before
@Test func aChoiceBeforeKeepIsStoredAndPreviewed()
@Test func previewWritesNothing()                          // row counts of person, entity, moment_entity, alias are unchanged
@Test func renameClearsCreatedByGuess()
```

- [ ] **Step 2: Run `swift test --filter PersonLinkActions`.** Expected: FAIL.
- [ ] **Step 3: Implement.** All writes of one action run in one `db.writer.write`.
- [ ] **Step 4: Run `swift test`.** Expected: PASS, the whole suite.
- [ ] **Step 5: Commit.** `git commit -m "Settle or move a person link, with a receipt and Undo"`

---

### Task 6: The sheet's rows, the chip and the sheet

**Files:**
- Create: `Confirmation/WhoIsThisOptions.swift`, `Lifeline/Screens/People/PersonChip.swift`, `Lifeline/Screens/People/WhoIsThisSheet.swift`, `Lifeline/Screens/People/WhoIsThisViewModel.swift`
- Test: `LifelineKit/Tests/LifelineKitTests/WhoIsThisOptionsTests.swift` (create)

**Interfaces:**
- Consumes: `PersonGuess.Result`, `PersonLink`, `PersonLinkActions`, `PreviewChip`, `PersonChipLine`.
- Produces:

```swift
public struct WhoIsThisOptions: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public var target: PersonLinkActions.Target; public var title: String; public var line: String; public var isCurrent: Bool
        public var id: String
    }
    public var saidName: String; public var quote: String?
    public var rows: [Row]             // the current choice first, then the other candidates
    public var everyoneElse: [Row]     // the other persons on file, by name, behind "Someone else"
    public var otherMoments: Int       // the group without this link; 0 hides the checkbox
    public static func build(saidName: String, quote: String?, current: PersonID?, currentIsGuess: Bool,
                             candidates: [PersonID], people: [(Person, stories: Int)], otherMoments: Int) -> WhoIsThisOptions
    public static func groupLabel(_ n: Int) -> String
}
```

  - Lines: the current choice when it is a guess: "In {n} of your stories · my guess"; any other person: "In {n} of your stories"; n of 0: "Not in a story yet". "{n} of your stories" is the count of the person's moments, as the People tile counts them.
  - `PersonChip(name:line:isAssumed:accessibilityLabel:onTap:)`: a button, at least 52 points high. Initials in a 36-point circle (the person's key photo when they have one, through the existing `PhotoImageView`), the name, the line under it, a chevron. Assumed: a 1.5-point dashed `Theme.ochre` outline and the line in `Theme.ochreText`. Otherwise a 1-point solid outline in the card border colour and the line in `Theme.secondaryText`. Identifier `person.chip`, or `person.chip.assumed`.
  - `WhoIsThisViewModel(source:deps:)` with `enum Source { case link(PersonLink), waiting(candidate: Candidate, chip: PreviewChip) }`, `var options: WhoIsThisOptions`, `var selected: PersonLinkActions.Target`, `var wholeGroup: Bool` (starts true), and `func done() -> Outcome` with `enum Outcome { case unchanged, settled, moved(PersonMoveReceipt), stored, failed(String) }`. For `.link`: the same target as the current person calls `settle`; another calls `move`. For `.waiting`: `choose`.
  - `WhoIsThisSheet(viewModel:onDone:)`: the layout of PC2, as a `.sheet` with medium and large detents. Radio rows (`who.option`), "Someone new" (`who.new`), "Someone else" as a disclosure that shows `everyoneElse` (`who.else`), "Not a person" as a quiet row (`who.notAPerson`), the checkbox (`who.group`), "Done" (`who.done`), the foot line. The sheet's root has `who.sheet`.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func theGuessIsFirstAndSaysItIsAGuess()      // rows[0].isCurrent, line "In 12 of your stories · my guess"
@Test func aSettledCurrentChoiceDoesNotSayGuess()  // currentIsGuess false → "In 12 of your stories"
@Test func otherCandidatesFollowInOrder()
@Test func aPersonInNoStory()                      // "Not in a story yet"
@Test func everyoneElseLeavesOutTheCandidatesAndTheOwner()
@Test func groupLabels() {
    #expect(WhoIsThisOptions.groupLabel(1) == "Also change the 1 other moment from this recording")
    #expect(WhoIsThisOptions.groupLabel(2) == "Also change the 2 other moments from this recording")
}
@Test func aWaitingCardHasNoCurrentPersonForANewName()   // current nil → "Someone new" is the selected row
```

- [ ] **Step 2: Run `swift test --filter WhoIsThisOptions`.** Expected: FAIL.
- [ ] **Step 3: Implement the kit file, then the three app files.** Run `xcodegen generate` in `ios/`.
- [ ] **Step 4: Run `swift test`, then build the app:** `xcodebuild build -project ios/Lifeline.xcodeproj -scheme Lifeline -destination 'id=<simulator id>'`. Expected: PASS and BUILD SUCCEEDED.
- [ ] **Step 5: Commit.** `git commit -m "The Who is this sheet and the person chip"`

---

### Task 7: Chips on the cards, the landing and the memory page

**Files:**
- Modify: `Lifeline/Screens/Cards/MemoryCard.swift` (the `FlowChips` of `peopleRefs`), `KeptCard.swift`, `CardHandler.swift`, `Lifeline/Screens/Landing/LandingViewModel.swift`, `LandingScreen.swift`, `Lifeline/Screens/Memory/MemoryViewModel.swift`, `MemoryScreen.swift` (the "with …" line near line 57)
- Modify (kit): `Extraction/KeptCard.swift` and `Extraction/FollowUpOwner.swift` only if a carried person name still yields a follow-up after Task 3; it must not.

**Interfaces:**
- Consumes: `PersonChip`, `WhoIsThisSheet`, `WhoIsThisViewModel.Source`, `PersonLinkActions.preview`, `PersonLinkRepository.links(of:)`, `guessCount(in:)`, `PersonChipLine.landingLine`, `NoticeSlot`.
- Produces: `CardHandler.previewChips(for card: Card) -> [PreviewChip]`, `CardHandler.personLinks(for memory: MemoryID) -> [PersonLink]`, `CardHandler.undoPersonMove() -> Bool`, and on each host view model a `notice` for "Changed to {name}." with Undo for 6 seconds, in the slot the host already uses.

Behaviour:

1. **A memory card that waits:** under the heading "With", one `PersonChip` for each `PreviewChip`. The place chip stays a plain chip. A tap opens the sheet with `.waiting`. After "Done" the chip shows the stored choice with no mark.
2. **A kept card:** one `PersonChip` for each `PersonLink` of the kept memory, above the follow-up chips. A tap opens the sheet with `.link`.
3. **The landing:** `landing.guesses` shows `PersonChipLine.landingLine(guesses:)` under the headline, for the whole session. Each row shows the chips of its memory. The line and the chips refresh after the sheet closes.
4. **The memory page:** the "with A and B" text becomes a row of chips from `links(of:)`. A place keeps its text.
5. **After a move:** the host shows "Changed to {name}." with Undo. Undo calls `PersonLinkActions.undo`; on `.stale` the slot shows "That changed since. Open the name to change it again."
6. **Largest text sizes:** the chips stack one for each line; nothing truncates.

- [ ] **Step 1: Make the changes.** No new kit logic belongs here; if a view needs a rule, move it to the kit with a test.
- [ ] **Step 2: Run `swift test` and build the app.** Expected: PASS and BUILD SUCCEEDED.
- [ ] **Step 3: Run the existing UI test classes that touch these screens:** `ExtractionUITests`, `FollowUpUITests`, `LandingUITests`, `PeopleUITests`. Note each failure that comes from the old chips; Task 9 moves those assertions. A failure of any other kind is a bug in this task: fix it now.
- [ ] **Step 4: Commit.** `git commit -m "Show who the app assumed on cards, the landing and the memory page"`

---

### Task 8: The person's page

**Files:**
- Modify: `Lifeline/Screens/Entities/EntityViewModel.swift`, `EntityScreen.swift` (the `moment(_:)` and `detail(_:)` rows)

**Interfaces:**
- Consumes: `PersonLinkRepository.links(to:)`, `PersonLinkActions.settle`, `WhoIsThisSheet`.
- Produces: `EntityViewModel.guessed: [MemoryID: PersonLink]` (links to this person with origin `assumed`), `func confirm(_ memory: MemoryID)`, `func undoPersonMove()`.

Behaviour (PC3):

1. A moment or detail in `guessed` shows in a card with the dashed ochre outline, the line "Assumed · you said “{said name}”" in place of the date line's colour only (the date stays), and two buttons: "Yes, this {name}" (`entity.moment.confirm`) and "Someone else…" (`entity.moment.someoneElse`). `{name}` is the first word of the person's name. The row has `entity.moment.assumed`.
2. "Yes, this {name}" settles that one link. The mark goes at once. No notice.
3. "Someone else…" opens the sheet for that link. After a move the moment leaves this page, and the page's notice slot shows "Changed to {name}." with Undo.
4. When the move removed this person (an empty guess), the page closes and the notice shows on the screen under it.
5. A row with no guess is unchanged. PC3 must not carry more controls for each moment than PC2 has options: a settled row has none.
6. Places, things and ideas are unchanged.

- [ ] **Step 1: Make the changes.**
- [ ] **Step 2: Run `swift test`, build, and run `EntityPageUITests`.** Expected: PASS.
- [ ] **Step 3: Commit.** `git commit -m "A guessed moment on a person's page can be confirmed or changed"`

---

### Task 9: UI tests

**Files:**
- Modify: `Lifeline/UITestSeed.swift` (a seed `guesses`), `Lifeline/Dependencies.swift` (its launch argument, beside the existing ones), `LifelineUITests/ExtractionUITests.swift`, `FollowUpUITests.swift`, `LandingUITests.swift` (move the assertions Task 7 broke)
- Create: `LifelineUITests/PeopleGuessUITests.swift`

**Seed `guesses`, invented:** persons "Robin Okafor" (alias "Robin", two older moments with no origin) and "Danielle" (alias "my sister"). One session with three kept moments: "The flat on Alder Street" and "The night the boiler went", both linked to Robin Okafor with origin `assumed` and said name "Robin"; "Dinner on the deposit", linked to a new person "Tomas" with origin `new` and to Danielle with origin `said`.

- [ ] **Step 1: Write the tests.**

```swift
func testTheLandingStatesTheGuesses()            // landing.guesses reads "I made 2 guesses about who you meant."
func testAnAssumedChipIsMarkedAndASaidOneIsNot() // person.chip.assumed exists for Robin Okafor with "Assumed · you said “Robin”"; Danielle's chip is person.chip with no line
func testAnOlderLinkHasNoMark()                  // open an older moment: Robin's chip is person.chip
func testTheSheetMovesANameAndUndoRestoresIt()   // tap the chip → who.sheet; choose "Someone new"; who.group is on; Done →
                                                 // both moments show "Robin" with no mark; notice "Changed to Robin." ; Undo → both show Robin Okafor, assumed
func testDoneWithTheSameChoiceSettlesTheGuess()  // open, Done → the mark is gone on that moment and, with the group on, on the other
func testYesThisRobinClearsOneMark()             // Robin Okafor's page: two entity.moment.assumed; tap entity.moment.confirm on one → one left
func testSomeoneElseFromThePageRemovesTheMoment()
func testNotAPersonRemovesTheChip()
func testTheSheetAtTheLargestTextSize()          // launch with the accessibility size the other suites use; who.done is hittable after a scroll
```

- [ ] **Step 2: Run `xcodegen generate`, then `-only-testing:LifelineUITests/PeopleGuessUITests`.** Expected: PASS.
- [ ] **Step 3: Run the whole UI suite.** Expected: PASS. Fix the moved assertions in the three older classes.
- [ ] **Step 4: Commit.** `git commit -m "UI tests: a guess is marked, changed, settled and undone"`

---

### Task 10: Docs, ledger and the device check

**Files:**
- Modify: `docs/OVERVIEW.md` (the part that says how a name is matched), `docs/DECISIONS.md` (one entry: the rulings made while building, from the ledger), `docs/GOOD_FIRST_TASKS.md` only if it names `WhoIsThisCard`
- Create: `docs/plans/2026-11-18-people-contacts-device-check.md`
- Commit: `.superpowers/sdd/2026-11-18-people-contacts/progress.md`, `rulings.md`

The device check list, exact items:

1. Record a story that names a person on file by first name. The chip shows "Assumed".
2. Record "…, my sister" for a person who has that name. No mark.
3. Record a name the app does not know. The chip shows "New", and the person is in People.
4. Change a guess to "Someone new" with the checkbox on. Every moment of that recording changes. Older stories do not.
5. Undo within 6 seconds. Everything is back.
6. Open the wrong roommate link from the first real story (an older link, no mark). The sheet opens and moves it.
7. VoiceOver reads a marked chip as "{name}, assumed, you said {said name}. Change who this is."
8. The largest text size: the chip wraps and the sheet scrolls to "Done".
9. Kill the app with the sheet open. Nothing changed.

- [ ] **Step 1: Write the docs.** ASD-STE100 style.
- [ ] **Step 2: Run `swift test` and the whole UI suite once more.** Expected: PASS.
- [ ] **Step 3: Commit.** `git commit -m "Docs: how a name is matched now, the rulings and the device check"`
- [ ] **Step 4: Stop.** Tell the owner the branch is ready for the device check. Do not push. Do not open a PR.

---

## After PC-a

- **PC-b, contacts:** `ContactsDirectory`, access, link and unlink, the picture, the linked row, the launch check, suggestions, the contact rows and search in the sheet, "New · not in your contacts", and the re-run of a recording's guesses after access is given.
- **PC-c, merge:** the button, the confirm, Undo, then the drag.
- **PC-d, extractor handles:** `person_handle` is written, and the group becomes the handle.
- **Flagged for the owner:** plan decision 8. A name no memory carries still uses the old card with its four choices in this PR.
