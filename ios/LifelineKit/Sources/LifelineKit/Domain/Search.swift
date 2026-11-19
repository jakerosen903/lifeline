import Foundation

/// A query and an in-memory index to grouped, ordered results (decisions 7, 9, 11, 12, 13). Pure.
public enum Search {
    /// Nil when the query has no letter or digit: the opening state, not "nothing found".
    public static func run(_ query: String, in index: SearchIndex) -> SearchResults? {
        guard let query = WordQuery(query) else { return nil }
        // An entry twice in the index (a duplicate read) shows once.
        return SearchResults(
            entities: firstOfEach(index.entities.compactMap { entityHit($0, query) }),
            memories: firstOfEach(index.memories.compactMap { memoryHit($0, query) }),
            order: index
        )
    }

    /// The folded query words that start no word of the heading: the words the text under a heading must show.
    static func unshown(_ queryWords: [String], by headingWords: [String]) -> [String] {
        queryWords.filter { word in !headingWords.contains { $0.hasPrefix(word) } }
    }
}

// MARK: - The query

/// The folded words of a query. Every word must start a word of the item.
private struct WordQuery {
    let words: [String]
    /// The words with one space between: a title that equals or starts with it ranks first.
    let phrase: String
    /// A query of one-character words searches names only (decision 9): "a b" would match nearly every telling.
    let searchesText: Bool

    init?(_ query: String) {
        let words = SearchFold.queryWords(query)
        guard !words.isEmpty else { return nil }
        self.words = words
        phrase = words.joined(separator: " ")
        searchesText = words.contains { $0.count > 1 }
    }

    /// Every query word starts some word of `candidates`.
    func isCoveredBy(_ candidates: [String]) -> Bool {
        words.allSatisfy { word in candidates.contains { $0.hasPrefix(word) } }
    }


    func titleMatch(_ titleWords: [String]) -> SearchMatch? {
        let title = titleWords.joined(separator: " ")
        if title == phrase { return .exactTitle }
        if title.hasPrefix(phrase) { return .titleStart }
        return isCoveredBy(titleWords) ? .titleWords : nil
    }
}

// MARK: - One item

private extension Search {
    static func firstOfEach<Hit: Identifiable>(_ hits: [Hit]) -> [Hit] {
        var seen = Set<Hit.ID>()
        return hits.filter { seen.insert($0.id).inserted }
    }

    static func entityHit(_ entry: SearchIndex.EntityEntry, _ query: WordQuery) -> SearchResults.EntityHit? {
        if let match = query.titleMatch(entry.titleWords) {
            return .init(summary: entry.summary, match: match)
        }
        if let i = entry.aliasWords.firstIndex(where: query.isCoveredBy) {
            return .init(summary: entry.summary, match: .alias, matchedAlias: entry.aliases[i])
        }
        return nil
    }

    static func memoryHit(_ entry: SearchIndex.MemoryEntry, _ query: WordQuery) -> SearchResults.MemoryHit? {
        let memory = entry.memory
        // A fact, a feeling or a goal has a stored title the person never said: `titleWords` is empty.
        if memory.isMoment, let match = query.titleMatch(entry.titleWords) {
            return .init(memory: memory, match: match)
        }
        guard query.searchesText else { return nil }

        // The words may be split between the title and the text.
        guard query.isCoveredBy(entry.titleWords + entry.textWords.flatMap { $0 }) else { return nil }
        return .init(memory: memory, match: .text, matchedText: matchedText(entry, query))
    }

    /// The text that shows why the memory was found: the quote when it holds every query word, else the first
    /// telling that does, else the first telling, then the quote, that holds a query word the heading does not show.
    /// A text hit always has such a word in some text, so the nil is not reached for a hit.
    static func matchedText(_ entry: SearchIndex.MemoryEntry, _ query: WordQuery) -> String? {
        let texts = entry.texts, words = entry.textWords
        if query.isCoveredBy(words[0]) { return texts[0] }
        let tellings = Array(texts.indices.dropFirst())
        if let i = tellings.first(where: { query.isCoveredBy(words[$0]) }) { return texts[i] }
        let unshown = Search.unshown(query.words, by: entry.headingWords)
        let touchesUnshown: (Int) -> Bool = { i in unshown.contains { word in words[i].contains { $0.hasPrefix(word) } } }
        if let i = tellings.first(where: touchesUnshown) { return texts[i] }
        return touchesUnshown(0) ? texts[0] : nil
    }
}

// MARK: - Order

private extension SearchResults {
    init(entities: [EntityHit], memories: [MemoryHit], order index: SearchIndex) {
        func group(_ type: EntityType) -> [EntityHit] {
            let hits = entities.filter { $0.summary.entity.type == type }
            // `mostTold` is a total order (moments, title, id); position in it breaks ties inside a match.
            let position = Dictionary(PeopleSort.mostTold.sorted(hits.map(\.summary)).enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            // `sorted` is a permutation of these hits, so every hit has a position: the unwrap cannot fail.
            return hits.sorted { ($0.match, position[$0.id]!) < ($1.match, position[$1.id]!) }
        }
        self.init(people: group(.person), places: group(.place), things: group(.thing), ideas: group(.idea),
                  memories: Self.lifeOrdered(memories, in: index))
    }

    /// By match, then life order (`EntityPage.ordered`), then id.
    static func lifeOrdered(_ hits: [MemoryHit], in index: SearchIndex) -> [MemoryHit] {
        let entries = Dictionary(index.memories.map { ($0.memory.id, $0) }, uniquingKeysWith: { first, _ in first })
        // `ordered` ends on `createdAt`, which can tie. Number the hits by (createdAt, id) and use the
        // number as `createdAt`, so the id decides every tie. The real `createdAt` still stands in for an
        // unknown told-at, and a fact, a feeling or a goal gets no range: it sorts by when it was told only.
        let numbered = hits.map(\.memory).sorted { ($0.createdAt, $0.id.rawValue) < ($1.createdAt, $1.id.rawValue) }
        var toldAt: [MemoryID: Date] = [:]
        var stripped: [Memory] = []
        for (number, memory) in numbered.enumerated() {
            toldAt[memory.id] = entries[memory.id]?.toldAt ?? memory.createdAt
            var copy = memory
            if !memory.isMoment { copy.range = .unplaced }
            copy.createdAt = Date(timeIntervalSince1970: Double(number))
            stripped.append(copy)
        }
        let position = Dictionary(EntityPage.ordered(stripped, toldAt: toldAt).enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        // `ordered` is a permutation of `stripped`, one memory for each hit: the unwrap cannot fail.
        return hits.sorted { ($0.match, position[$0.id]!) < ($1.match, position[$1.id]!) }
    }
}
