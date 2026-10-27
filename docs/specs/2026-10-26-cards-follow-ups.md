# Cards: follow-ups stay on the memory card

Status: in progress, 2026-10-26. Implements the owner's decision "Follow-ups stay on the memory card" (`docs/DECISIONS.md`) and audit finding F1 (`docs/specs/2026-10-26-ui-audit.md`). PR 1 of the audit's ship order.

## Problem

After Keep, follow-up cards arrive as separate cards: "Sounds like it belongs to: “family”", "Sounds like a story", "Sounds like a thing you had", "Who's this?". Nothing on such a card names the memory it came from. In a live session several cards are on screen, so the person cannot tell which memory a follow-up is about. The owner reports that the cards read as random (PRINCIPLES 9).

## Terms

- **Follow-up:** a hint (domain, story, collection, chapter), an entity mention (thing, place, idea) or a person mention ("Who's this?") that the extractor emitted with a memory.
- **Owner memory:** the memory candidate that a follow-up belongs to.
- **Kept card:** the memory card after Keep, while it still has follow-ups to show.

## Design

### Which memory owns a follow-up

1. A hint belongs to the memory named by its `memory_candidate_id`.
2. An entity mention belongs to the first memory candidate from the same segment that refers to it. A memory refers to a mention when one of these is true:
   - the memory's `about_ref` equals the mention's `ref`;
   - one of the memory's entity refs (`entityRefs`, including the place from `placeText`) has the same normalized text and the same kind.
3. A person mention belongs to the first memory candidate from the same segment whose `about_ref` equals the mention's `ref`, or whose `peopleRefs` contain the mention's text (normalized).
4. "Normalized" means `PeopleRepository.normalize`.
5. "First" means the lowest `ordinal`. When that memory is dismissed, the follow-up moves to the next memory that refers to it. When no memory in the segment refers to a follow-up, it has no owner memory.
6. These rules must live in LifelineKit as pure code with unit tests.

### The live session

1. A follow-up is never a card of its own. The queue holds each follow-up under its owner memory until that memory is kept.
2. When the person taps Keep on a memory card that has follow-ups, the card does not leave. It becomes a kept card:
   - a top line "Kept" with a checkmark;
   - the memory's title, one line;
   - one chip per follow-up, in the order the extractor emitted them;
   - a "Done" button.
3. A memory card with no follow-ups leaves on Keep, as it does now.
4. Chip labels:

   | Follow-up | Chip |
   |---|---|
   | Domain hint "family" | "Family?" (first letter in capitals) |
   | Story hint "the steak dinner" | "Story: the steak dinner?" |
   | Collection hint | "Collection: {phrase}?" |
   | Chapter hint | "Chapter: {phrase}?" |
   | Thing | "{text}: a thing?" |
   | Place | "{text}: a place?" |
   | Idea | "{idea title or text}: something you think?" |
   | Person | "{text}: who's this?" |

5. One tap on a hint, thing, place or idea chip accepts it, as "Yes" or "Keep" on the old card did. The chip then shows a checkmark and the plain text without the question mark ("✓ Family", "✓ the shed"). It stays on the kept card. The session never leaves the session screen for an entity page.
6. A thing, place or idea chip has a context menu with the other types and "Not any of these", as "Not quite" on the old entity card had.
7. A person chip opens a sheet with the "Who's this?" choices of the old card. A choice closes the sheet and checks the chip.
8. A checked entity or person chip opens that entity's page when tapped again, outside the live session only (session detail, timeline).
9. "Done" closes the kept card:
   - unanswered hint and entity follow-ups are dismissed, as "Not quite" did;
   - an unanswered person follow-up becomes an open mention, so it waits in the People queue, as an unanswered "Who's this?" card did.
10. When every chip is answered, the kept card closes by itself after 1.5 s.
11. When the person keeps, dismisses or merges ("Same story") another memory card, every open kept card closes as if "Done" was tapped. At most one kept card is open.
12. Dismiss on a memory card hides its follow-ups with it. Undo brings the memory card back with its follow-ups still held.
13. A follow-up with no owner memory never shows in the session. It stays pending in the store.
14. After a heavy moment, kept cards show no chips: the card leaves on Keep as if it had no follow-ups. The follow-ups stay pending (the existing suppression rule).

### Session detail and the timeline

1. The cards waiting after a session follow the same rules. A pending memory card keeps its follow-ups and becomes a kept card on Keep.
2. Pending follow-ups whose owner memory was already accepted (for example, the app was closed before the person answered) show as one kept card for that memory: "Kept" and the memory's title, then the chips. They never show as separate cards.
3. Pending follow-ups whose owner memory was dismissed, or that have no owner memory, do not show.

### The People screen

The People queue is unchanged. It lists open mentions, which are about people, so a "Who's this?" card there needs no memory.

### Accessibility and identifiers

1. Kept card: `card.kept`. Chip: `card.followUp`, with the chip text as its label. Done: `card.keptDone`.
2. The identifiers `card.hint`, `card.hintYes`, `card.hintNo`, `card.entity`, `card.entityKeep`, `card.entityNotQuite` and `card.entityNotAny` are no longer on the session, session detail or timeline screens. `HintCard` and `EntityCard` are deleted if nothing else uses them.
3. A chip is a button. VoiceOver reads its text; a checked chip reads "{text}, done".

## The two failing entity UI tests

`EntitiesUITests.testEntityPagesShowDetailsAboveMomentsAndIdeasInOrder` and `EntitiesUITests.testThingsFilterByDomainTag` fail on `main`:

- the first finds 1 moment on an idea page where it expects 2;
- the second cannot find `entities.tagFilter`.

The cause must be found before any fix (systematic debugging). When the cause is in the app, the app is fixed. When the test is out of date, the test is fixed and the PR body says why. Both tests must also move from the old entity card to the chips.

## Edge cases

1. A follow-up arrives after its memory was kept (a later extraction event). It joins the open kept card for that memory. When that card is closed, the follow-up shows as a kept card of its own for that memory (rule 2 under Session detail).
2. A continuation re-emits a memory card with a changed payload. Its held follow-ups stay with it.
3. The same entity is referred to by two memories in one segment. It belongs to the first only. Accepting it once links it once; the extractor's links on the second memory are unchanged.
4. Keep fails (a store error). The memory card stays as a memory card and shows the error, as now. No chips show.

## Tests

1. LifelineKit unit tests for the ownership rules: hint by id, entity by `about_ref`, entity by entity ref text and kind, place from `placeText`, person by `peopleRefs`, first by ordinal, moving to the next memory after a dismiss, no owner.
2. LifelineKit unit tests for the queue: follow-ups never become cards; Keep exposes them; dismiss hides them and undo restores them; "Done" reports what to dismiss and what to open as a mention; a late follow-up joins its kept card; waiting cards group pending follow-ups under an accepted memory.
3. UI tests (fixture extractor): keep a memory, see its chips on the same card; accept a domain chip; accept a thing chip and stay on the session screen; "Done" closes the card; a person chip opens the "Who's this?" sheet.
4. The full UI suite passes, including both `EntitiesUITests`.

## Out of scope

- The timeline restructure, About and the entity pages (audit PRs 4 and 5).
- Pair cards ("Are these the same?") and "Same story" are unchanged.
