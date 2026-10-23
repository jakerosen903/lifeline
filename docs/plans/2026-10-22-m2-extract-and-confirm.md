# M2: Extract and Confirm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After each segment closes, the app sends it to the extractor, shows the candidates as cards under the transcript, and one tap turns a card into a memory with its people and place; unknown names become "Who's this?" cards; the `lifeline` CLI runs the same extractor over a database file.

**Architecture:** `LifelineKit` gains an `Extraction` module: an `ExtractionService` protocol, an `AnthropicExtractionService` that calls the Messages API over `URLSession` with structured output, a pure `ContextPacketBuilder`, a pure `OutputValidator` that rejects anything the owner did not say, and an `ExtractionQueue` actor that serializes requests per session and writes immutable `candidate` rows. A `Confirmation` module turns an accepted candidate into `memory`, `memory_span`, `memory_person`, `place`, `mention` and `anchor` rows. The app shows cards from a `CardQueue` fed by the queue; the key lives in the Keychain and is typed into Settings. The resolver (M3) is not built; anchors are stored unresolved and memories stay unplaced.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Swift Testing, XCUITest, GRDB.swift 7.11.1, `URLSession`, Security framework (Keychain), Anthropic Messages API (`claude-opus-5-5`, structured outputs, adaptive thinking at `effort: low`, `fallbacks: "default"`, prompt caching).

**Spec:** `docs/specs/2026-10-21-v1-listening-app-design.md` sections 3 (Session, People), 4, 6, 7, 9 (serious disclosure, pending cards), 10, 11 row M2. The M1 plan `docs/plans/2026-10-21-m1-record-transcribe-store.md` describes the code this plan extends. Read both first.

## Global Constraints

- Everything in M1's Global Constraints still holds (iOS 26, Swift 6 strict, app target holds only views, view models and the composition root; all logic in `LifelineKit`; fixtures invented; docs in ASD-STE100; never push).
- The app must talk to the model only through `ExtractionService`. No file outside `Sources/LifelineKit/Extraction/` may build a request to `api.anthropic.com`.
- Model call: model `claude-opus-5-5`, `output_config.effort: "low"`, `thinking` omitted (adaptive is the default on this model and cannot be disabled), structured output via `output_config.format` of type `json_schema`, `fallbacks: "default"` with header `anthropic-beta: server-side-fallback-2026-07-01`, `max_tokens: 4096`, one `cache_control: {"type": "ephemeral"}` on the last block of the fixed system prompt. Model name, effort and max tokens are fields of `ExtractorConfig`, not literals in the client.
- Headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`, plus the beta header above.
- Check `stop_reason` before reading `content`. `refusal` and `max_tokens` are failures that leave the segment `pending`; they are never parsed as output.
- Every field that carries content must be a span or a quote from the segment. `title` is the one composed field (max 8 words). The validator enforces this on device; the prompt asks for it.
- `(segment_id, extractor_version)` is unique. `candidate` rows are immutable: status changes only.
- Nothing in `memory`, `person`, `place` or `mention` may contain text the owner did not say or type, except `memory.title`.
- The API key is never written to disk outside the Keychain, never logged, never in a build setting. The CLI reads `ANTHROPIC_API_KEY` from the environment.
- The extractor version string is `v1` and is the name of the prompt file `extractor.v1.md`.
- Copy on cards: "Sounds like a memory", "Add to timeline", "Not quite", "Who's this?", "Someone new", "Not a person" (from `docs/design/Main.dc.html` and `People.dc.html`).

## Review Focus

Each line names an input the spec implies but no acceptance criterion exercises, and the task whose tests pin it.

1. **The network is down, or the key is missing, mid-session.** Recording continues, the segment stays `pending`, no error dialog interrupts the owner, a quiet status line says words are not being sorted, and the segment is retried at session end. Task 6 (`failedRequestLeavesSegmentPendingAndRecordingContinues`, `missingKeyDisablesExtractionQuietly`).
2. **The model returns a quote or a name that is not in the segment.** It is never shown as the owner's words. The candidate is stored with status `dismissed` and a `rejection` note so the CLI can count invented details. Task 2 (`OutputValidatorTests.quoteNotInSegmentIsRejected`, `peopleRefNotInSegmentIsRejected`) and Task 6 (`rejectedCandidatesAreStoredNotShown`).
3. **The same name said twice, or a name that matches an existing alias in another case.** One mention, one person, no duplicate. Task 7 (`peopleRefMatchingAnAliasLinksWithoutAMention`, `samePersonTwiceInOneSegmentLinksOnce`).
4. **A serious disclosure.** No new memory cards for the rest of that session; the fixed card itself is M4. Task 6 (`seriousDisclosureSuppressesLaterMemoryCards`).
5. **The app is killed between extraction and confirmation, or the same version is re-run.** Pending candidates reappear in the session's detail screen; re-running the same version inserts nothing. Task 1 (`sameSegmentAndVersionTwiceIsRejected`), Task 6 (`alreadyExtractedSegmentIsSkipped`), Task 9 (UI: `pendingCardsShowInSessionDetail`).

---

## File Structure

```
ios/LifelineKit/
  Package.swift                               add resources: Extraction/Prompts
  Sources/LifelineKit/
    Domain/Identifiers.swift                  add CandidateID, MemoryID, PlaceID, MentionID, AnchorID
    Domain/Candidate.swift                    Candidate, CandidateKind, CandidateStatus
    Domain/Memory.swift                       Memory, MemorySpan, MemoryPerson, MemoryPlace, Place, Visibility
    Domain/People.swift                       Alias, Mention, MentionStatus
    Domain/Anchor.swift                       Anchor, AnchorRelation, AnchorTargetKind
    Store/Migrations.swift                    v2: candidate, memory, memory_span, memory_person, place, memory_place, alias, mention, anchor
    Store/AppDatabase.swift                   record conformances for the new types
    Store/CandidateRepository.swift           insert (unique guard), setStatus, pending(in:), candidates(for segment)
    Store/MemoryRepository.swift              insert memory with spans, people, places, anchors; memories(in session)
    Store/PeopleRepository.swift              people, aliases, mentions; findByAlias, insertPerson, resolve
    Store/SessionRepository.swift             add setStatus(segment:), pendingSegments(in:)
    Extraction/ExtractorOutput.swift          Codable output types; the exact spec schema
    Extraction/ExtractorSchema.swift          JSON Schema literal for output_config.format
    Extraction/ExtractorConfig.swift          model, effort, maxTokens, version, promptCacheTTL
    Extraction/Prompts/extractor.v1.md        the prompt (resource)
    Extraction/ExtractorPrompt.swift          loads the resource; renders the fixed system prompt
    Extraction/ContextPacket.swift            ContextPacket + ContextPacketBuilder (pure, caps)
    Extraction/OutputValidator.swift          pure: output + segment text -> accepted / rejected candidates
    Extraction/ExtractionService.swift        protocol + ExtractionRequest + ExtractionError
    Extraction/HTTPTransport.swift            protocol over URLSession; URLSessionTransport
    Extraction/AnthropicMessagesClient.swift  request body, headers, response decoding, retry policy
    Extraction/AnthropicExtractionService.swift  ExtractionService over the client
    Extraction/ScriptedExtractionService.swift   deterministic candidates for UI tests and demos
    Extraction/ExtractionQueue.swift          actor: per-session serial queue, candidate rows, retry at end
    Extraction/CardQueue.swift                pure: candidates -> cards in order, disclosure suppression
    Confirmation/CandidateActions.swift       accept memory, dismiss, resolve mention
    Secrets/SecretStore.swift                 protocol + InMemorySecretStore + key format check
    Secrets/KeychainSecretStore.swift         Security framework, iOS and macOS
    CLI.swift                                 add `extract`
  Tests/LifelineKitTests/
    CandidateRepositoryTests.swift, MemoryRepositoryTests.swift, PeopleRepositoryTests.swift
    ExtractorSchemaTests.swift, OutputValidatorTests.swift, ContextPacketTests.swift
    AnthropicMessagesClientTests.swift, ExtractionQueueTests.swift, CardQueueTests.swift
    CandidateActionsTests.swift, SecretStoreTests.swift, CLIExtractTests.swift
    ExtractorIntegrationTests.swift           opt-in, needs ANTHROPIC_API_KEY
    Fakes/FakeHTTPTransport.swift, Fakes/FakeExtractionService.swift
  Tests/Fixtures/
    transcript-roadtrip.json, transcript-school.json   (garden exists)
    extractor-output-garden.json              a valid model output for decoding tests
ios/Lifeline/
  Dependencies.swift                          add secrets, extraction service, queue factory
  Screens/Session/SessionViewModel.swift      cards, accept/dismiss/resolve
  Screens/Session/SessionScreen.swift         cards under the live text
  Screens/Cards/MemoryCard.swift, WhoIsThisCard.swift, CardStack.swift
  Screens/SessionDetail/SessionDetailViewModel.swift, SessionDetailScreen.swift   memories + waiting cards
  Screens/People/PeopleScreen.swift, PeopleViewModel.swift
  Screens/Settings/SettingsScreen.swift       API key section
  Screens/Home/HomeScreen.swift               People link
ios/LifelineUITests/ExtractionUITests.swift
docs/DECISIONS.md                             entry: API key in Keychain via Settings
```

---

### Task 1: Schema v2, domain types and repositories

**Files:**
- Create: `Sources/LifelineKit/Domain/Candidate.swift`, `Domain/Memory.swift`, `Domain/People.swift`, `Domain/Anchor.swift`, `Store/CandidateRepository.swift`, `Store/MemoryRepository.swift`, `Store/PeopleRepository.swift`
- Modify: `Domain/Identifiers.swift`, `Store/Migrations.swift`, `Store/AppDatabase.swift`, `Store/SessionRepository.swift`
- Test: `Tests/LifelineKitTests/CandidateRepositoryTests.swift`, `MemoryRepositoryTests.swift`, `PeopleRepositoryTests.swift`, extend `MigrationsTests.swift`

**Interfaces:**
- Consumes: `AppDatabase`, `SessionRepository`, `Segment`, `Word`, `Person`, `TypedID`.
- Produces:
  - `CandidateID`, `MemoryID`, `PlaceID`, `MentionID`, `AnchorID: TypedID`.
  - `enum CandidateKind: String { case memory, person, place, flag }`; `enum CandidateStatus: String { case pending, accepted, dismissed, superseded }`.
  - `struct Candidate { id, segmentID, extractorVersion: String, kind, payload: String (JSON), confidence: Double, status, rejection: String?, createdAt: Date }`.
  - `struct Memory { id, title, summaryQuote, visibility: Visibility (.timeline/.private), chapterID: String?, createdFromCandidateID: CandidateID, createdAt }` plus the time-range columns `earliest, latest, likelyStart, likelyEnd: String?` (`YYYY-MM-DD`), `granularity: String?`, `origin: String?`, `evidenceText: String?`, all nil in M2.
  - `struct MemorySpan { memoryID, segmentID, startMs, endMs, order }`, `struct MemoryPerson { memoryID, personID, roleText: String? }`, `struct Place { id, nameText, lat: Double?, lon: Double? }`, `struct MemoryPlace { memoryID, placeID }`.
  - `struct Alias { personID, text }`, `enum MentionStatus: String { case unresolved, resolved, notAPerson = "not_a_person" }`, `struct Mention { id, segmentID, text, status, personID: PersonID? }`.
  - `struct Anchor { id, memoryID, phrase, relation: AnchorRelation, targetKind: AnchorTargetKind, targetID: String?, value: String? (JSON), resolved: Bool }`; `AnchorRelation: before, after, during, sameYearAs = "same_year_as", age, absolute`; `AnchorTargetKind: memory, personBirth = "person_birth", chapter, publicEvent = "public_event", none`.
  - `CandidateRepository.insert(_:) throws` (throws `CandidateRepository.Error.duplicate` on `(segment_id, extractor_version, kind, payload)` already present; the unique index is `(segment_id, extractor_version, ordinal)` where `ordinal` is the candidate's position in the model output), `setStatus(_ id: CandidateID, _ status: CandidateStatus, rejection: String? = nil) throws`, `candidates(for segment: SegmentID) throws -> [Candidate]`, `pending(in session: SessionID) throws -> [Candidate]` (join through segment, segment index then ordinal), `fetch(_ id:) -> Candidate?`.
  - `MemoryRepository.insert(_ memory: Memory, spans: [MemorySpan], people: [MemoryPerson], places: [MemoryPlace], anchors: [Anchor]) throws` (one transaction; throws `MemoryRepository.Error.noSpan` if `spans` is empty), `memories(in session: SessionID) throws -> [Memory]` (via spans, session order), `people(of memory: MemoryID) throws -> [Person]`, `spans(of:) -> [MemorySpan]`.
  - `PeopleRepository.people() throws -> [Person]` (owner first, then display name), `aliases(of: PersonID) -> [Alias]`, `findPerson(matching text: String) throws -> Person?` (case- and whitespace-insensitive match on `display_name` or any alias), `insertPerson(displayName: String) throws -> Person` (also inserts the alias equal to the name), `addAlias(_ text: String, to: PersonID) throws` (no-op if present), `insertMention(_:) throws`, `mentions(status: MentionStatus) -> [Mention]`, `mention(id:) -> Mention?`, `resolve(_ id: MentionID, to person: PersonID) throws` (status resolved, person set, alias added), `markNotAPerson(_ id: MentionID) throws`, `insertPlace(nameText:) -> Place` (reuses an existing row with the same text, case-insensitive).
  - `SessionRepository.setStatus(_ status: SegmentStatus, for segment: SegmentID) throws`, `segments(in session: SessionID, status: SegmentStatus) throws -> [Segment]`, `fetchSegment(_ id: SegmentID) -> Segment?`.

- [ ] **Step 1: Write the failing migration and repository tests**

```swift
@Test func v2CreatesTheConfirmationTables() throws {
    let db = try AppDatabase.inMemory()
    let tables = try db.writer.read { try String.fetchAll($0, sql: "select name from sqlite_master where type = 'table' order by name") }
    for t in ["alias", "anchor", "candidate", "memory", "memory_person", "memory_place", "memory_span", "mention", "place"] { #expect(tables.contains(t)) }
}

@Test func sameSegmentAndVersionTwiceIsRejected() throws {
    // insert candidate ordinal 0 for (segment, "v1") twice -> second insert throws .duplicate; count stays 1
}

@Test func pendingCandidatesComeInSegmentThenOrdinalOrder() throws {
    // two segments, two candidates each inserted out of order -> pending(in:) returns s0#0, s0#1, s1#0, s1#1
}

@Test func memoryNeedsAtLeastOneSpan() throws {
    // insert(memory, spans: []) throws .noSpan and writes nothing
}

@Test func memoryInsertIsOneTransaction() throws {
    // insert with a MemoryPerson pointing at a missing person fails the FK and leaves no memory row
}

@Test func findPersonMatchesDisplayNameAndAliasIgnoringCase() throws {
    // person "Maya" with alias "my sister"; findPerson("MY SISTER ") and findPerson("maya") return it; findPerson("Sam") is nil
}

@Test func resolveMentionAddsAliasAndLinksPerson() throws {
    // mention "Mai" resolved to Maya -> status resolved, personID set, aliases(of: Maya) contains "Mai"
}

@Test func insertPlaceReusesTheSameName() throws {
    // insertPlace("Fresno") twice (second "fresno") -> same id
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd ios/LifelineKit && swift test --filter "Migrations|CandidateRepository|MemoryRepository|PeopleRepository"`
Expected: compile errors for missing types.

- [ ] **Step 3: Implement the types, migration v2 and repositories**

Register `"v2"` after `"v1"`; never edit v1. Explicit snake_case columns with `references(..., onDelete: .cascade)` as in v1. `candidate` gets `uniqueKey(["segment_id", "extractor_version", "ordinal"])`. `memory.time_range` columns are the seven listed on `Memory`. `alias` primary key `(person_id, text)`. `memory_span` primary key `(memory_id, "order")`. Dates as `.datetime` like v1 (the ISO-8601 cleanup is a deferred minor from M1; do not fix it here).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios/LifelineKit && swift test`
Expected: all pass, 68 + new.

- [ ] **Step 5: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add schema v2 and repositories for candidates, memories, people and anchors"
```

---

### Task 2: Extractor output, schema, prompt, config and validator

**Files:**
- Create: `Extraction/ExtractorOutput.swift`, `Extraction/ExtractorSchema.swift`, `Extraction/ExtractorConfig.swift`, `Extraction/Prompts/extractor.v1.md`, `Extraction/ExtractorPrompt.swift`, `Extraction/OutputValidator.swift`, `Tests/Fixtures/extractor-output-garden.json`
- Modify: `Package.swift` (add `resources: [.copy("Extraction/Prompts")]` to the `LifelineKit` target)
- Test: `ExtractorSchemaTests.swift`, `OutputValidatorTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `struct ExtractorOutput: Codable, Sendable { memories: [MemoryOut], mentions: [MentionOut], flags: Flags }`
  - `struct MemoryOut { ref: String, title: String, quote: String, segmentSpan: WordSpan, peopleRefs: [String], placeText: String?, anchors: [AnchorOut], sameAsMemoryID: String?, collectionHint: String?, chapterHint: String?, confidence: Double }`, `struct WordSpan { startWord: Int, endWord: Int }` (inclusive word indexes into the segment's words), `struct AnchorOut { phrase: String, relation: AnchorRelation, targetText: String?, value: String? }`, `struct MentionOut { text: String, kind: MentionKind (.person/.place), likelyAliasOfPersonID: String?, confidence: Double }`, `struct Flags { seriousDisclosure: Bool, wantsToStop: Bool, wantsToChangeSubject: Bool }`. Snake-case coding keys match the spec.
  - `enum ExtractorSchema { static let json: [String: Any] }` the JSON Schema of `ExtractorOutput`: every object has `additionalProperties: false` and lists every property in `required`; optional fields use `"type": ["string", "null"]`; no numeric or string constraints; `relation` and `kind` are `enum`s.
  - `struct ExtractorConfig: Sendable { model = "claude-opus-5-5", effort = "low", maxTokens = 4096, version = "v1", apiVersion = "2023-06-01", betas = ["server-side-fallback-2026-07-01"]; static let `default` }`.
  - `enum ExtractorPrompt { static func system(version: String) throws -> String }` (reads `extractor.<version>.md` from `Bundle.module`; throws `.missingPrompt(version)`), `static func userMessage(segmentText: String, words: [String], packet: ContextPacket) -> String` (Task 3 defines `ContextPacket`; this function is written in Task 3).
  - `enum OutputValidator { static func validate(_ output: ExtractorOutput, segmentText: String, words: [String]) -> Validated }`, `struct Validated { accepted: [ValidatedCandidate], rejected: [(candidate: ValidatedCandidate, reason: String)], flags: Flags }`, `enum ValidatedCandidate { case memory(MemoryOut), mention(MentionOut) }`. A memory is accepted only if `quote` is a substring of the segment text after whitespace normalization and case folding, `segmentSpan` is within `0..<words.count` with `start <= end`, every `peopleRef` and `placeText` and `anchor.phrase` is a substring of the segment text, and `title` has at most 8 words. A mention is accepted only if `text` is a substring. Anything else is rejected with a one-line reason naming the field.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func schemaForbidsExtraPropertiesEverywhere() throws {
    // walk ExtractorSchema.json recursively; every "type": "object" has additionalProperties == false and required == all property keys
}
@Test func sampleOutputDecodesWithSpecKeys() throws {
    // decode Tests/Fixtures/extractor-output-garden.json -> 1 memory titled "The pomegranate tree", people_refs ["my mother"], 1 mention, flags all false
}
@Test func promptV1LoadsAndNamesTheRules() throws {
    let text = try ExtractorPrompt.system(version: "v1")
    #expect(text.contains("Extract only what is said") && text.contains("8 words"))
    #expect(throws: ExtractorPrompt.Error.missingPrompt("v9")) { try ExtractorPrompt.system(version: "v9") }
}
@Test func quoteNotInSegmentIsRejected() { /* quote "we drove to Yosemite" against segment "the garden had a pomegranate tree" -> rejected, reason contains "quote" */ }
@Test func peopleRefNotInSegmentIsRejected() { /* people_refs ["Dad"] not in text -> rejected, reason contains "people_refs" */ }
@Test func quoteMatchesAcrossWhitespaceAndCase() { /* quote "The  garden\nhad" against "the garden had..." -> accepted */ }
@Test func spanOutsideWordsIsRejected() { /* end_word == words.count -> rejected */ }
@Test func titleOverEightWordsIsRejected() { }
@Test func flagsPassThroughUnchanged() { }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "ExtractorSchema|OutputValidator"`
Expected: compile errors.

- [ ] **Step 3: Write `extractor.v1.md`**

The prompt is fixed copy; write it in full here, in the file, under these headings and rules, in plain sentences:

- Role: "You sort what a person says about their life into candidates for their timeline. The person is the author. You never add, infer or correct."
- The five prompt rules from spec §7 verbatim: extract only what is said; a summary is a `collection_hint`, a named era a `chapter_hint`; mark confidence honestly; `serious_disclosure` for abuse, danger to self or others, or similar; `title` is at most 8 words and prefers a phrase from the text.
- Field rules: `quote` is copied exactly from the segment; `segment_span` indexes the segment's words, 0-based, inclusive; `people_refs` and `place_text` are copied phrases; `anchors` carry the owner's phrase and one relation; `same_as_memory_id` refers to a memory in the context packet; empty arrays when nothing applies.
- Context: "The context packet lists people, memories so far and the previous segments. Use it to link, never to invent."
- Output: "Return only the JSON object."

- [ ] **Step 4: Implement the types, schema, config, prompt loader and validator**

`ExtractorSchema.json` is built from nested dictionary literals so a test can walk it. Keep `OutputValidator` free of I/O.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add ios/LifelineKit
git commit -m "Add extractor output types, schema, prompt v1 and the output validator"
```

---

### Task 3: Context packet

**Files:**
- Create: `Extraction/ContextPacket.swift`
- Modify: `Extraction/ExtractorPrompt.swift` (add `userMessage`)
- Test: `ContextPacketTests.swift`

**Interfaces:**
- Consumes: `Segment`, `Person`, `Alias`, `Memory`, `PeopleRepository`, `MemoryRepository`, `SessionRepository`.
- Produces:
  - `struct ContextPacket: Codable, Sendable, Equatable { previousSegments: [String], people: [PersonEntry], chapters: [ChapterEntry], memories: [MemoryEntry], curiosity: [String], stage: String, profileFreeText: String? }`, `struct PersonEntry { id: String, name: String, aliases: [String] }`, `struct MemoryEntry { id: String, title: String, rangeText: String? }`, `struct ChapterEntry { id: String, title: String, rangeText: String? }`.
  - `struct ContextPacketLimits { previousSegments = 2, people = 50, curiosity = 10 }`.
  - `enum ContextPacketBuilder { static func build(segment: Segment, previous: [Segment], people: [(Person, [Alias])], memories: [Memory], profileFreeText: String?, stage: String, limits: ContextPacketLimits = .init()) -> ContextPacket }` (pure; `previous` is every earlier segment of the session in order, the builder keeps the last `limits.previousSegments`; people are capped by most recently used, which M2 approximates by the order given, owner excluded; chapters and curiosity are empty in M2).
  - `ExtractorPrompt.userMessage(segmentText:words:packet:) -> String` renders the words as `0:the 1:garden …` so spans are unambiguous, then the packet as JSON, then the segment text.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func keepsOnlyTheLastTwoPreviousSegments() { }
@Test func capsPeopleAtFiftyAndExcludesTheOwner() { }
@Test func memoriesOfThisSessionCarryTheirTitles() { }
@Test func userMessageNumbersEveryWord() { /* contains "0:the" and "4:house" */ }
@Test func packetIsStableJSON() { /* encoding the same packet twice gives identical bytes (sorted keys) so the cache prefix is stable */ }
```

- [ ] **Step 2: Run to verify they fail** — `swift test --filter ContextPacket` — Expected: compile errors.
- [ ] **Step 3: Implement** `ContextPacket.swift` and `userMessage`. Use `JSONEncoder` with `.sortedKeys` and `.withoutEscapingSlashes`.
- [ ] **Step 4: Run to verify they pass** — `swift test` — Expected: all pass.
- [ ] **Step 5: Commit** — `git commit -m "Add the context packet builder and the extractor user message"`

---

### Task 4: Messages API client and `AnthropicExtractionService`

**Files:**
- Create: `Extraction/ExtractionService.swift`, `Extraction/HTTPTransport.swift`, `Extraction/AnthropicMessagesClient.swift`, `Extraction/AnthropicExtractionService.swift`, `Extraction/ScriptedExtractionService.swift`, `Tests/LifelineKitTests/Fakes/FakeHTTPTransport.swift`, `Fakes/FakeExtractionService.swift`
- Test: `AnthropicMessagesClientTests.swift`

**Interfaces:**
- Consumes: `ExtractorOutput`, `ExtractorSchema`, `ExtractorConfig`, `ExtractorPrompt`, `ContextPacket`.
- Produces:
  - `struct ExtractionRequest: Sendable { segmentID: SegmentID, segmentText: String, words: [String], packet: ContextPacket }`.
  - `struct ExtractionResponse: Sendable { output: ExtractorOutput, version: String, model: String, usage: Usage }`, `struct Usage { inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens: Int }`.
  - `enum ExtractionError: Error, Equatable { case noKey, unauthorized, rateLimited(retryAfterSeconds: Int?), server(status: Int), network(String), refused(category: String?), truncated, badOutput(String), missingPrompt(String) }`.
  - `protocol ExtractionService: Sendable { func extract(_ request: ExtractionRequest) async throws(ExtractionError) -> ExtractionResponse; var version: String { get } }`.
  - `protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`; `struct URLSessionTransport: HTTPTransport` (timeout 60 s).
  - `struct AnthropicMessagesClient: Sendable { init(config: ExtractorConfig, apiKey: @Sendable () -> String?, transport: HTTPTransport, sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }); func extract(system: String, user: String) async throws(ExtractionError) -> (ExtractorOutput, model: String, usage: Usage) }`. Body: `model`, `max_tokens`, `system: [{type: text, text: system, cache_control: {type: ephemeral}}]`, `messages: [{role: user, content: user}]`, `output_config: {effort, format: {type: json_schema, schema: ExtractorSchema.json}}`, `fallbacks: "default"`. Retries 429, 500, 529 and network errors up to 3 attempts with delays 1 s, 2 s, 4 s (`retry-after` wins when present); 400, 401, 403, 404 do not retry. Parses `stop_reason` first: `refusal` → `.refused(stop_details.category)`, `max_tokens` → `.truncated`, otherwise concatenates `text` blocks and decodes `ExtractorOutput` (`.badOutput` on failure).
  - `struct AnthropicExtractionService: ExtractionService { init(config: ExtractorConfig = .default, apiKey: @Sendable () -> String?, transport: HTTPTransport = URLSessionTransport()) }`: loads the system prompt once, appends `profileFreeText` as a second system block without cache control, renders the user message, calls the client.
  - `final class ScriptedExtractionService: ExtractionService` returns, for any segment whose text contains "blue door", one memory (`title: "The blue door"`, `quote: the segment text`, `people_refs: ["Maya"]`, one anchor `phrase: "when I was six", relation: .age`) and one person mention "Maya"; for any other segment an empty output. Version `"scripted"`.
  - `FakeExtractionService`: queue of results or errors per call, records requests. `FakeHTTPTransport`: queue of `(status, body)` or thrown errors, records requests.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func requestCarriesTheSpecShape() async throws {
    // send; decode recorded body: model "claude-opus-5-5", max_tokens 4096, output_config.effort "low",
    // output_config.format.type "json_schema", fallbacks "default", system[0].cache_control.type "ephemeral",
    // no "thinking" key; headers x-api-key, anthropic-version 2023-06-01, anthropic-beta contains server-side-fallback-2026-07-01
}
@Test func parsesTextBlockIntoOutput() async throws { }
@Test func refusalIsNotParsed() async throws { /* stop_reason refusal, stop_details.category "cyber" -> .refused("cyber") */ }
@Test func maxTokensIsTruncated() async throws { }
@Test func missingKeyFailsBeforeAnyRequest() async throws { /* apiKey returns nil -> .noKey, transport saw 0 requests */ }
@Test func unauthorizedDoesNotRetry() async throws { /* 401 -> .unauthorized after 1 request */ }
@Test func rateLimitRetriesThenGivesUp() async throws { /* 429 x3 -> .rateLimited, 3 requests, sleeps [1s, 2s] */ }
@Test func retryAfterHeaderWins() async throws { /* retry-after: 5 -> sleep 5s */ }
@Test func networkErrorRetriesAndSucceeds() async throws { }
@Test func profileFreeTextIsASecondSystemBlockWithoutCache() async throws { }
```

- [ ] **Step 2: Run to verify they fail** — `swift test --filter AnthropicMessagesClient` — Expected: compile errors.
- [ ] **Step 3: Implement** the transport, client, service, scripted service and fakes. `Codable` request types; no third-party client.
- [ ] **Step 4: Run to verify they pass** — `swift test` — Expected: all pass.
- [ ] **Step 5: Commit** — `git commit -m "Add the Messages API client and AnthropicExtractionService"`

---

### Task 5: Secret store

**Files:**
- Create: `Secrets/SecretStore.swift`, `Secrets/KeychainSecretStore.swift`
- Test: `SecretStoreTests.swift`

**Interfaces:**
- Produces: `protocol SecretStore: Sendable { func read(_ key: SecretKey) throws -> String?; func write(_ value: String, for key: SecretKey) throws; func delete(_ key: SecretKey) throws }`, `enum SecretKey: String { case anthropicAPIKey = "anthropic-api-key" }`, `final class InMemorySecretStore: SecretStore`, `struct KeychainSecretStore: SecretStore { init(service: String = "com.lifeline.secrets") }` using `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, update-or-add on write. `enum APIKeyFormat { static func looksValid(_ s: String) -> Bool }` (trimmed, starts with `sk-ant-`, no whitespace, length ≥ 20).

- [ ] **Step 1: Write the failing tests** — `inMemoryRoundTrip`, `deleteRemoves`, `apiKeyFormatRejectsBlankAndSpaces`, `apiKeyFormatAcceptsAConsoleKey` (`"sk-ant-api03-" + 40 x "a"`).
- [ ] **Step 2: Run to verify they fail** — `swift test --filter SecretStore`.
- [ ] **Step 3: Implement.** The Keychain store is exercised on the device (Task 10), not in `swift test`, because the macOS test host may prompt.
- [ ] **Step 4: Run to verify they pass** — `swift test`.
- [ ] **Step 5: Commit** — `git commit -m "Add SecretStore with Keychain and in-memory implementations"`

---

### Task 6: Extraction queue and card queue

**Files:**
- Create: `Extraction/ExtractionQueue.swift`, `Extraction/CardQueue.swift`
- Test: `ExtractionQueueTests.swift`, `CardQueueTests.swift`

**Interfaces:**
- Consumes: `ExtractionService`, `OutputValidator`, `ContextPacketBuilder`, `CandidateRepository`, `SessionRepository`, `PeopleRepository`, `MemoryRepository`, `ProfileRepository`.
- Produces:
  - `actor ExtractionQueue { init(session: SessionID, service: any ExtractionService, store: ExtractionStore, log: @Sendable (String) -> Void); func enqueue(_ segment: SegmentID); func drain() async; var events: AsyncStream<ExtractionEvent> }` where `struct ExtractionStore { candidates: CandidateRepository, sessions: SessionRepository, people: PeopleRepository, memories: MemoryRepository, profile: ProfileRepository }`.
  - `enum ExtractionEvent: Sendable, Equatable { case candidates([Candidate], segment: SegmentID), flags(Flags, segment: SegmentID), failed(segment: SegmentID, ExtractionError), skipped(segment: SegmentID) }`.
  - Behavior: one task processes enqueued segments in order. For each: skip if a candidate row with this version exists (`.skipped`); build the packet; call the service; validate; insert accepted candidates `pending` and rejected ones `dismissed` with `rejection`; store a `flag` candidate when any flag is true; set segment status `extracted`; emit. On `ExtractionError`: segment stays `pending`, emit `.failed`, continue with the next segment. `drain()` waits for the queue to empty, then retries every `pending` segment of the session once more and waits again; it is what the recorder calls at Stop. `.noKey` short-circuits: no request, `.failed(.noKey)` once per segment, no retry at drain.
  - `struct CardQueue: Equatable, Sendable { var cards: [Card]; var suppressed: Bool; mutating func apply(_ event: ExtractionEvent); mutating func remove(_ id: CandidateID) }`, `enum Card: Identifiable, Equatable { case memory(Candidate, MemoryOut), whoIsThis(Candidate, MentionOut) }`. Pure. A `flags` event with `seriousDisclosure` sets `suppressed = true`; while suppressed, `.memory` cards are not added (mentions still are, they are questions about names, not memory cards). Cards are appended in event order; accepting or dismissing removes.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func segmentsAreExtractedInOrderAndStoredPending() async throws { }
@Test func rejectedCandidatesAreStoredNotShown() async throws { /* validator rejects -> row dismissed with rejection, event carries only accepted */ }
@Test func failedRequestLeavesSegmentPendingAndRecordingContinues() async throws { /* service throws .network -> .failed, segment still pending, next segment still processed */ }
@Test func drainRetriesPendingOnce() async throws { /* first call fails, drain -> second call succeeds -> extracted */ }
@Test func missingKeyDisablesExtractionQuietly() async throws { /* .noKey -> one .failed per segment, drain makes no further calls */ }
@Test func alreadyExtractedSegmentIsSkipped() async throws { }
@Test func flagsAreStoredAsAFlagCandidate() async throws { }
@Test func cardQueueAppendsInOrderAndRemoves() { }
@Test func seriousDisclosureSuppressesLaterMemoryCards() { /* after flags(seriousDisclosure) a memory card is not added; a whoIsThis card is */ }
```

- [ ] **Step 2: Run to verify they fail** — `swift test --filter "ExtractionQueue|CardQueue"`.
- [ ] **Step 3: Implement.** The actor owns one `Task` loop over an `AsyncStream<SegmentID>`; `drain()` uses a continuation that resolves when the loop is idle.
- [ ] **Step 4: Run to verify they pass** — `swift test`.
- [ ] **Step 5: Commit** — `git commit -m "Add ExtractionQueue and CardQueue"`

---

### Task 7: Confirmation actions

**Files:**
- Create: `Confirmation/CandidateActions.swift`
- Test: `CandidateActionsTests.swift`

**Interfaces:**
- Consumes: Task 1 repositories, `MemoryOut`, `MentionOut`, `Word`.
- Produces: `struct CandidateActions: Sendable { init(store: ExtractionStore) }` with
  - `func acceptMemory(_ candidate: Candidate) throws -> AcceptedMemory` where `struct AcceptedMemory { memory: Memory, newMentions: [Mention] }`. Decodes the payload as `MemoryOut`; maps `segmentSpan` to milliseconds through the segment's words (`startMs` of word `startWord`, `endMs` of word `endWord`); inserts the memory with one span, `summaryQuote = quote`, `visibility = .timeline`, all range columns nil; for each `peopleRef`: `findPerson(matching:)` → `MemoryPerson(roleText: ref)`; otherwise one `Mention` per distinct ref text (case-insensitive) with status `unresolved`, returned in `newMentions`; `placeText` → `insertPlace` + `MemoryPlace`; each anchor → `Anchor(resolved: false, targetKind: .none)`; candidate status `accepted`. Throws `CandidateActions.Error.notPending` if the candidate is not pending, `.wrongKind` if not a memory.
  - `func dismiss(_ candidate: Candidate) throws` → status `dismissed`.
  - `func resolveMention(_ mention: MentionID, to choice: MentionChoice) throws -> Person?` with `enum MentionChoice { case existing(PersonID), new(displayName: String), notAPerson }`. `existing` resolves and adds the alias; `new` inserts the person (display name = mention text unless given) and resolves; `notAPerson` marks. Then links every memory that was created from a candidate in the same segment whose payload `peopleRefs` contains the mention text (case-insensitive) with `MemoryPerson(roleText: mention.text)`, once per memory.
  - `func acceptMention(_ candidate: Candidate) throws -> Mention` inserts the mention row for a `person` candidate and marks the candidate accepted; `whoIsThis` cards call this on first display so the queue survives a kill.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func acceptMemoryWritesSpanInMillisecondsFromWords() throws { /* span words 1...3 -> start = word1.startMs, end = word3.endMs */ }
@Test func peopleRefMatchingAnAliasLinksWithoutAMention() throws { }
@Test func unknownPeopleRefBecomesOneMention() throws { }
@Test func samePersonTwiceInOneSegmentLinksOnce() throws { /* people_refs ["Maya", "maya"] -> one mention; after resolve, one memory_person */ }
@Test func resolveNewPersonLinksTheMemory() throws { }
@Test func notAPersonLinksNothing() throws { }
@Test func acceptTwiceIsRejected() throws { /* second accept throws .notPending; one memory */ }
@Test func placeTextCreatesPlaceAndLink() throws { }
@Test func anchorsAreStoredUnresolved() throws { }
```

- [ ] **Step 2: Run to verify they fail** — `swift test --filter CandidateActions`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify they pass** — `swift test`.
- [ ] **Step 5: Commit** — `git commit -m "Add CandidateActions: accept, dismiss and resolve"`

---

### Task 8: CLI `extract`, fixtures and the opt-in integration test

**Files:**
- Create: `Tests/Fixtures/transcript-roadtrip.json`, `Tests/Fixtures/transcript-school.json`, `Tests/LifelineKitTests/ExtractorIntegrationTests.swift`, `CLIExtractTests.swift`
- Modify: `CLI.swift`, `Sources/lifeline/main.swift` (no change expected beyond passing environment)

**Interfaces:**
- Consumes: `ExtractionQueue`, `AnthropicExtractionService`, `FakeExtractionService`.
- Produces: `CLI.run(_ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment, service: (any ExtractionService)? = nil)`; command `extract --session <id> --db <path> [--version v1] [--model <id>]`. Uses `service` when given (tests), else `AnthropicExtractionService` with the key from `environment["ANTHROPIC_API_KEY"]`; exit 3 with "ANTHROPIC_API_KEY is not set" when missing. Runs the queue over the session's `pending` segments and drains. Prints one line per candidate: `segment_index\tkind\tstatus\tconfidence\ttitle_or_text` then a summary line `N candidates, R rejected, F failed segments`.

- [ ] **Step 1: Write the two fixtures.** Invented, 3 to 4 segments each, same JSON format as `transcript-garden.json`. Road trip: a drive to a lake with "my dad" and "my sister", one age phrase ("I was eleven"). School: "Mr. Alvarez", "third grade", a move to a new town.
- [ ] **Step 2: Write the failing CLI test**

```swift
@Test func extractPrintsCandidatesAndSummary() throws {
    // import garden fixture; run extract with a FakeExtractionService returning one memory + one mention; output has 2 candidate lines and "2 candidates, 0 rejected, 0 failed segments"; segment status extracted
}
@Test func extractWithoutKeyExitsThree() throws { }
```

- [ ] **Step 3: Run to verify it fails** — `swift test --filter CLIExtract`.
- [ ] **Step 4: Implement `extract`.**
- [ ] **Step 5: Write the integration test (opt-in)**

```swift
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
struct ExtractorIntegrationTests {
    @Test(arguments: ["transcript-garden", "transcript-roadtrip", "transcript-school"])
    func noFieldContainsTextAbsentFromTheTranscript(fixture: String) async throws {
        // import fixture, run the real service over every segment, then for every accepted candidate:
        // quote, people_refs, place_text, anchor phrases, mention text are substrings of the segment text; title <= 8 words
    }
}
```

- [ ] **Step 6: Run** — `swift test` (integration suite skipped without the key), then once with the key: `ANTHROPIC_API_KEY=... swift test --filter ExtractorIntegration`. Expected: all pass; record the token usage printed by the test in the commit body.
- [ ] **Step 7: Commit** — `git commit -m "Add lifeline extract, two fixtures and the opt-in extractor integration test"`

---

### Task 9: App: Settings key, cards in the session, memories and people

**Files:**
- Create: `Screens/Cards/MemoryCard.swift`, `Screens/Cards/WhoIsThisCard.swift`, `Screens/Cards/CardStack.swift`, `Screens/People/PeopleScreen.swift`, `Screens/People/PeopleViewModel.swift`, `LifelineUITests/ExtractionUITests.swift`
- Modify: `Dependencies.swift`, `Screens/Settings/SettingsScreen.swift`, `Screens/Session/SessionViewModel.swift`, `Screens/Session/SessionScreen.swift`, `Screens/SessionDetail/SessionDetailViewModel.swift`, `Screens/SessionDetail/SessionDetailScreen.swift`, `Screens/Home/HomeScreen.swift`, `Session/SessionRecorder.swift` (Kit: hand each closed segment to an `onSegmentStored: @Sendable (SegmentID) -> Void` hook and call `drain` through an `onStop: @Sendable () async -> Void` hook), `docs/DECISIONS.md`

**Interfaces:**
- Consumes: everything above.
- Produces (app):
  - `Dependencies` gains `secrets: any SecretStore`, `extraction: any ExtractionService`, `extractionStore: ExtractionStore`, `makeExtractionQueue: @Sendable (SessionID) -> ExtractionQueue`, `actions: CandidateActions`. `live()` uses `KeychainSecretStore` and `AnthropicExtractionService(apiKey: { try? secrets.read(.anthropicAPIKey) })`; `uiTesting()` uses `InMemorySecretStore` pre-filled with a fake key and `ScriptedExtractionService`.
  - Settings: a "Sorting" section with a `SecureField` (`settings.apiKey`), a Save button (`settings.apiKeySave`) enabled only when `APIKeyFormat.looksValid`, a line "Key saved" or "No key. Sessions are recorded; nothing is sorted until you add one.", and a Remove button. The field never shows the stored key; only the saved state.
  - `SessionViewModel` gains `cards: [Card]`, `extractionStatus: String?` ("Not sorting right now" after a `.failed(.network/.server/.rateLimited)`, "Add a key in Settings to sort what you say" after `.noKey`, nil otherwise; the status line keeps errors first), `func accept(_ card: Card) async`, `func dismiss(_ card: Card)`, `func resolve(_ card: Card, _ choice: MentionChoice) async`.
  - `CardStack` renders cards in order under the live text; `MemoryCard` shows "Sounds like a memory", the title in serif, the quote in stone, anchor phrases in ochre (M2 has no resolved dates), people chips, buttons "Add to timeline" (`card.add`) and "Not quite" (`card.dismiss`); swipe left dismisses. `WhoIsThisCard` shows "Who's this?", the mention text in quotes, up to three existing people (`card.person`), "Someone new" (`card.newPerson`), "Not a person" (`card.notAPerson`).
  - `SessionDetailScreen` gains two sections above the segments: "Waiting for you" (pending cards of this session, same components) and "Memories" (title, quote, people names; `detail.memory`).
  - `PeopleScreen` from Home (`home.people`): "Who's this?" queue first (unresolved mentions with the same card), then people with aliases (`people.row`).
  - `SessionRecorder`: when a segment is stored, call `onSegmentStored(segment.id)`; in `stop()`, after the voice session stops and before `endedAt` is written, `await onStop()`. Default hooks are no-ops so M1 tests stand.
- Decision log entry: "2026-10-22 · API key lives in the Keychain, typed into Settings" (why: nothing in the build or the repo; the owner can rotate it without a rebuild; what it costs: first-run setup step).

- [ ] **Step 1: Kit test first** — in `SessionRecorderTests`: `storedSegmentsReachTheHookInOrder` and `stopAwaitsTheStopHookBeforeEnding`. Run, see them fail, implement the hooks, run, see them pass.
- [ ] **Step 2: Write the failing UI tests**

```swift
func testMemoryCardAppearsAndAddsAMemory() {
    // skip About you, Start; wait for staticText "Sounds like a memory"; tap card.add; Stop;
    // open the session row; staticText "detail.memory" exists and contains "The blue door"
}
func testWhoIsThisResolvesToANewPerson() {
    // Start; wait for "Who's this?"; tap card.newPerson; Stop; Home -> home.people; people.row contains "Maya"
}
func testPendingCardsShowInSessionDetail() {
    // Start; wait for "Sounds like a memory"; Stop without acting; open the session; "Sounds like a memory" is in the detail screen
}
func testSettingsSavesAKeyState() {
    // open Settings; type "sk-ant-api03-" + 40 a's in settings.apiKey; settings.apiKeySave; staticText "Key saved"
}
```

- [ ] **Step 3: Run to verify they fail** — `xcodebuild test -project ios/Lifeline.xcodeproj -scheme Lifeline -destination 'id=88EC5B09-3A30-4544-8145-F5246BB99AEE' -only-testing:LifelineUITests/ExtractionUITests` — Expected: failures on missing elements.
- [ ] **Step 4: Implement** the dependencies, screens, view models and the decision entry. Run `xcodegen generate` after adding files.
- [ ] **Step 5: Run all tests** — `swift test` and the full `xcodebuild test` — Expected: all pass (M1's 3 UI tests included).
- [ ] **Step 6: Commit** — `git commit -m "Add extraction cards, Who's this, People, memories in detail and the Settings key"`

---

### Task 10: Device checklist (owner runs this; it is M2's done-when)

1. Settings → paste the Console API key → "Key saved". Kill and relaunch; Settings still says "Key saved".
2. Start a session. Tell one story with a named person and a place, pause 3 s. Expected: within about 10 s a "Sounds like a memory" card with a title in your words, the quote, the person as a chip, the anchor phrase in ochre.
3. Tap "Add to timeline". Expected: the card goes; Stop; the session's detail shows the memory with the person's name once the mention is resolved.
4. A "Who's this?" card for the name. Tap "Someone new". Expected: People shows them; the memory lists them.
5. Say the same name in a later session. Expected: no "Who's this?" card; the memory links the existing person.
6. Turn on Airplane Mode mid-session, tell a story, pause. Expected: no card, status "Not sorting right now", recording continues. Turn it off, Stop. Expected: the segment is retried and its card shows in the detail screen under "Waiting for you".
7. Remove the key in Settings, Start. Expected: "Add a key in Settings to sort what you say", recording works, no requests (check the Console usage page).
8. Tell a story with a clear summary ("we went every summer") and no single instance. Expected: no memory card, or a card whose collection hint reads back the phrase; nothing invented.
9. Copy the database from the phone with Xcode's Devices window; run `ANTHROPIC_API_KEY=… swift run lifeline extract --session <id> --db <path>` on a session with pending segments. Expected: a candidate table, exit 0.
10. Run the opt-in integration test once with the key: `ANTHROPIC_API_KEY=… swift test --filter ExtractorIntegration`. Expected: pass on all three fixtures. Note the cost from the Console.

Record the outcome of each item in the PR description.

---

## Self-review notes

- Spec coverage: §7 When, Context packet, Output schema, Prompt rules, Model call, Idempotency → Tasks 2, 3, 4, 6. §3 Session cards, People → Task 9. §6 tables candidate, memory, memory_span, memory_person, memory_place, person, alias, mention, place, anchor → Task 1 (chapter, collection, curiosity_item, tombstone wait for M3 and M4). §9 serious disclosure suppression → Task 6; the fixed card is M4. §10 `extract`, integration test → Task 8. `resolve`, `eval`, export bundle are M3 and M5.
- Not in M2 by design: the resolver and any date on a card; chapters and collections; the "Waiting for you" section on a timeline (the timeline is M3; M2 puts it in the session detail); the disclosure card copy; export through the share sheet.
- Type names used across tasks were checked once after writing: `ExtractionStore`, `Card`, `MentionChoice`, `ExtractionEvent`, `ValidatedCandidate` appear with the same spelling in every task that uses them.
