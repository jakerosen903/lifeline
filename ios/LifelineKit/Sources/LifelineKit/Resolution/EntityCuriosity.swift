import Foundation

/// Pure (M7): one scene question per entity that has no moment yet. Each asks for a scene,
/// never for a date and never for an opinion (Principles 1 and 2). A Thing or a Place is never
/// asked for its dates; the person adds those from its page if they want.
public enum EntityCuriosity {
    public static func question(for entity: Entity) -> (CuriosityKind, String) {
        switch entity.type {
        case .place, .thing: (.entityWithoutMoment, "What do you remember first about \(entity.title)?")
        case .person: (.personWithoutMoment, "Is there one time with \(entity.title) that stands out?")
        case .idea: (.ideaWithoutMoment, "Is there a moment that brought that to mind?")
        }
    }

    /// `memories` must hold every linked memory. A place or thing asks only once it has a detail
    /// (something was said about it); a person or an idea asks as soon as it has no moment. The
    /// owner, hidden and excluded entities never ask. Payoff 1: an entity question can lead an
    /// opening but never outranks a dated question.
    public static func drafts(entities: [Entity], links: [MomentEntity], memories: [MemoryID: Memory], owner: EntityID?) -> [CuriosityItem] {
        let byEntity = Dictionary(grouping: links, by: \.entityID)
        return entities.compactMap { entity in
            guard entity.id != owner, !entity.hiddenFromTimeline, !entity.excludedFromAI else { return nil }
            let linked = byEntity[entity.id] ?? []
            let hasMoment = linked.contains { $0.relation == .mention && memories[$0.memoryID]?.isMoment == true }
            guard !hasMoment else { return nil }
            if entity.type == .place || entity.type == .thing, !linked.contains(where: { $0.relation == .detail }) { return nil }
            let (kind, text) = question(for: entity)
            return CuriosityItem(id: .init(), kind: kind, text: text, payoffCount: 1, status: .open, sourceMemoryID: nil, targetMemoryID: nil, entityID: entity.id)
        }
    }
}
