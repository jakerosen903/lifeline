import Foundation

extension ExtractionStore {
    /// What search may find (decision 6): every visible person, place, thing and idea but the owner, and every told,
    /// visible memory with the words of its tellings. A fixed number of statements, whatever the archive's size.
    /// Nothing hidden, no floating stand-in and no word outside a memory's own spans enters the index.
    public func searchIndex() throws -> SearchIndex {
        let ownerEntity = try profile.owner()?.entityID
        let aliases = try people.allAliases()
        var entries: [SearchIndex.EntityEntry] = []
        for type in EntityType.allCases {
            for summary in try entities.summaries(type: type) where summary.entity.id != ownerEntity {
                entries.append(SearchIndex.EntityEntry(summary: summary, aliases: Self.otherNames(aliases[summary.entity.id] ?? [], than: summary.entity.title)))
            }
        }

        let told = try memories.firstTellings(kinds: Set(MemoryKind.allCases))
        let words = try memories.tellingWords()
        let moments = try memories.visibleMemories().filter { !$0.isFloating }.map { memory in
            SearchIndex.MemoryEntry(memory: memory, tellings: words[memory.id] ?? [], toldAt: told[memory.id]?.toldAt)
        }
        return SearchIndex(entities: entries, memories: moments)
    }

    /// The alias equal to the title (by fold) says nothing new. An old spelling stays, so the old name still finds the person.
    private static func otherNames(_ aliases: [String], than title: String) -> [String] {
        let own = SearchFold.fold(title)
        return aliases.filter { SearchFold.fold($0) != own }
    }
}
