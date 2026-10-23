import Foundation

public struct RunReport: Equatable, Sendable {
    public struct Change: Equatable, Sendable {
        public var memoryID: MemoryID
        public var title: String
        public var before: TimeRange
        public var after: TimeRange
    }
    public var placed: Int
    public var floatingCreated: Int
    public var curiosityOpen: Int
    public var changes: [Change]
}

/// Reads the store, runs the pure resolver, writes back only what changed. Called after every
/// accepted memory, after the owner saves a birthday, and by `lifeline resolve --all`.
/// Running it twice in a row writes nothing the second time.
public struct ResolverRunner: Sendable {
    private let store: ExtractionStore
    private let config: ResolverConfig

    public init(store: ExtractionStore, config: ResolverConfig = .default) {
        self.store = store; self.config = config
    }

    @discardableResult
    public func run() throws -> RunReport {
        var memories = try store.memories.allMemories()
        var anchors = try store.memories.allAnchors()
        let chapters = try store.chapters.chapters()
        let birth = try store.profile.ownerBirthDate()

        // Pass 1: find targets that need a floating memory, create them, point the anchors at them.
        var output = Resolver.resolve(try input(memories, anchors, birth, chapters))
        var floatingCreated = 0
        for target in output.floating {
            guard let source = memories.first(where: { $0.id == target.fromMemory }),
                  let span = try store.memories.spans(of: source.id).first else { continue }
            let floating = try store.memories.insertFloating(title: target.phrase, segment: span.segmentID, startMs: span.startMs, endMs: span.endMs)
            floatingCreated += 1
            memories.append(floating)
        }
        for i in anchors.indices where anchors[i].isRelative && anchors[i].targetID == nil {
            guard let phrase = anchors[i].targetText,
                  let target = memories.first(where: { Resolver.matches($0.title, phrase) }) else { continue }
            anchors[i].targetKind = .memory
            anchors[i].targetID = target.id.rawValue
            try store.memories.update(anchors[i])
        }
        if floatingCreated > 0 { output = Resolver.resolve(try input(memories, anchors, birth, chapters)) }

        // Pass 2: write placements, mark anchors, refresh the open questions.
        var changes: [RunReport.Change] = []
        for (id, range) in output.placements {
            guard let memory = memories.first(where: { $0.id == id }) else { continue }
            try store.memories.updateRange(id, range)
            changes.append(RunReport.Change(memoryID: id, title: memory.title, before: memory.range, after: range))
        }
        for var anchor in anchors where output.resolvedAnchorIDs.contains(anchor.id) != anchor.resolved {
            anchor.resolved = output.resolvedAnchorIDs.contains(anchor.id)
            try store.memories.update(anchor)
        }
        let items = output.curiosity.map { draft in
            CuriosityItem(id: .init(), kind: draft.kind, text: draft.text, payoffCount: draft.payoffCount, status: .open,
                          sourceMemoryID: draft.sourceMemoryID,
                          targetMemoryID: draft.targetMemoryID ?? draft.targetPhrase.flatMap { phrase in memories.first { Resolver.matches($0.title, phrase) }?.id })
        }
        try store.curiosity.replaceOpenAnchorItems(items)

        changes.sort { $0.title < $1.title }
        return RunReport(placed: changes.count, floatingCreated: floatingCreated, curiosityOpen: try store.curiosity.open().count, changes: changes)
    }

    private func input(_ memories: [Memory], _ anchors: [Anchor], _ birth: CivilDate?, _ chapters: [Chapter]) throws -> ResolverInput {
        let refs = try memories.map { memory in
            let span = try store.memories.spans(of: memory.id).first
            return MemoryRef(id: memory.id, title: memory.title, range: memory.range,
                             primarySpan: MemoryRef.Span(segmentID: span?.segmentID ?? SegmentID(rawValue: ""), startMs: span?.startMs ?? 0, endMs: span?.endMs ?? 0))
        }
        return ResolverInput(memories: refs, anchors: anchors, birthDate: birth, chapters: chapters, config: config)
    }
}
