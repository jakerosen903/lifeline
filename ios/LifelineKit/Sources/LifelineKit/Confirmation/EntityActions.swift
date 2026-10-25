import Foundation

/// Entity cards and details (M7): "Sounds like a thing you had" accepted as any of the four
/// types, "Not any of these", and a detail moved between entities from the Change sheet.
extension CandidateActions {
    /// Keep on an entity card, as the type the person chose ("It's a place" is one tap). Reuses an
    /// entity of that type and title, links every kept memory of the segment that names it, and
    /// gives it a first telling to play. A person goes through the people tables.
    @discardableResult
    public func acceptEntity(_ candidate: Candidate, as type: EntityType? = nil) throws -> Entity {
        guard candidate.kind == .entity else { throw Error.wrongKind }
        try requirePending(candidate)
        guard let mention = CandidatePayload.mention(candidate) else { throw Error.badPayload }
        let chosen = type ?? mention.kind.entityType
        let entity: Entity
        if chosen == .person {
            let person = try store.people.findPerson(matching: mention.text) ?? store.people.insertPerson(displayName: mention.text)
            entity = try store.entities.entity(id: person.entityID) ?? Entity(id: person.entityID, type: .person, title: person.displayName)
        } else if chosen == .idea || type == nil {
            entity = try createEntity(from: mention, candidate: candidate, as: chosen)
        } else {
            entity = try store.entities.insert(type: chosen, title: mention.text, candidate: candidate.id)
        }

        var firstSpan: MemorySpan?
        for memory in try store.memories.memories(fromSegment: candidate.segmentID) {
            guard let card = memory.createdFromCandidateID.flatMap({ try? store.candidates.fetch($0) }).flatMap(CandidatePayload.memory) else { continue }
            let names = card.allEntityRefs.contains { Self.same($0.text, mention.text) }
            let about = mention.ref != nil && card.aboutRef == mention.ref && !memory.isMoment
            guard names || about else { continue }
            try store.entities.link(memory.id, entity.id, relation: about ? .detail : .mention, roleText: about ? nil : mention.text)
            if firstSpan == nil { firstSpan = try store.memories.spans(of: memory.id).first }
        }
        if try store.entities.spans(of: entity.id).isEmpty {
            if let span = firstSpan {
                try store.entities.insertSpan(EntitySpan(entityID: entity.id, segmentID: span.segmentID, startMs: span.startMs, endMs: span.endMs, order: 0))
            } else if let segment = try store.sessions.fetchSegment(candidate.segmentID) {
                try store.entities.insertSpan(EntitySpan(entityID: entity.id, segmentID: segment.id, startMs: segment.startMs, endMs: segment.endMs, order: 0))
            }
        }
        try store.candidates.setStatus(candidate.id, .accepted)
        return try store.entities.entity(id: entity.id) ?? entity
    }

    /// "Not any of these": the card goes; nothing is created. A dismissed card can come back.
    public func notAnEntity(_ candidate: Candidate) throws {
        guard candidate.kind == .entity else { throw Error.wrongKind }
        try dismiss(candidate)
    }

    /// "About whom or what?" on the Change sheet: the detail leaves the entity it was on and
    /// lands on `entity`; nil leaves it under About. Only a fact, feeling or goal is a detail.
    public func moveDetail(_ memory: MemoryID, to entity: EntityID?) throws {
        guard let row = try store.memories.fetch(memory), !row.isMoment else { throw Error.wrongKind }
        for link in try store.entities.links(of: memory).map(\.link) where link.relation == .detail {
            try store.entities.unlink(memory, link.entityID, relation: .detail)
        }
        if let entity { try store.entities.link(memory, entity, relation: .detail) }
    }
}
