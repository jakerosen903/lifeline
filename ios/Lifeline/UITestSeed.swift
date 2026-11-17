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
        _ = try people(store: store, profile: profile, sessions: sessions)
    }

    /// Under `-uiTesting-seedPortrait`: the family, then Jordan's own facts, feelings and a goal for the You tab,
    /// told in the same session after the family's. One fact is hidden; one quote is only filler; Maya's and
    /// Sam's facts stay on their pages.
    static func writePortrait(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository) throws {
        guard var seed = try people(store: store, profile: profile, sessions: sessions), let jordan = try profile.owner()?.entityID else { return }
        if var saved = try profile.fetch() {
            saved.birthPlaceText = "Dayton"
            try profile.save(saved)
        }
        let lake = try store.entities.insert(type: .place, title: "The lake").id
        try seed.keep("Took things apart", kind: .fact, quote: "um, I was always the kid who took things apart", links: [(jordan, nil)])
        let oldest = try seed.keep("The oldest of two", kind: .fact, quote: "I'm the oldest of two", links: [(jordan, nil)])
        try store.tags.tag(.memory, oldest.rawValue, "Family")
        let still = try seed.keep("Never sat still", kind: .fact, quote: "I never could sit still in a classroom", links: [])
        try store.tags.tag(.memory, still.rawValue, "School")
        let light = try seed.keep("The hall light", kind: .fact, quote: "I still sleep with the hall light on", links: [])
        try store.memories.setHidden(light, true)
        try seed.keep("Something about Ohio", kind: .fact, quote: "um, uh", links: [])
        try seed.keep("Leaving Boston", kind: .feeling, quote: "leaving Boston felt like closing a book before the last chapter", links: [])
        try seed.keep("Never scared at the lake", kind: .feeling, quote: "I was never scared at the lake, not once", links: [(lake, nil)])
        try seed.keep("Lisbon", kind: .goal, quote: "I want to take Maya to Lisbon someday", links: [])
        // "Saying yes to things" has spans (its moments), so it plays; this idea has none, so it shows no control.
        // It sorts after "Saying yes to things" by title, so `entities.row` firstMatch stays the same.
        _ = try store.entities.insert(type: .idea, title: "Telling the truth")
    }

    /// Under `-uiTesting-seedTaggedMoment`, after a seed that has "Maya's graduation": exactly one moment carries a
    /// tag ("Graduations"). It is a separate flag so the seeds other tests count on keep their tags as they are.
    static func tagOneMoment(store: ExtractionStore) throws {
        guard let moment = try store.memories.allMemories().first(where: { $0.title == "Maya's graduation" }) else { return }
        try store.tags.tag(.memory, moment.id.rawValue, "Graduations")
    }

    /// Under `-uiTesting-seedPhotos`: the family, then generated photos added through the library as a pick would add them.
    /// Maya has two (a dated landscape cover, then an undated portrait), "The tree house" one, Jordan one.
    /// Dad, Sam and Lena have none. Solid colours with a circle; never a real photo.
    static func writePhotos(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository, library: PhotoLibrary) throws {
        try writePeople(store: store, profile: profile, sessions: sessions)
        guard let jordan = try profile.owner()?.entityID,
              let maya = try store.entities.entities(type: .person).first(where: { $0.title == person })?.id,
              let treeHouse = try store.memories.allMemories().first(where: { $0.title == "The tree house" })?.id else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "seed-photos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A memory dated by a photo, for the page that says so. No links: it sits on the timeline only.
        var beach = SeedSession(session: Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed-beach.m4a", stageLog: "[]", landingChoiceMade: true),
                                store: store, sessions: sessions)
        try sessions.insert(beach.session)
        if let day = CivilDate(year: 2012, month: 6, day: 14) {
            try beach.keep("The beach", kind: .event, range: .fromPhoto(day), links: [])
        }
        let photos: [(subject: PhotoSubject, width: Int, height: Int, rgb: Int, takenAt: String?, gps: (lat: Double, lon: Double)?)] = [
            (.entity(maya), 1600, 1200, 0xC8893F, "2012:06:14 15:32:10", (0.5, -30.0)),
            (.entity(maya), 1200, 1600, 0x5F7046, nil, nil),
            (.memory(treeHouse), 1600, 1200, 0xECE3D2, "1999:07:04 10:00:00", nil),
            (.entity(jordan), 1600, 1200, 0x8F5A1C, nil, nil),
        ]
        for (index, photo) in photos.enumerated() {
            let file = folder.appending(path: "seed-\(index).jpg")
            try GeneratedPhoto.write(to: file, width: photo.width, height: photo.height, rgb: photo.rgb, takenAt: photo.takenAt, gps: photo.gps)
            let subject = photo.subject
            try waitFor { _ = try await library.add(fileAt: file, assetLocalID: nil, to: subject) }
        }
    }

    /// The seed runs before the first screen, from a synchronous launch. The library is an actor off the main
    /// thread, so blocking here cannot deadlock it. Under UI testing only.
    private static func waitFor(_ work: @escaping @Sendable () async throws -> Void) throws {
        let done = DispatchSemaphore(value: 0)
        let failure = FailureBox()
        Task.detached {
            do { try await work() } catch { failure.set(error) }
            done.signal()
        }
        done.wait()
        if let error = failure.get() { throw error }
    }

    /// The family behind `writePeople`, and the session it was told in, for a seed that tells more after it.
    private static func people(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository) throws -> SeedSession? {
        let birth = Calendar.current.date(from: DateComponents(year: 1990, month: 6, day: 1))
        try profile.save(Profile(displayName: "Jordan", birthDate: birth, birthPlaceText: nil, freeText: nil, updatedAt: .now))
        guard let jordan = try profile.owner()?.entityID else { return nil }
        let maya = try store.people.insertPerson(displayName: "Maya").entityID
        let dad = try store.people.insertPerson(displayName: "Dad").entityID
        let sam = try store.people.insertPerson(displayName: "Sam").entityID
        _ = try store.people.insertPerson(displayName: "Lena")
        let alder = try store.entities.insert(type: .place, title: "Alder Street").id
        // An idea told in two moments: its page lists "Often with" (it replaced "Beside it").
        let yes = try store.entities.insert(type: .idea, title: "Saying yes to things").id

        let session = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed.m4a", stageLog: "[]", landingChoiceMade: true)
        try sessions.insert(session)
        var seed = SeedSession(session: session, store: store, sessions: sessions)
        try seed.keep("The tree house", kind: .event, year: 1999, relation: .mention,
                      links: [(maya, "my sister"), (dad, "my dad"), (alder, nil), (jordan, nil), (yes, nil)])
        try seed.keep("Learning to swim", kind: .event, year: 2000, relation: .mention,
                      links: [(maya, "my sister"), (dad, "my dad"), (alder, nil), (jordan, nil), (yes, nil)])
        try seed.keep("The science fair", kind: .event, year: 2001, relation: .mention, links: [(maya, nil), (dad, "my dad")])
        try seed.keep("Maya's graduation", kind: .event, year: 2003, relation: .mention, links: [(maya, nil)])
        try seed.keep("Moving into Hemenway Street", kind: .event, year: 2012, relation: .mention, links: [(sam, "my roommate")])
        try seed.keep("Two years younger than me", kind: .fact,
                      quote: "um, two years younger than me, you know", links: [(maya, nil)])
        try seed.keep("The brave one", kind: .fact,
                      quote: "she was always the the brave one", links: [(maya, nil)])
        try seed.keep("The futon", kind: .fact,
                      quote: "we shared that terrible futon for most of 2012", links: [(sam, nil)])
        return seed
    }
}

/// The error a detached seed step threw, read back on the waiting thread.
private final class FailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: (any Error)?
    func set(_ error: any Error) { lock.withLock { self.error = error } }
    func get() -> (any Error)? { lock.withLock { error } }
}

/// One seeded session (`seed.m4a`, never written): each `keep` adds a segment of 4 000 ms and keeps one memory on it.
private struct SeedSession {
    let session: Session
    let store: ExtractionStore
    let sessions: SessionRepository
    let start = Date.now
    var index = 0

    @discardableResult
    mutating func keep(_ title: String, kind: MemoryKind, year: Int? = nil, range dated: TimeRange? = nil, relation: EntityRelation = .detail, quote: String? = nil,
                       links: [(EntityID, String?)]) throws -> MemoryID {
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
        let range = dated ?? year.map { TimeRange.year($0, origin: .stated, evidence: "in \($0)") } ?? .unplaced
        let memory = Memory(id: .init(), title: title, summaryQuote: text, visibility: .timeline, chapterID: nil,
                            createdFromCandidateID: candidate.id, createdAt: told, range: range, kind: kind)
        try store.memories.insert(memory, spans: [MemorySpan(memoryID: memory.id, segmentID: segment.id, startMs: segment.startMs, endMs: segment.endMs, order: 0)],
                                  people: [], places: [],
                                  links: links.map { MomentEntity(memoryID: memory.id, entityID: $0.0, relation: relation, roleText: $0.1) },
                                  anchors: [], acceptingCandidate: candidate.id)
        return memory.id
    }
}
