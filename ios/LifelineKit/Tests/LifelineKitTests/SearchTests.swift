import Foundation
import Testing
@testable import LifelineKit

struct SearchTests {
    // MARK: - Fixtures (invented)

    private static let base = Date(timeIntervalSince1970: 1_000_000_000)
    private static let late = Date(timeIntervalSince1970: 1_800_000_000)

    private static func entry(_ title: String, type: EntityType, moments: Int = 0, ownWords: String? = nil, aliases: [String] = []) -> SearchIndex.EntityEntry {
        let entity = Entity(id: EntityID(rawValue: "e-\(title)-\(ownWords ?? "")"), type: type, title: title)
        let summary = EntitySummary(entity: entity, ownWords: ownWords, momentRanges: Array(repeating: .unplaced, count: moments), span: .unplaced)
        return .init(summary: summary, aliases: aliases)
    }

    private static func memory(_ title: String, kind: MemoryKind = .event, quote: String = "", tellings: [String] = [],
                               range: TimeRange = .unplaced, toldAt: Date? = nil, createdAt: Date = base) -> SearchIndex.MemoryEntry {
        let memory = Memory(id: MemoryID(rawValue: "m-\(title)"), title: title, summaryQuote: quote, visibility: .timeline, chapterID: nil,
                            createdFromCandidateID: CandidateID(rawValue: "c-\(title)"), createdAt: createdAt, range: range, kind: kind)
        return .init(memory: memory, tellings: tellings, toldAt: toldAt)
    }

    private static func said(_ year: Int) -> TimeRange { .stated(year: year) }

    private let index = SearchIndex(
        entities: [
            entry("Maya", type: .person, moments: 2, ownWords: "my sister", aliases: ["May"]),
            entry("Dad", type: .person, moments: 1, ownWords: "my father"),
            entry("Zoë", type: .person),
            entry("Lena", type: .person, moments: 1, ownWords: "my aunt", aliases: ["Linny"]),
            entry("Sasha", type: .person, moments: 1),
            entry("Sam", type: .person, moments: 3, ownWords: "my roommate"),
            entry("Sam", type: .person, moments: 1, ownWords: "my cousin"),
            entry("Alder Street", type: .place),
            entry("São Paulo", type: .place),
            entry("Dad's Volvo", type: .thing),
            entry("Saying yes to things", type: .idea),
        ],
        memories: [
            memory("Swimming lessons", quote: "I learned to float", tellings: ["my father held me up"]),
            memory("The tree house", tellings: ["a rope and a ladder"]),
            memory("The birthday party", tellings: ["we had cake"]),
            memory("Took things apart", kind: .fact, quote: "I was always the kid who dismantled radios"),
            memory("The long drive", quote: "we drove all night",
                   tellings: ["he kept an old harmonica in the glove box", "the harmonica was out of tune"]),
            memory("The red kite", quote: "it caught the wind", range: .year(1998, origin: .inferred, evidence: nil)),
        ]
    )

    private let lakes = SearchIndex(memories: [
        memory("Cold morning", tellings: ["down by the lake"], range: said(1950)),
        memory("The lake in 1999", range: said(1999)),
        memory("Lake Erie", range: said(2005)),
        memory("Lake", range: said(2020)),
    ])

    private let ordered = SearchIndex(memories: [
        memory("Undated one", tellings: ["a harmonica"], toldAt: late),
        memory("2003 one", tellings: ["a harmonica"], range: said(2003)),
        memory("1999 one", tellings: ["a harmonica"], range: said(1999)),
        memory("Halfdated one", tellings: ["a bell"],
               range: TimeRange(earliest: CivilDate(year: 1990, month: 1, day: 1), latest: nil, likelyStart: nil, likelyEnd: nil,
                                granularity: .year, origin: .stated, evidenceText: nil)),
    ])

    private let factAndMoment = SearchIndex(memories: [
        memory("Stored fact title", kind: .fact, quote: "my harmonica years", range: said(1990), toldAt: late),
        memory("A dated one", tellings: ["a harmonica"], range: said(1999), toldAt: base),
    ])

    // MARK: - The query's edges

    @Test func anEmptyQueryIsNotASearch() {
        for query in ["", "  ", "…", "'"] { #expect(Search.run(query, in: index) == nil) }
    }
    @Test func aQueryThatFindsNothingIsEmptyNotNil() {
        #expect(Search.run("xylophone", in: index)?.isEmpty == true)
    }
    @Test func anEmptyIndexFindsNothing() {
        #expect(Search.run("maya", in: .empty)?.isEmpty == true)
    }
    @Test func aVeryLongQueryAnswers() {
        #expect(Search.run(String(repeating: "lake ", count: 2_000), in: index) != nil)
    }
    @Test func oneCharacterSearchesNamesOnly() throws {
        // "The tree house" has the telling "a rope and a ladder"; Alder Street starts with "a".
        let found = try #require(Search.run("a", in: index))
        #expect(found.places.map(\.summary.entity.title) == ["Alder Street"])
        #expect(found.memories.allSatisfy { $0.match < .text }, "no memory by its words")
        #expect(Search.run("a", in: ordered)?.memories.isEmpty == true, "\"a harmonica\" is a telling, not a name")
    }
    @Test func severalOneCharacterWordsSearchNamesOnly() throws {
        // "Halfdated one" has the telling "a bell": "a b" must not search the words said.
        #expect(Search.run("a b", in: ordered)?.memories.isEmpty == true)
        let found = try #require(Search.run("a b", in: index))
        #expect(found.memories.allSatisfy { $0.match < .text }, "no memory by its words")
        #expect(Search.run("a bell", in: ordered)?.memories.map(\.memory.title) == ["Halfdated one"], "one longer word searches the words")
    }

    // MARK: - Matching

    @Test func caseAndDiacriticsDoNotMatter() {
        #expect(Search.run("ZOE", in: index)?.people.map(\.summary.entity.title) == ["Zoë"])
        #expect(Search.run("sao", in: index)?.places.map(\.summary.entity.title) == ["São Paulo"])
    }
    @Test func punctuationDoesNotMatter() {
        #expect(Search.run("dads volvo", in: index)?.things.map(\.summary.entity.title) == ["Dad's Volvo"])
        #expect(Search.run("Dad's Volvo!", in: index)?.things.count == 1)
    }
    @Test func everyWordMustMatchInAnyOrder() {
        #expect(Search.run("volvo dad", in: index)?.things.count == 1)
        #expect(Search.run("volvo maya", in: index)?.things.isEmpty == true)
    }
    @Test func aWordMatchesFromItsStartOnly() {
        #expect(Search.run("swim", in: index)?.memories.map(\.memory.title) == ["Swimming lessons"])
        #expect(Search.run("art", in: index)?.memories.isEmpty == true, "not inside \"party\"")
        #expect(Search.run("treehouse", in: index)?.memories.isEmpty == true, "no spelling tolerance (decision 7)")
    }

    // MARK: - Kinds

    @Test func aPersonIsFoundByAnAliasAndSaysWhich() throws {
        // Lena has the alias "Linny" and the own words "my aunt".
        let hit = try #require(Search.run("linny", in: index)?.people.first)
        #expect(hit.match == .alias && hit.matchedAlias == "Linny" && hit.secondLine == "Linny")
        #expect(Search.run("lena", in: index)?.people.first?.secondLine == "my aunt")
    }
    @Test func aTitleMatchBeatsAnAliasMatchAndShowsOnce() {
        // Maya also has the alias "May".
        #expect(Search.run("may", in: index)?.people.map(\.match) == [.titleStart])
        #expect(Search.run("may", in: index)?.people.first?.matchedAlias == nil)
    }
    @Test func twoPeopleWithOneNameBothShow() {
        // Sam "my roommate" has 3 moments; Sam "my cousin" has 1.
        #expect(Search.run("sam", in: index)?.people.map(\.secondLine) == ["my roommate", "my cousin"])
    }
    @Test func aFactIsFoundByItsWordsNotItsHiddenTitle() {
        #expect(Search.run("took", in: index)?.memories.isEmpty == true)
        #expect(Search.run("radios", in: index)?.memories.map(\.heading) == ["\u{201C}I was always the kid who dismantled radios\u{201D}"])
        #expect(Search.run("radios", in: index)?.memories.first?.matchedText == "I was always the kid who dismantled radios")
    }
    @Test func aMomentIsFoundByItsWords() throws {
        let hit = try #require(Search.run("harmonica glove", in: index)?.memories.first)
        #expect(hit.memory.title == "The long drive" && hit.match == .text)
        #expect(hit.matchedText == "he kept an old harmonica in the glove box")
    }
    @Test func aMomentOfKindOtherIsFoundByItsTitle() throws {
        let fair = SearchIndex(memories: [Self.memory("The county fair", kind: .other, tellings: ["we won a ribbon"])])
        let hit = try #require(Search.run("county", in: fair)?.memories.first)
        #expect(hit.memory.title == "The county fair" && hit.match == .titleWords)
    }
    @Test func aFeelingOrAGoalIsFoundByItsQuoteNeverItsStoredTitle() throws {
        for kind in [MemoryKind.feeling, .goal] {
            let told = SearchIndex(memories: [Self.memory("Stored title words", kind: kind, quote: "I wanted to see the ocean")])
            #expect(Search.run("stored", in: told)?.memories.isEmpty == true, "\(kind): the stored title is not searched")
            let hit = try #require(Search.run("ocean", in: told)?.memories.first)
            #expect(hit.match == .text && hit.matchedText == "I wanted to see the ocean", "\(kind)")
        }
    }
    @Test func aRetoldMemoryShowsOnce() {
        #expect(Search.run("harmonica", in: index)?.memories.filter { $0.memory.title == "The long drive" }.count == 1)
    }
    @Test func theQueryWordsMayBeSplitBetweenTitleAndWords() throws {
        let found = try #require(Search.run("drive harmonica", in: index))
        #expect(found.memories.map(\.memory.title) == ["The long drive"])
        #expect(found.memories.first?.matchedText == "he kept an old harmonica in the glove box")
    }
    @Test func theWordsShownAreTheOnesTheTitleDoesNotShow() throws {
        // "long" is in the title and in the first telling; only the second telling shows why the memory was found.
        let drive = SearchIndex(memories: [Self.memory("The long drive", quote: "we drove all night",
                                                       tellings: ["it was a long way", "he played the harmonica"])])
        let hit = try #require(Search.run("long harmonica", in: drive)?.memories.first)
        #expect(hit.match == .text && hit.matchedText == "he played the harmonica")
    }
    @Test func aTitleMatchHasNoMatchedText() {
        #expect(Search.run("kite", in: index)?.memories.first?.matchedText == nil)
    }
    @Test func aMemoryInTheIndexTwiceShowsOnce() {
        let twice = SearchIndex(entities: index.entities + index.entities, memories: index.memories + index.memories)
        #expect(Search.run("sasha", in: twice)?.people.count == 1)
        #expect(Search.run("harmonica", in: twice)?.memories.count == 1)
    }

    // MARK: - The index

    @Test func anEntryIsFoldedOnceWhenItIsMade() {
        // `Search.run` reads these words; every test above runs on them.
        let person = Self.entry("Zoë", type: .person, aliases: ["Dad's Volvo", "SÃO"])
        #expect(person.titleWords == SearchFold.words("Zoë"))
        #expect(person.aliasWords == ["Dad's Volvo", "SÃO"].map(SearchFold.words))
        let tellings = ["he kept an old harmonica", "the harmonica was out of tune"]
        let moment = Self.memory("The long drive", quote: "we drove all night", tellings: tellings)
        #expect(moment.titleWords == SearchFold.words("The long drive"))
        #expect(moment.textWords == (["we drove all night"] + tellings).map(SearchFold.words), "the quote first, then each telling")
        let fact = Self.memory("Took things apart", kind: .fact, quote: "I dismantled radios")
        #expect(fact.titleWords.isEmpty, "a fact's stored title is never searched")
        #expect(fact.textWords == [SearchFold.words("I dismantled radios")])
    }

    // MARK: - Order

    @Test func matchesOrderByHowTheyMatched() {
        // The text match is the oldest and the exact title the newest: the match decides first.
        #expect(Search.run("lake", in: lakes)?.memories.map(\.match) == [.exactTitle, .titleStart, .titleWords, .text])
    }
    @Test func entitiesWithOneMatchGoMostToldFirstThenByTitle() {
        #expect(Search.run("s", in: index)?.people.map(\.summary.entity.title) == ["Sam", "Sam", "Sasha"])
    }
    @Test func memoriesWithOneMatchGoInLifeOrder() {
        #expect(Search.run("harmonica", in: ordered)?.memories.map(\.memory.title) == ["1999 one", "2003 one", "Undated one"])
    }
    @Test func equalMemoriesGoByIdSoTheyNeverSwap() {
        let twins = SearchIndex(memories: [Self.memory("Twin b", tellings: ["a kite"]), Self.memory("Twin a", tellings: ["a kite"])])
        #expect(Search.run("kite", in: twins)?.memories.map(\.memory.title) == ["Twin a", "Twin b"])
    }
    @Test func theOrderNeverVaries() {
        let reversed = SearchIndex(entities: index.entities.reversed(), memories: index.memories.reversed())
        #expect(Search.run("s", in: index) == Search.run("s", in: reversed))
        #expect(Search.run("harmonica", in: ordered) == Search.run("harmonica", in: SearchIndex(memories: ordered.memories.reversed())))
    }

    // MARK: - What a hit says

    @Test func aGuessedDateKeepsItsWords() {
        #expect(Search.run("kite", in: index)?.memories.first?.dateText == "around 1998")
    }
    @Test func anUndatedMomentHasNoDateLine() {
        #expect(Search.run("undated", in: ordered)?.memories.first?.dateText == nil)
    }
    @Test func aHalfDatedMomentHasNoDateLine() throws {
        let hit = try #require(Search.run("halfdated", in: ordered)?.memories.first)
        #expect(hit.memory.range.displayText == "no date yet" && hit.dateText == nil)
    }
    @Test func aFactsHiddenRangeDoesNotSetItsPlace() {
        // The fact's stored range is 1990, before the moment's 1999; it was told last.
        #expect(Search.run("harmonica", in: factAndMoment)?.memories.map(\.memory.kind) == [.event, .fact])
    }
    @Test func aFactHasNoDateLine() {
        #expect(Search.run("radios", in: index)?.memories.first?.dateText == nil, "a fact's stored range is not shown (M7)")
        #expect(Search.run("harmonica", in: factAndMoment)?.memories.last?.dateText == nil)
    }
    @Test func groupsAndTheirHeadings() throws {
        #expect(EntityType.allCases.map(SearchResults.heading) == ["People", "Places", "Things", "What you think"])
        #expect(SearchResults.memoriesHeading == "Memories")
        let found = try #require(Search.run("dad", in: index))
        #expect(found.people.count == 1 && found.things.count == 1, "Dad and Dad's Volvo, each in its group")
    }
    @Test func everyMemoryFoundByItsWordsHasALineOfThem() {
        // A fact whose quote holds every word shows none: its heading is the quote (decision 13).
        let withAFact = SearchIndex(memories: index.memories + [Self.backRow])
        let queries = ["harmonica", "harmonica glove", "drive harmonica", "long harmonica", "tune", "float", "father", "rope", "cake", "night", "wind",
                       "learned float", "sit classroom", "classroom", "back chalk"]
        for query in queries {
            for hit in Search.run(query, in: withAFact)?.memories ?? [] where hit.match == .text && !Self.headingHoldsEveryWord(hit, query) {
                let line = SearchSnippet.line(for: hit, query: query)
                #expect(line != nil, "\(query): \(hit.heading)")
                let unshown = Search.unshown(SearchFold.queryWords(query), by: SearchFold.words(hit.heading))
                #expect(line?.parts.contains { part in part.isMatch && SearchFold.words(part.text).contains { w in unshown.contains { w.hasPrefix($0) } } } == true,
                        "\(query): the line shows a word the heading does not")
            }
        }
    }

    /// A fact whose heading, the cleaned quote, holds "sit" but not "classroom".
    private static let backRow = memory("Sat at the back", kind: .fact, quote: "I would sit at the back",
                                        tellings: ["we had to sit in rows", "the classroom smelled of chalk"])

    private static func headingHoldsEveryWord(_ hit: SearchResults.MemoryHit, _ query: String) -> Bool {
        let headingWords = SearchFold.words(hit.heading)
        return SearchFold.queryWords(query).allSatisfy { word in headingWords.contains { $0.hasPrefix(word) } }
    }

    @Test func aFactsLineShowsTheWordItsQuoteDoesNot() throws {
        let hit = try #require(Search.run("sit classroom", in: SearchIndex(memories: [Self.backRow]))?.memories.first)
        #expect(hit.matchedText == "the classroom smelled of chalk", "the quote already shows \"sit\"")
        let line = try #require(SearchSnippet.line(for: hit, query: "sit classroom"))
        #expect(line.parts.filter(\.isMatch).map(\.text) == ["classroom"])
    }
    @Test func anIdeaIsFoundInItsGroup() {
        #expect(Search.run("saying yes", in: index)?.ideas.map(\.summary.entity.title) == ["Saying yes to things"])
    }
}
