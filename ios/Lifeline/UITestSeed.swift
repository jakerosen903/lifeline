import Foundation
import LifelineKit

/// Fixtures written before the first screen, for tests about the shell rather than about recording.
/// Invented content only.
enum UITestSeed {
    static let person = "Maya"
    static let firstYear = 1980
    static let memoryCount = 12

    /// Under `-uiTesting-noOwner`: first open is done but the profile has no owner page. Every path
    /// through first open saves one, so only this reaches the You tab's no-owner state.
    static func writeProfileWithoutOwner(profile: ProfileRepository, store: ExtractionStore) throws {
        try profile.save(Profile(displayName: nil, birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
        if let owner = try profile.owner() { try store.entities.delete(owner.entityID) }
    }

    /// Under `-uiTesting-seedPerson`: the person only, with no session, so the next session is the first
    /// ("Tell another" is offered after a first session).
    static func writePersonOnly(store: ExtractionStore) throws {
        _ = try store.people.insertPerson(displayName: person)
    }

    /// Under `-uiTesting-seed`: one landed session with a segment per memory, each kept as a moment in its own year.
    /// The segments are already sorted, so the worker leaves them alone.
    static func write(sessions: SessionRepository, store: ExtractionStore) throws {
        _ = try store.people.insertPerson(displayName: person)
        let session = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed.m4a", stageLog: "[]", landingChoiceMade: true)
        try sessions.insert(session)
        for index in 0..<memoryCount {
            let year = firstYear + index
            let text = "the summer of \(year) at the lake"
            let segment = Segment(id: .init(), sessionID: session.id, index: index, startMs: index * 5_000, endMs: index * 5_000 + 4_000,
                                  text: text, status: .extracted)
            try sessions.insert(segment, words: [])
            let candidate = Candidate(id: .init(), segmentID: segment.id, extractorVersion: "seed", ordinal: 0, kind: .memory, payload: "{}",
                                      confidence: 1, status: .pending, rejection: nil, createdAt: .now)
            try store.candidates.insert(candidate)
            let memory = Memory(id: .init(), title: "The lake in \(year)", summaryQuote: text, visibility: .timeline, chapterID: nil,
                                createdFromCandidateID: candidate.id, createdAt: .now, range: .year(year, origin: .stated, evidence: "in \(year)"))
            try store.memories.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment.id, startMs: segment.startMs, endMs: segment.endMs, order: 0)],
                                      people: [], places: [], anchors: [], acceptingCandidate: candidate.id)
        }
    }

    /// Under `-uiTesting-seedPeople`: an invented family for the People grid and the entity pages. It saves a
    /// profile, so first open is done. Jordan is the owner; Lena is told about by no moment; the idea
    /// "Saying yes to things" is in two moments with Maya, Dad and Alder Street.
    static func writePeople(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository) throws {
        let birth = Calendar.current.date(from: DateComponents(year: 1990, month: 6, day: 1))
        try profile.save(Profile(displayName: "Jordan", birthDate: birth, birthPlaceText: nil, freeText: nil, updatedAt: .now))
        guard let jordan = try profile.owner()?.entityID else { return }
        let maya = try store.people.insertPerson(displayName: "Maya").entityID
        let dad = try store.people.insertPerson(displayName: "Dad").entityID
        let sam = try store.people.insertPerson(displayName: "Sam").entityID
        _ = try store.people.insertPerson(displayName: "Lena")
        let alder = try store.entities.insert(type: .place, title: "Alder Street").id
        // An idea told in two moments: its page lists "Often with" (it replaced "Beside it").
        let yes = try store.entities.insert(type: .idea, title: "Saying yes to things").id

        let session = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed.m4a", stageLog: "[]", landingChoiceMade: true)
        try sessions.insert(session)
        var index = 0
        let start = Date.now
        func keep(_ title: String, kind: MemoryKind, year: Int?, relation: EntityRelation, quote: String? = nil, links: [(EntityID, String?)]) throws {
            let text = quote ?? "\(title), as told"
            let segment = Segment(id: .init(), sessionID: session.id, index: index, startMs: index * 5_000, endMs: index * 5_000 + 4_000,
                                  text: text, status: .extracted)
            // A second apart, so "oldest told first" has one answer.
            let told = start.addingTimeInterval(Double(index))
            index += 1
            try sessions.insert(segment, words: [])
            let candidate = Candidate(id: .init(), segmentID: segment.id, extractorVersion: "seed", ordinal: 0, kind: .memory, payload: "{}",
                                      confidence: 1, status: .pending, rejection: nil, createdAt: .now)
            try store.candidates.insert(candidate)
            let range = year.map { TimeRange.year($0, origin: .stated, evidence: "in \($0)") } ?? .unplaced
            let memory = Memory(id: .init(), title: title, summaryQuote: text, visibility: .timeline, chapterID: nil,
                                createdFromCandidateID: candidate.id, createdAt: told, range: range, kind: kind)
            try store.memories.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment.id, startMs: segment.startMs, endMs: segment.endMs, order: 0)],
                                      people: [], places: [],
                                      links: links.map { MomentEntity(memoryID: memory.id, entityID: $0.0, relation: relation, roleText: $0.1) },
                                      anchors: [], acceptingCandidate: candidate.id)
        }
        try keep("The tree house", kind: .event, year: 1999, relation: .mention,
                 links: [(maya, "my sister"), (dad, "my dad"), (alder, nil), (jordan, nil), (yes, nil)])
        try keep("Learning to swim", kind: .event, year: 2000, relation: .mention,
                 links: [(maya, "my sister"), (dad, "my dad"), (alder, nil), (jordan, nil), (yes, nil)])
        try keep("The science fair", kind: .event, year: 2001, relation: .mention, links: [(maya, nil), (dad, "my dad")])
        try keep("Maya's graduation", kind: .event, year: 2003, relation: .mention, links: [(maya, nil)])
        try keep("Moving into Hemenway Street", kind: .event, year: 2012, relation: .mention, links: [(sam, "my roommate")])
        try keep("Two years younger than me", kind: .fact, year: nil, relation: .detail,
                 quote: "um, two years younger than me, you know", links: [(maya, nil)])
        try keep("The brave one", kind: .fact, year: nil, relation: .detail,
                 quote: "she was always the the brave one", links: [(maya, nil)])
        try keep("The futon", kind: .fact, year: nil, relation: .detail,
                 quote: "we shared that terrible futon for most of 2012", links: [(sam, nil)])
    }
}
