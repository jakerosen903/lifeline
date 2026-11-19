# People and contacts: one person, one contact, and every guess in view

Status: approved by the owner on 2026-11-18, with the calls in "Calls the builder made" as written. The owner can still overrule each call. Plan for the first PR: `docs/plans/2026-11-18-people-contacts.md`.

Mock-ups: `docs/design/PC1_Assumed.dc.html`, `PC2_WhoIsThis.dc.html`, `PC3_PersonLinked.dc.html` and `PC4_NoContact.dc.html`. The canvas: https://claude.ai/artifact/6vReaCCBrkFqzSkMk6JfRN, bottom row "People and contacts". The wording on the screens is the designer's draft. The owner writes the final copy.

Sample names in this spec are invented.

## Problem

On first real use the owner told a story about a roommate. The app filed the story under a different friend with the same spoken name. Nothing showed that the app had guessed. No control changed the person.

The first spec deferred the contact link: "`contact_identifier` is deferred; no Contacts framework in V1" (`docs/specs/2026-10-21-v1-listening-app-design.md`, data model). So a person in the app is only a spoken name, and two real people with one name cannot be told apart.

## How a spoken name is matched today

This is the behaviour on `main` on 2026-11-18. File paths are under `ios/LifelineKit/Sources/LifelineKit/`.

1. **The rule.** `PeopleRepository.findPerson(matching:)` (`Store/PeopleRepository.swift`) returns a person when the spoken text equals the person's name or one of their aliases. It ignores case and outer whitespace. It never ignores spelling. A phrase with a comma ("my mom, Marcel") is tried whole, then each part. It never returns the owner.
2. **Two people with one name.** The query ends with `limit 1` and has no order. When two people hold the same name or alias, the database picks one. No rule chooses.
3. **Where the rule runs with no question.**
   - `ExtractionQueue`: a person name that `findPerson` knows is filed as a known mention. No card shows.
   - `CandidateActions.edges(of:)`: on Keep, each name in the memory's `people_refs` that `findPerson` knows becomes a link at once.
   - `CandidateActions.resolveIfKnown(_:)`: a waiting mention whose name is now known is answered by the app.
   - `CandidateActions.aboutEntity`: a fact about a named person links to the person `findPerson` returns.
   - `MergeActions.people(named:)`: the people of a telling are found by name when a telling is separated.
4. **Guesses make more guesses.** `PeopleRepository.resolve(_:to:)` saves the mention's text and its relation phrase ("my roommate") as aliases. `edges(of:)` saves the role half of "my mom, Marcel" as an alias. So one wrong link teaches the app a wrong name.
5. **One answer goes everywhere.** `CandidateActions.resolveMention` applies the owner's answer to every waiting mention with the same text, in every recording.
6. **A name the app does not know.** It becomes a `mention` row with status `unresolved`. The app shows a "Who's this?" card (`ios/Lifeline/Screens/Cards/WhoIsThisCard.swift`) and a "Check this: {name}?" tag (`Confirmation/CheckThis.swift`). The card offers the three closest known people (`PersonMatcher`), "Someone else", "Someone new" and "Not a person".
7. **How a link is stored.** A link is one row in `moment_entity` (`memory_id`, `entity_id`, `relation`, `role_text`). `relation` is `mention` for a moment and `detail` for a fact, feeling or goal. `role_text` holds the spoken words. No column records who made the link or whether it was a guess.
8. **How a link moves today.** The Change sheet removes a person from a memory (`unlinkPerson`) and adds another (`linkPerson`, `linkNewPerson`). `EntityRepository.merge` joins two places or two things; it refuses a person, and it refuses when the side that would go has photos. `moveDetail` moves a detail. No action moves one name from one person to another. No action merges two people.
9. **What leaves the phone.** The context packet (`Extraction/ContextPacket.swift`) sends each known person's id, name and aliases to the model, so the extractor can use them.
10. **What the extractor says about a person.** A memory names its people as plain text (`people_refs: [String]`). The prompt asks for a `mentions` entry only for a name that is not in the packet. The packet holds at most 50 people, so a known person can still arrive as a mention, and `ExtractionQueue` files it as known. A mention has an optional `likely_alias_of_person_id`. So two people with one name in one recording are the same string in the data.

## Goals

1. A person maps to at most one contact, and a contact maps to at most one person.
2. A person needs no contact. The app works with full, limited or no contacts access.
3. The app may assume who a name means. Each assumption is visible and one tap changes it (principle 5).
4. A link to a contact gives the person the contact's picture as their first picture. The owner can change it.
5. A wrong guess must not teach the app a wrong name.

## Non-goals

- Fixing misheard words in the transcript.
- The photo card and key photo work (branches `photo-story` and `photo-card`). This spec uses its words and its key photo rule and changes neither.
- Writing to the owner's contacts. The app only reads.
- Reading any contact field other than the name, the nickname and the picture.
- Matching faces in photos to people.
- Family sharing.

## Anti-goals

- A queue of names to confirm. A mark states a guess and asks for nothing (principle 9).
- A People grid filled with contacts that are in no story.
- A contact's data in the text that goes to the model.

## Terms

- **Said name:** the words the owner used for someone in a moment ("Robin", "my roommate").
- **Link:** one `moment_entity` row that joins a memory to a person.
- **Origin:** who made a link and on what basis. See "Origin of a link".
- **Guess:** a link with origin `assumed`.
- **Settle:** the owner confirms or changes a guess. A settled link has origin `confirmed`.
- **Mark:** the dashed ochre outline with the word "Assumed". Ochre always comes with a word.
- **Group:** the links in one recording that the app treats as one person for a said name.
- **Linked person:** a person with a contact.
- **Sheet:** the "Who is this?" sheet (PC2).

## Approaches considered

### How a person relates to a contact

- **A. A person is the app's own record with an optional contact (chosen).** The `person` row gains a nullable contact identifier. Stories, names and photos belong to the person. The contact adds a full name and a picture. It works with no access. It is additive.
- **B. Every person is a contact.** The app creates a contact for each unknown name. Rejected: it writes to the owner's contacts, it fails with no access, and a great-grandmother needs no phone number.
- **C. Copy all contacts into the app as people.** Rejected: it copies the address book into the database, it fills People with persons who are in no story (principle 9), and limited access shows only some contacts.

### Where a guess is recorded

- **A. An origin column on the link row (chosen).** The claim "this moment is about this person" is the link, so the basis of the claim sits on the link. One column, no new table.
- **B. A separate table of guesses.** Rejected: two rows must agree for each link, and a kill between two writes leaves them apart.
- **C. The `mention` table.** Rejected: a mention belongs to a segment, not to a memory. One segment can hold several memories.

### Who tells two people with one name apart

- **A. The app, by name only.** Simple. It cannot separate two people with one name in one recording.
- **B. The extractor gives each person in a recording a handle (chosen, as step 2).** The extractor reads the story, so it can see "Robin, my roommate" and "Robin from college" as two people. The app still decides who each handle is. Cost: a new prompt version and its test stories.

The work ships as step 1 (A, with marks, the sheet and contacts) and then step 2 (B replaces the grouping by name).

## Origin of a link

A person link has one origin.

| Origin | Meaning | Mark |
| --- | --- | --- |
| `assumed` | The app chose the person from the name. | Yes |
| `said` | The owner's own words in the story point to one person: a said name together with a relation phrase, where exactly one person holds both as aliases. | No |
| `new` | The app made a new person for a said name that fits no one (rules 6 and 7). It is not a guess about who the person is. | No. The line reads "New". |
| `confirmed` | The owner chose or confirmed the person: the sheet, "Yes, this Robyn", the Change sheet, a typed name. | No |
| none | The link is older than this feature. Its basis is not known. | No |

A memory has at most one link to a person, as today: the key of `moment_entity` stays (`memory_id`, `entity_id`, `relation`). When a memory names one person twice ("Robin" and "my roommate"), the one link keeps the first said name and the strongest origin, in the order `confirmed`, `said`, `assumed`, `new`.

Rules:

1. Keep on a memory card must not weaken an origin: the stronger origin wins, and no origin is the weakest. Keeping a moment does not settle a guess. (narrowed 2026-11-18, ruling R13)
2. The app must save an alias only from a link with origin `said` or `confirmed`. A guess teaches no name. A person made by rule 6 or 7 has the said name as their own name.
5. Aliases saved before this feature count as the owner's. The app cannot tell which of them came from a wrong guess. The owner removes a wrong one on the person's page, as today.
3. A relation phrase said with a guess ("my roommate Robin") is saved as an alias only when the owner settles the guess.
4. Only the owner's action changes `assumed` to `confirmed`.

## Matching a said name

Matching is a pure function, `PersonGuess`, in LifelineKit. Its input is the said name, the relation phrase when one was said, the people on file with their aliases, and the contacts the app can see. Its output is one choice and the list of other candidates in order. It writes nothing.

### Candidates

- **A person on file** is a candidate when the said name, or one comma part of it, equals the person's name or an alias. The comparison ignores case, outer whitespace and diacritics. The owner is never a candidate.
- **A contact** is a candidate when the said name equals the contact's full name, given name or nickname, by the same comparison. A contact that is linked to a person is not a second candidate: it counts as that person.

### The choice

The rules run in order. The first rule that applies decides.

1. **The owner's words point to one person.** The said name and the said relation phrase are both held by exactly one person. The link has origin `said`. No mark. Example: "Danielle, my sister" goes to the Danielle whose aliases hold "my sister", not to another Danielle.
2. **A relation phrase alone names one person.** "My mom" is an alias of exactly one person. Origin `said`. No mark. A group phrase ("our parents") keeps today's rule and is never one person.
3. **A fuller name fits one candidate only.** The said name has two or more words and equals one candidate's full name. The app assumes that candidate. When the candidate is a contact, the app creates a person linked to it, as in rule 5. Origin `assumed`.
4. **A person on file fits.** The app assumes the person on file, not a contact that also fits. With two or more persons on file, the app assumes the one most recently linked to a kept memory. Origin `assumed`.
5. **Exactly one contact fits and no person does.** The app creates a person linked to that contact and assumes it. The mark reads "Assumed · new, from your contacts". Origin `assumed`.
6. **Two or more contacts fit and no person does.** The app creates a person with the said name and no contact. The line reads "New · not linked yet". The sheet lists the contacts. Origin `new`.
7. **Nothing fits.** The app creates a person with the said name. The line reads "New · not in your contacts". When the app cannot see contacts, the line reads "New". (narrowed 2026-11-19, PC-b plan decision 5) This is not a guess about who the person is, so the outline is solid. Origin `new`.

Every person chip opens the sheet, with or without a mark. A wrong link with no mark is still one tap from the repair.

### When the guess is made

- **Before Keep.** A card that waits shows its chips from `PersonGuess`. Nothing is written: no person, no link. The chip shows what Keep will do.
- **A choice before Keep.** When the owner uses the sheet on a card that waits, the app stores the choice with the card (table `candidate_person_choice`). Keep applies it with origin `confirmed`.
- **On Keep.** The app runs `PersonGuess` for each said name of that card, creates the persons that rules 3 and 5 to 7 call for, and writes the links with their origins, in the same transaction as the memory.
- **A name no memory carries.** A person the story names with no moment or detail about them gets no Keep. It keeps today's card, and the card opens the sheet. No person exists until the owner answers.
- **Access given after a guess.** When the owner allows contacts on the landing, the app runs `PersonGuess` once more for the links of that recording whose origin is `new` and whose person the app made and nobody edited. A link with origin `assumed` does not change. The app does not link a contact that the owner declined for that person. It runs for no other recording. (Narrowed 2026-11-18, PC-b plan decision 7.)

### What changes from today

- The app creates the person on Keep (rules 5 to 7). A name the app does not know no longer waits as a "Who's this?" card. The sheet replaces the card for new recordings.
- The `limit 1` with no order goes. Rule 4 chooses, and the choice is marked.
- `resolveIfKnown` and the copy of one answer to every recording go. An answer carries inside one recording only. See "Settling a guess".
- Mentions that are `unresolved` when this ships keep their "Who's this?" card and their "Check this" tag until the owner answers them.
- A group phrase ("our parents") is unchanged: it still writes a mention and keeps its own card.

## Where the mark shows

1. **The card after a story and the landing (PC1).** Each person chip shows the person's name and one line: "Assumed · you said “Robin”", "Assumed · new, from your contacts", "New · not in your contacts". The landing's sub-line states the count: "I made two guesses about who you meant."
2. **The memory page.** The same chips.
3. **The person's page (PC3).** A moment that is here by a guess has the mark, "Yes, this {name}" and "Someone else…".
4. **Not on a Timeline row and not on a People tile.** A Timeline row shows no people. A count of open guesses on a tile would be a queue.

A page that shows a choice must be as plain as the sheet that made it. PC3 must not carry more controls for each moment than PC2 has options.

## Settling a guess

### The sheet (PC2)

The sheet opens from a person chip. It shows:

1. The title "Who is “{said name}” here?" and the quote.
2. The current choice first, selected, with its line ("In 12 of your stories · my guess").
3. Each other candidate: a person on file ("In 3 of your stories") or a contact ("In your contacts · not in a story yet").
4. "Someone new": a new person with the said name and no contact.
5. "Search your contacts". See "Contacts".
6. "Not a person": the link goes and the name stays in the quote. A quiet row, as on today's card.
7. The checkbox "Also change the {n} other moments from this recording". It shows only when the group has other links. It is on by default.
8. "Done", and the line "Nothing is deleted. You can change this again at any time."

"Done" settles the link, also when the owner kept the app's choice. The sheet has no separate "confirm" control.

### How far one answer carries

- An answer applies to the tapped link. With the checkbox on, it applies to every link in the group.
- **Step 1:** the group is the links in the same recording with the same said name, by the comparison in "Candidates".
- **Step 2:** the group is the links in the same recording with the same extractor handle.
- An answer never carries to another recording. A said name in a later recording is a new guess.

### "Yes, this Robyn" and "Someone else…" (PC3)

"Yes, this {name}" settles that one link. "Someone else…" opens the sheet for that link.

## Moving a name to another person

When the owner changes the person, the app must do all of this in one transaction:

1. **The link moves.** The row for the old person goes. A row for the new person is written with the same `role_text` and origin `confirmed`. When the new person already has a link to that memory, that link stays and its origin becomes `confirmed`.
2. **Details move with it.** A fact, feeling or goal of the same recording that is a detail of the old person, and whose card names the same said name or handle, becomes a detail of the new person. A detail the owner placed by hand does not move.
3. **Photos do not move.** A photo belongs to a person's page or to a memory. It does not belong to a link.
4. **The first telling follows.** When the old person's first telling came from a moved moment, the old person takes the first telling of their oldest remaining moment. The new person takes one only when they have none.
5. **Names.** The said name and its relation phrase become aliases of the new person. The old person keeps their aliases; the owner removes one on that person's page, as today.
6. **An empty guess goes.** When the old person was created by the app for this said name, and now has no moment, no detail, no photo, no contact the owner linked and no name the owner gave, the app removes that person. A person the app made from a contact on Keep, and nobody settled, goes too. The picture the app copied from that contact does not keep them. (narrowed 2026-11-19, PC-b rulings PB2 and PB12) Undo brings them back. A person the owner edited stays: a typed name, stated dates, hidden, or kept from the AI (R39).
7. **Undo.** The one message slot shows "Changed to {name}." with Undo for 6 seconds. Undo restores every row as it was. Undo is refused when a moved link changed in the meantime, as `unmerge` does today.

A kill in the middle must leave either the old state or the new state.

## Merging two people

Two entries can be one real person: "Robin" and "Robyn Vale".

1. **Drag.** On the People grid, the owner drags one face onto another. The two tiles pull together into one.
2. **A button.** A person's page has "Same as another person…" with a picker. VoiceOver and Switch Control use this path.
3. **Confirm.** Both paths ask "Same person?" with both names and both pictures before anything changes. The person dropped onto is the one that stays.
4. **Conflicts.** `EntityRepository.merge` refuses people today, so this is a new merge. Where both persons have a value (notes, birth date, the detail line, stated dates, the hidden and excluded flags), the staying person's value is kept. The other value is kept in the receipt for Undo and is not shown after it. Mentions that point at the other person point at the staying one. Declined contact suggestions of both are kept.
5. **What joins.** The person that stays takes every moment, detail, alias and photo of the other. Each link keeps its origin. The person that stays keeps their name. The photos keep one order: the staying person's photos first, with their key photo at the front, then the other person's.
6. **Contacts.** When only one of the two has a contact, the result has it. When both have a contact and the contacts differ, the app must not merge. It says that they are linked to two different contacts.
7. **Undo.** "Merged into {name}." with Undo for 6 seconds, in the one message slot. The receipt holds both persons as they were.
8. **The forced case.** When the owner links a person to a contact that another person holds, the app asks "Same person?" for those two. The link is made only when the owner merges them. Until the merge exists (PC-c), the app refuses the link and says who holds the contact. (narrowed 2026-11-19, PC-b plan decision 4)

The motion is tuned on the device. This spec fixes the behaviour only.

## Contacts

### Access

- The design assumes the owner gives access. With limited or no access, the app still works with fewer suggestions.
- The app asks once. It asks when the first kept moment names a person, on the landing of that recording. The landing must be quiet: the recording was not heavy, no serious disclosure showed and sorting is done. Otherwise the prompt waits for the next landing that qualifies. (narrowed 2026-11-19, PC-b rulings PB36 and PB38) It also asks when the owner taps "Link to a contact" or "Search your contacts" before that.
- The system prompt shows the usage string. Draft: "Lifeline matches the names in your stories to your contacts. It reads names and pictures only, and they stay on this phone."
- The app must not ask at first launch. A prompt before the first story has no reason the owner can see.

| Status | What the app does |
| --- | --- |
| Full | Matches against all contacts. |
| Limited | Matches against the contacts the owner shared. The sheet's search shows Apple's `ContactAccessButton` beside the result list, so one tap shares one more contact. |
| Not asked | Matches against people on file only. The first need shows the prompt. |
| Denied or restricted | Matches against people on file only. Every guess is still marked. A person's page shows the card from PC4 with "Allow contacts in Settings". The app does not ask again. |

### What the app reads and keeps

- The app reads the name fields, the nickname and the picture. It must request no other key.
- For a linked person the app keeps the contact's identifier and the contact's full name at the time of the link.
- The app keeps no copy of any other contact. It reads the contacts it can see into memory for matching and drops them.
- **Nothing from a contact goes to the model.** The context packet sends only names the owner said or typed. A contact's name is never saved as an alias, so every alias is the owner's words. For a person whose name came from a contact (`name_origin` is `contact`), the packet's `name` is the oldest alias and the rest are its aliases. A test reads the packet and fails on any contact name. The usage string and the "About the app" line stay true.

### The identifier

- The app stores `CNContact.identifier` of the unified contact. Apple documents it as stable between launches and unique on the current device only.
- The identifier is not valid on another phone. After a restore on a new phone, the identifier does not resolve.
- When an identifier does not resolve, the app looks for a contact whose full name equals the kept name. With exactly one, the app links to it again. With none or several, the person shows the "contact not found" state.

### Linking and unlinking

- A link is made by rule 5, by a contact row in the sheet, by "Link to a contact" (PC4), or by "Yes, link them" on a suggestion.
- "Change" on the linked row (PC3) offers another contact or "Unlink". Unlink removes the identifier and the kept name. The person, their moments, their name and their pictures stay.
- One contact, one person: see "Merging two people", point 8.

### The person's name

- A person created from a contact (rule 5) takes the contact's full name as their name. The said name is kept as an alias.
- A person on file who is linked later keeps their name. The linked row shows the contact's name. The owner can rename the person, as today.
- A name the owner typed or said is never replaced by a contact's name.
- The app records where the name came from: `said`, `typed` or `contact`.

### The picture

- On a link, the app reads the contact's picture and stores a copy through `PhotoLibrary`, as it stores any photo. The stored copy follows the S4 rules: a JPEG of at most 2048 pixels with no metadata.
- The first photo on a person is the key photo. So the contact's picture is the key photo only when the person has no photo. A person with photos gets the contact's picture as one more photo, after the others.
- The owner changes the key photo and adds photos by the rules of the photo card and key photo spec (branch `photo-card`, `docs/specs/2026-11-18-photo-card-key-photo.md`): "Make this the key photo", or a drag of a photo to the front. Until that branch merges, the control reads "Make this the cover". The code names (`PhotoRole.cover`, `setCover`) stay.
- A contact with no picture adds nothing.
- `PhotoLibrary.add` reuses a stored photo with the same bytes. When the contact's picture is already one of the owner's photos, the app links that photo and does not record it as the contact's copy. The app replaces or removes only a photo it recorded as the contact's copy.
- Unlink keeps the picture. The owner removes it as any photo.

### A contact that changes

The app checks the linked contacts at launch and when the system posts `CNContactStoreDidChange`. The notice arrives only while the app runs, so the launch check is required. The check fetches only the linked identifiers.

- **Renamed.** The kept name is updated. The person's name changes only when it came from the contact and the owner has not renamed the person.
- **New picture.** When the person's key photo is still the copy the app took from the contact, the app replaces it with the new picture. In every other case the app does nothing.
- **Deleted, or no longer shared.** The app cannot tell these apart under limited access. The person keeps everything, including the picture. The linked row reads "This contact is not in your contacts now" with "Link to a contact" and "Unlink". Under full access the app tries the name match from "The identifier" first. Under limited access the app does not try it, because a card with that name can be a namesake. (narrowed 2026-11-19, PC-b ruling PB34)

### A contact that appears later (PC4)

At the same check, for each person with no contact, the app looks for contacts whose name equals the person's name or an alias. With exactly one that is not linked and not declined, the person's page shows "{contact name} is in your contacts. Is this the same person?" with "Yes, link them" and "No, someone else". "No" is kept, and the app does not offer that contact for that person again. The suggestion shows on the person's page only. No badge and no count shows elsewhere.

## Step 2: the extractor tells people apart

- The extractor returns, for each recording, the people it found. Each has a handle, the said name, the relation phrase when one was said, and the id of a person from the packet only when the story's own words point to that person.
- A memory names its people by handle, not by text.
- The packet carries the handles of the earlier segments of the same recording, so a handle holds across segments.
- The person id replaces today's `likely_alias_of_person_id` on a mention.
- The app treats the handle as the group. The app treats the person id as one more input to `PersonGuess`: it decides the choice in rule 4, and the link is still `assumed`.
- Two handles with one said name become two guesses. The second is never assumed to be the first. It takes the next candidate in order. With no other candidate it is a new person (rule 7).
- Two handles that the owner settles to one person in one memory share that memory's one link.
- The extractor can be wrong in both directions. "Someone else…" and merge repair it.
- This is a new prompt version. It needs test stories: two people with one name in one recording, one person under two names, a name with no other words, and a known name with a new relation phrase.

Step 2 changes no screen. It gets its own plan after step 1 ships.

## Data model

Migration v15 is additive. The phone's database is the only copy, so the migration drops nothing and rewrites no row. The migration is named `v15`, not `v14`: the photo story registered `v14` first, and GRDB records a migration by name (R36).

`person`, new columns, all nullable:

| Column | Holds |
| --- | --- |
| `contact_identifier` | The unified contact's identifier. A unique index where it is not null gives one contact to one person. |
| `contact_name` | The contact's full name at the last check. |
| `contact_state` | `linked` or `missing`. Null with no contact. |
| `contact_photo_id` | The photo the app copied from the contact, when one exists. References `photo`, set null on delete. |
| `name_origin` | `said`, `typed` or `contact`. Null for a person older than v15. |
| `created_by_guess` | True when the app created the person on Keep and the owner has not acted on them. |

`moment_entity`, new columns, nullable:

| Column | Holds |
| --- | --- |
| `origin` | `assumed`, `said`, `confirmed` or `new`. Null for an older link and for a link to a place, thing or idea. |
| `person_handle` | The extractor's handle. Added in v15 and written from step 2. |

New table `contact_declined` (`person_id`, `contact_identifier`, primary key on both, cascade on the person).

New table `candidate_person_choice` (`candidate_id`, `said_name`, `person_id` nullable, `choice`: `person`, `contact`, `new` or `not_a_person`, `contact_identifier` nullable; cascade on the candidate).

- No existing row changes. An older link has no origin and shows no mark.
- The backup file carries the new columns. `contact_identifier` in a backup is valid only on the phone that made it; "The identifier" covers a restore.
- `mention` stays. A new recording writes a mention only for a group phrase and for a name no memory carries.

## Structure in the code

- `PersonGuess` (kit, pure): the matching rules. Tests cover every rule.
- `ContactsDirectory` (kit, a protocol): status, the contacts for matching, a fetch by identifiers, a picture by identifier. The app target has the `CNContactStore` implementation. Tests and UI tests use a scripted one. Contact fetches run off the main thread.
- `PersonLinkActions` (kit): settle, move with a receipt, undo.
- `ContactLinkActions` (kit): link, unlink, the check at launch, suggestions.
- `PersonMergeActions` (kit): merge two people with a receipt, undo.
- `PeopleRepository.findPerson` stays for a name the owner types. No extraction path calls it.
- `WhoIsThisSheet` replaces `WhoIsThisCard` for new recordings.

## Edge cases

- **Two contacts with one full name.** Rule 6: no contact is chosen. The sheet lists both with their pictures.
- **A said name that is the owner's name.** Unchanged: the owner is never a candidate on the extraction path.
- **A one-word said name that is a common word** ("Will", "Faith"). The extractor decides what is a person. "Not a person" in the sheet is the repair.
- **A relation phrase held by two people** ("my roommate" for two roommates in different years). Rule 2 does not apply. The app assumes the one most recently linked, with the mark.
- **The owner settles a guess, then merges that person.** The link keeps origin `confirmed`.
- **Access changes from full to denied in Settings.** iOS ends the app. At the next launch, linked persons show "contact not found" with the Settings link. Nothing is unlinked.
- **Access changes from limited to full.** The launch check finds more candidates. Old guesses do not change. Suggestions can appear on persons' pages.
- **A contact is linked, then the same contact unifies with another card.** The app fetches by the stored identifier and stores the identifier the system returns.
- **A kill between the contact picture's file and its row.** The S4 sweep removes the file. The next launch check copies the picture again when the person has no `contact_photo_id`.
- **A kill in the middle of a move or a merge.** One transaction: the old state or the new state.
- **Undo after the 6 seconds.** The sheet is the way back. A merge has no way back after its Undo; the confirm step says so.
- **A person hidden from the timeline or excluded from AI.** Matching still sees them, so a hidden person is not made a second time. The chip follows today's rules for a hidden entity.
- **A recording is deleted.** Its links go by cascade. A person the app created for it, with nothing else, is removed by the rule in "Moving a name", point 6.
- **Hundreds of contacts.** Matching reads the contacts' names once for each recording and keeps them in memory while that recording's cards wait. The read is off the main thread. Pictures are read only for a link.
- **The largest text sizes.** The chip's two lines wrap. The sheet scrolls.
- **VoiceOver.** A marked chip reads "{name}, assumed, you said {said name}. Change who this is." Drag to merge has the button path.

## Test plan

Unit tests in LifelineKit (`swift test`):

- `PersonGuess`: one test for each of the seven rules; two persons with one name; a person and a contact with one name; a fuller name that fits only the contact; a known name with a new relation phrase; a group phrase; the owner's name; diacritics and case.
- Origin: Keep does not weaken an origin (narrowed 2026-11-18, ruling R13); an alias is saved from `said` and `confirmed` and never from `assumed`; a relation phrase is saved only on settle.
- Settle: one link; the group with the checkbox on; nothing in another recording changes.
- Move: the link, the details, the first telling, the aliases, the removed empty person, Undo, a refused stale Undo.
- Merge: links, aliases, the photo order and the key photo; two different contacts refuse; Undo.
- Contacts with a scripted directory: link, unlink, the unique contact, rename, new picture when the key photo is the contact's copy and when it is the owner's choice, missing, re-link by name with one match and with two, a declined suggestion that does not return.
- Each status: full, limited, not asked, denied.
- Migration v15 on a copy of a v13 database: every row is kept, old links have no origin, the backup round-trips.
- The context packet holds no name with origin `contact`.

UI tests with a scripted directory: the marked chip on the landing; the sheet changes a person and Undo restores it; "Yes, this Robyn" clears a mark; the linked row; the suggestion card; the no-access card; merge by the button.

Device checks, in a checklist beside the plan:

- The system prompt and its text. The two-step iOS prompt for limited access.
- `ContactAccessButton` in the sheet's search under limited access. It grants nothing when it is clipped or covered.
- How the system's contact search treats nicknames and part names. Apple's documentation does not say.
- The identifier after a restore from a backup on the same phone. Apple's documentation does not say.
- The size of a contact's picture.
- Drag to merge and its motion, also at the largest text size.

## Principles

- **1, the person is the author.** A name the owner said or typed is never replaced. A relation phrase is saved only from the owner's words.
- **5, uncertainty is shown.** Every guess has the mark and the word "Assumed". Keep does not settle it. Ochre comes with a word, never with reduced opacity.
- **9, never a database to maintain.** No queue of guesses, no count on a tile, no person without a story. A person needs no contact.
- **Data posture.** Contacts stay on the phone. Nothing from a contact goes to the model.

## Suggested PRs

| PR | What | Needs |
| --- | --- | --- |
| PC-a | Migration v15, origin, `PersonGuess` against people on file, the marks, the sheet with no contact rows, move with Undo. This alone fixes the reported bug. | — |
| PC-b | `ContactsDirectory`, access, link and unlink, the picture, the linked row, the check at launch, suggestions, the contact rows and search in the sheet. | PC-a |
| PC-c | Merge: the button, the confirm, Undo, then the drag. | PC-a |
| PC-d | Step 2: extractor handles. Its own plan. | PC-a |

On approval, `docs/DECISIONS.md` gets an entry, `docs/OVERVIEW.md` gets the new matching rules, and the first spec's line about `contact_identifier` gets a pointer to this spec.

## Calls the builder made

The owner said these on 2026-11-18, and they are not in this list: a person is backed by a contact; a person needs no contact; the contact's picture is the first picture; a guess is visible and easy to change; the four screens; the design assumes contacts access and stays usable with none; words said with a name ("Danielle, my sister") settle who it is.

The owner approved the spec with these calls on 2026-11-18. No call was discussed one by one, so each stays open to an overrule.

**Read from the owner's messages, which may have been meant for another session:**

1. **Every guess from a name alone is marked** (rules 3 to 5), because the name can be a new person. The other option: mark only when more than one candidate fits.
2. **Drag to merge two people**, with a button path, a confirm and Undo. The owner's message said "two things". This spec covers people only; the owner must say whether places and things merge the same way.
3. **The extractor gives each person in a recording a handle** (step 2).

**Not yet asked:**

20. **Names the app saved before this feature count as the owner's words**, so "Danielle, my sister" trusts an old alias. A wrong old alias stays until the owner removes it.
21. **In a merge, the staying person's value wins** where both have one (notes, birth date, detail line, dates, hidden and excluded).
22. **A choice made in the sheet before Keep is stored with the card** and applied on Keep.

4. **A person on file wins over a contact with the same name** (rule 4), and the guess is marked. The app does not ask "which one?".
5. **An answer carries inside one recording only.** Today's copy of one answer to every recording goes.
6. **Older links get no mark until a retelling or a merge reaches them. Then they take the guess's origin, and show the mark when that is `assumed`.** (narrowed 2026-11-18, ruling R13) The app cannot know which older links were guesses. The other option marks every older link that came from a name, which puts a mark on most of the archive.
7. **The app creates a person on Keep for a name it does not know.** The "Who's this?" card goes for new recordings. Cost: a misheard name becomes a person until the owner taps "Not a person" or merges it.
8. **A person the app created for a guess is removed when a move leaves them empty.** Undo restores them.
9. **A person created from a contact takes the contact's full name. A person on file keeps their name when linked later.**
10. **A contact's name never goes to the model.** The packet sends the said names for that person. Cost: the extractor does not see "Robyn Vale" for a person the owner calls "Robin".
11. **The app asks for contacts on the landing of the first recording that names a person**, not at first launch.
12. **After a restore, the app links again by an exact, single name match** without a question.
13. **A new contact picture replaces the key photo only while the key photo is the app's copy of the old one.**
14. **A missing contact unlinks nothing.** The person shows "not in your contacts now".
15. **The mark does not show on Timeline rows or People tiles.**
16. **"Done" on the sheet settles the link**, also when the owner kept the app's choice.
17. **Two persons linked to two different contacts cannot be merged.**
18. **Four PRs, with the extractor change last and under its own plan.**
19. **The usage string and every line of copy in this spec are drafts.**
