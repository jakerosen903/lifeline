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

    /// Under `-uiTesting-seedThings`: Jordan, born 1990-06-01, and things for the Things shelf, all told in one session.
    /// Placed by stated years: "The red bike" (1999 and 2004; a key photo), "Dad's Volvo" (2001; a detail with a quote).
    /// "The piano" has no moment, only a stated span (1996 to 2002). "The radiator" is placed by a guess (2012, inferred)
    /// and its only detail is hidden. Not placed: "Grandpa's watch" (an undated moment; a key photo whose file is gone),
    /// "The guitar" (a detail only), "The blue kite" (its only moment hidden) and a long-titled armchair (undated).
    /// "The shoebox" is hidden. With `undatedOnly` (`-uiTesting-thingsUndatedOnly`): the watch, without its photo, and the guitar.
    static func writeThings(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository, library: PhotoLibrary,
                            photosDirectory: URL, undatedOnly: Bool) throws {
        let birth = Calendar.current.date(from: DateComponents(year: 1990, month: 6, day: 1))
        try profile.save(Profile(displayName: "Jordan", birthDate: birth, birthPlaceText: nil, freeText: nil, updatedAt: .now))
        let session = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed.m4a", stageLog: "[]", landingChoiceMade: true)
        try sessions.insert(session)
        var seed = SeedSession(session: session, store: store, sessions: sessions)
        let folder = FileManager.default.temporaryDirectory.appending(path: "seed-things-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func thing(_ title: String) throws -> EntityID { try store.entities.insert(type: .thing, title: title).id }

        let watch = try thing("Grandpa's watch")
        try seed.keep("Grandpa's last visit", kind: .event, relation: .mention, links: [(watch, nil)])
        let guitar = try thing("The guitar")
        try seed.keep("Three chords", kind: .fact, quote: "I never learned more than three chords", links: [(guitar, nil)])
        if undatedOnly { return }

        // A key photo that cannot load: it is stored, then its file is removed.
        let gone = try addPhoto(library, in: folder, named: "watch", rgb: 0x5F7046, to: watch)
        try FileManager.default.removeItem(at: photosDirectory.appending(path: gone.fileName))

        let bike = try thing("The red bike")
        try seed.keep("Riding to the quarry", kind: .event, year: 1999, relation: .mention, links: [(bike, nil)])
        try seed.keep("Selling the red bike", kind: .event, year: 2004, relation: .mention, links: [(bike, nil)])
        _ = try addPhoto(library, in: folder, named: "bike", rgb: 0xC8893F, to: bike)

        let volvo = try thing("Dad's Volvo")
        try seed.keep("The drive to Dayton", kind: .event, year: 2001, relation: .mention, links: [(volvo, nil)])
        try seed.keep("The smell of the Volvo", kind: .fact, quote: "um, it smelled like oranges and wet dog", links: [(volvo, nil)])

        // "Add dates" writes a stated span: settled, so it never reads as a guess.
        let piano = try thing("The piano")
        try store.entities.setStatedSpan(piano, .stated(between: 1996, and: 2002))

        let radiator = try thing("The radiator")
        let cold = try seed.keep("The cold flat", kind: .event, relation: .mention, links: [(radiator, nil)])
        try store.memories.updateRange(cold, .year(2012, origin: .inferred, evidence: "when I was 22"))
        let clank = try seed.keep("The clanking radiator", kind: .fact, quote: "he clanked all night", links: [(radiator, nil)])
        try store.memories.setHidden(clank, true)

        let kite = try thing("The blue kite")
        let tree = try seed.keep("The kite in the tree", kind: .event, year: 2000, relation: .mention, links: [(kite, nil)])
        try store.memories.setHidden(tree, true)

        let chair = try thing("The enormous green armchair that came with the flat on Hemenway Street")
        try seed.keep("Carrying the armchair upstairs", kind: .event, relation: .mention, links: [(chair, nil)])

        let shoebox = try thing("The shoebox")
        try seed.keep("The shoebox under the bed", kind: .event, year: 1999, relation: .mention, links: [(shoebox, nil)])
        try store.entities.setHidden(shoebox, true)
    }

    /// A generated photo (a solid colour with a circle), added to a thing's page as a pick would add it.
    private static func addPhoto(_ library: PhotoLibrary, in folder: URL, named name: String, rgb: Int, to thing: EntityID) throws -> Photo {
        let file = folder.appending(path: "\(name).jpg")
        try GeneratedPhoto.write(to: file, width: 1600, height: 1200, rgb: rgb, takenAt: nil, gps: nil)
        let box = PhotoBox()
        try waitFor { box.set(try await library.add(fileAt: file, assetLocalID: nil, to: .entity(thing))) }
        guard let photo = box.get() else { throw CocoaError(.fileReadUnknown) }
        return photo
    }

    /// Under `-uiTesting-seedPhotoStory`: the family, then two landed photo sessions, each about a generated photo.
    /// The first (two moments, told 2 hours ago) is about a dated photo (14 June 2012) and has two kept memories that both hold it:
    /// "The beach" (unplaced; names Maya and Dad) and "The drive home" (stated 2012; names Dad). The real Keep write puts the photo
    /// on Maya's and Dad's pages by a story link. The second (newer, one sorted moment) has no kept memory, and its photo has no other home.
    /// `unlanded` leaves one of them with no landing choice made, so the app opens on its landing (`-uiTesting-photoStoryLanding`).
    /// `withGuess` (`-uiTesting-photoStoryGuess`) adds a third kept memory to the first story: "The picnic", which names Maya and
    /// Alder Street, holds the photo, and has a guessed date from the age anchor "when I was 22" (the band holds 14 June 2012).
    /// `assumedName` (`-uiTesting-photoStoryAssumedName`) adds "The ferry" (stated 2012) to the first story: it names Sam by a
    /// guess (assumed, said "Sammy"), so Keep puts the photo on Sam's page, and a move of the name moves it.
    enum PhotoStoryLanding: String { case first, second }

    static func writePhotoStory(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository, library: PhotoLibrary,
                                unlanded: PhotoStoryLanding?, withGuess: Bool = false, assumedName: Bool = false) throws {
        guard try people(store: store, profile: profile, sessions: sessions) != nil,
              let maya = try store.entities.entities(type: .person).first(where: { $0.title == person })?.id,
              let dad = try store.entities.entities(type: .person).first(where: { $0.title == "Dad" })?.id,
              let sam = try store.entities.entities(type: .person).first(where: { $0.title == "Sam" })?.id,
              let alder = try store.entities.entities(type: .place).first(where: { $0.title == "Alder Street" })?.id else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "seed-photo-story-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // The first story. The photo is stored with no link, as a pick stores it; the session row then points at it.
        let beachPhoto = try storePhoto(library, in: folder, named: "story-beach", rgb: 0xC8893F, takenAt: "2012:06:14 15:32:10")
        let first = Session(id: .init(), startedAt: .now.addingTimeInterval(-7_200), endedAt: .now.addingTimeInterval(-7_100), audioPath: "seed-story-1.m4a",
                            stageLog: "[]", landingChoiceMade: unlanded != .first, subjectPhotoID: beachPhoto.id, startedFrom: .photo)
        try sessions.insert(first)
        var seed = SeedSession(session: first, store: store, sessions: sessions)
        let beach = try seed.keep("The beach", kind: .event, relation: .mention, links: [(maya, nil), (dad, "my dad")])
        let drive = try seed.keep("The drive home", kind: .event, year: 2012, relation: .mention, links: [(dad, "my dad")])
        try store.photos.link(beachPhoto.id, to: .memory(beach))
        try store.photos.link(beachPhoto.id, to: .memory(drive))
        // No hand link to Maya's page: it would make the story's link the owner's (plan decision 13).
        if assumedName {
            try seed.keep("The ferry", kind: .event, year: 2012, relation: .mention, links: [(sam, "Sammy")], origins: [sam: .assumed])
        }
        // The range is the one the resolver gives this anchor, so a resolver run (after Undo) puts back the same range.
        // `people` saved Jordan's birthday, so the birth date is there; the second story is written either way.
        let phrase = "when I was 22"
        if withGuess, let birth = try profile.ownerBirthDate(), let age = AnchorPhrase.parseAge(phrase, value: "22") {
            var guess = TimeRange.stated(age: age, birth: birth, evidence: phrase)
            guess.origin = .inferred
            let picnic = try seed.keep("The picnic", kind: .event, range: guess, relation: .mention, links: [(maya, nil), (alder, nil)],
                                       ageAnchor: (phrase: phrase, value: "22"))
            try store.photos.link(beachPhoto.id, to: .memory(picnic))
        }

        // The second story: one sorted moment, no memory kept, and a photo nothing else holds.
        let lonePhoto = try storePhoto(library, in: folder, named: "story-lone", rgb: 0x5F7046, takenAt: nil)
        let second = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed-story-2.m4a", stageLog: "[]",
                             landingChoiceMade: unlanded != .second, subjectPhotoID: lonePhoto.id, startedFrom: .photo)
        try sessions.insert(second)
        try sessions.insert(Segment(id: .init(), sessionID: second.id, index: 0, startMs: 0, endMs: 4_000, text: "the long way round, as told", status: .extracted), words: [])
    }

    private static func storePhoto(_ library: PhotoLibrary, in folder: URL, named name: String, rgb: Int, takenAt: String?) throws -> Photo {
        let file = folder.appending(path: "\(name).jpg")
        try GeneratedPhoto.write(to: file, width: 1600, height: 1200, rgb: rgb, takenAt: takenAt, gps: nil)
        let box = PhotoBox()
        try waitFor { box.set(try await library.store(fileAt: file, assetLocalID: nil)) }
        guard let photo = box.get() else { throw CocoaError(.fileReadUnknown) }
        return photo
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

    /// Under `-uiTesting-seedDuplicates`: what the launch repair is for. Three stories whose titles differ only
    /// in case and a full stop, with one moment each, and one chapter with no title and no memory. It saves a
    /// profile, so first open is done.
    static func writeDuplicates(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository) throws {
        try profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
        let session = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed.m4a", stageLog: "[]", landingChoiceMade: true)
        try sessions.insert(session)
        var seed = SeedSession(session: session, store: store, sessions: sessions)
        let copies = [("The road trip", "Leaving before dawn"), ("the road trip", "The flat tyre in Nebraska"), ("The road trip.", "The motel with the neon cactus")]
        for (story, moment) in copies {
            let memory = try seed.keep(moment, kind: .event, year: 2009, links: [])
            try store.stories.add(memory: memory, to: try store.stories.insert(title: story, chapterID: nil).id)
        }
        _ = try store.chapters.insertChapter(title: nil)
    }

    /// Under `-uiTesting-seedSpine`: Jordan, born 1990, with six dated moments on the Timeline's spine and one undated.
    /// Gaps between them are 1, 1, 2, 3 and 2 years, so exactly one gap names itself ("3 years"). "The tree house" is
    /// inferred (1999) and sits in the chapter "Maple Street"; "The science fair" sits in a chapter with no title.
    static func writeSpine(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository) throws {
        let birth = Calendar.current.date(from: DateComponents(year: 1990, month: 6, day: 1))
        try profile.save(Profile(displayName: "Jordan", birthDate: birth, birthPlaceText: nil, freeText: nil, updatedAt: .now))
        let session = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed.m4a", stageLog: "[]", landingChoiceMade: true)
        try sessions.insert(session)
        var seed = SeedSession(session: session, store: store, sessions: sessions)
        let treeHouse = try seed.keep("The tree house", kind: .event, links: [])
        let swim = try seed.keep("Learning to swim", kind: .event, links: [])
        let fair = try seed.keep("The science fair", kind: .event, links: [])
        let graduation = try seed.keep("Maya's graduation", kind: .event, links: [])
        let gig = try seed.keep("The first gig", kind: .event, links: [])
        let apartment = try seed.keep("The first apartment", kind: .event, links: [])
        try seed.keep("The blue kite", kind: .event, links: [])
        try store.memories.updateRange(treeHouse, .year(1999, origin: .inferred, evidence: "when I was nine"))
        try store.memories.updateRange(swim, .stated(year: 2000))
        try store.memories.updateRange(fair, .stated(year: 2001))
        try store.memories.updateRange(graduation, .stated(year: 2003))
        try store.memories.updateRange(gig, .stated(year: 2006))
        try store.memories.updateRange(apartment, .stated(between: 2008, and: 2010))
        let maple = try store.chapters.insertChapter(title: "Maple Street")
        try store.chapters.assign(memory: treeHouse, toChapter: maple.id)
        let untitled = try store.chapters.insertChapter(title: nil)
        try store.chapters.assign(memory: fair, toChapter: untitled.id)
    }

    /// Under `-uiTesting-seedGuesses`: links that Keep guessed, for the "Who is this?" sheet and the marks. Jordan is
    /// the owner. An earlier session holds Robin Okafor's two older moments (links with no origin) and Priya's one
    /// moment: the guess made Priya and links her as an assumed "Priya", so a move from her page removes her. The
    /// latest session keeps "The flat on Alder Street" and "The night the boiler went" (Robin Okafor, assumed, said
    /// "Robin") and "Dinner on the deposit" (Tomas, whom the guess made, origin `new`; Danielle, said "my sister").
    /// With `landingOpen` the latest session has no landing choice yet, so its landing opens at launch.
    static func writeGuesses(store: ExtractionStore, profile: ProfileRepository, sessions: SessionRepository, landingOpen: Bool) throws {
        try profile.save(Profile(displayName: "Jordan", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
        let robin = try store.people.insertPerson(displayName: "Robin Okafor").entityID
        try store.people.addAlias("Robin", to: PersonID(rawValue: robin.rawValue))
        let danielle = try store.people.insertPerson(displayName: "Danielle").entityID
        try store.people.addAlias("my sister", to: PersonID(rawValue: danielle.rawValue))
        let priya = guessedPerson("Priya"), tomas = guessedPerson("Tomas")

        let earlier = Session(id: .init(), startedAt: .now.addingTimeInterval(-86_400), endedAt: .now.addingTimeInterval(-86_000),
                              audioPath: "seed-earlier.m4a", stageLog: "[]", landingChoiceMade: true)
        try sessions.insert(earlier)
        var older = SeedSession(session: earlier, store: store, sessions: sessions, start: earlier.startedAt)
        try older.keep("Robin's first car", kind: .event, year: 2004, relation: .mention, links: [(robin, nil)])
        try older.keep("The summer at the cannery", kind: .event, year: 2006, relation: .mention, links: [(robin, nil)])
        try older.keep("The bike ride to the coast", kind: .event, year: 2009, relation: .mention, links: [(priya.entity.id, "Priya")],
                       origins: [priya.entity.id: .assumed], plan: priya.plan)

        let latest = Session(id: .init(), startedAt: .now, endedAt: .now, audioPath: "seed.m4a", stageLog: "[]", landingChoiceMade: !landingOpen)
        try sessions.insert(latest)
        var seed = SeedSession(session: latest, store: store, sessions: sessions)
        try seed.keep("The flat on Alder Street", kind: .event, year: 2011, relation: .mention, links: [(robin, "Robin")], origins: [robin: .assumed])
        try seed.keep("The night the boiler went", kind: .event, year: 2012, relation: .mention, links: [(robin, "Robin")], origins: [robin: .assumed])
        try seed.keep("Dinner on the deposit", kind: .event, year: 2012, relation: .mention, links: [(tomas.entity.id, "Tomas"), (danielle, "my sister")],
                       origins: [tomas.entity.id: .new, danielle: .said], plan: tomas.plan)
    }

    /// A person the guess made (`created_by_guess`), written with the first moment that links them, as Keep writes one
    /// (the plan also gives them their name as an alias).
    private static func guessedPerson(_ name: String) -> (entity: Entity, plan: EntityRepository.Write) {
        let person = Person(id: .init(), displayName: name, notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil,
                            nameOrigin: .said, createdByGuess: true)
        let entity = Entity(id: person.entityID, type: .person, title: name)
        var plan = EntityRepository.Write()
        plan.entities = [entity]
        plan.persons = [person]
        return (entity, plan)
    }
}

/// The error a detached seed step threw, read back on the waiting thread.
private final class FailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: (any Error)?
    func set(_ error: any Error) { lock.withLock { self.error = error } }
    func get() -> (any Error)? { lock.withLock { error } }
}

/// The photo a detached seed step stored, read back on the waiting thread.
private final class PhotoBox: @unchecked Sendable {
    private let lock = NSLock()
    private var photo: Photo?
    func set(_ photo: Photo) { lock.withLock { self.photo = photo } }
    func get() -> Photo? { lock.withLock { photo } }
}

/// One seeded session (`seed.m4a`, never written): each `keep` adds a segment of 4 000 ms and keeps one memory on it.
private struct SeedSession {
    let session: Session
    let store: ExtractionStore
    let sessions: SessionRepository
    var start = Date.now
    var index = 0

    /// `ageAnchor` stores one resolved age anchor ("when I was 22") on the memory, so the resolver keeps its guessed range.
    /// `origins` gives a link its origin (none: a link older than v15). `plan` writes the people a link needs first.
    @discardableResult
    mutating func keep(_ title: String, kind: MemoryKind, year: Int? = nil, range dated: TimeRange? = nil, relation: EntityRelation = .detail, quote: String? = nil,
                       links: [(EntityID, String?)], origins: [EntityID: LinkOrigin] = [:], plan: EntityRepository.Write = .init(),
                       ageAnchor: (phrase: String, value: String)? = nil) throws -> MemoryID {
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
                                  links: links.map { MomentEntity(memoryID: memory.id, entityID: $0.0, relation: relation, roleText: $0.1, origin: origins[$0.0]) },
                                  entities: plan,
                                  anchors: ageAnchor.map { [Anchor(id: .init(), memoryID: memory.id, phrase: $0.phrase, relation: .age, targetKind: .none,
                                                                   targetID: nil, value: $0.value, resolved: true)] } ?? [],
                                  acceptingCandidate: candidate.id)
        return memory.id
    }
}

// MARK: - Contacts (PC-b)

extension UITestSeed {
    /// The scripted phone's contacts, invented. Tests that need more cards add them here.
    /// - "Robyn Okafor" goes by "Robin", so she fits the guessed "Robin" of `-uiTesting-seedGuesses` (a contact row in its sheet).
    /// - "Dara Quinn" is the one contact that fits "Dara" of `-uiTesting-followUps`, so Keep makes her from the contact.
    ///   She has a picture, so a test sees it copied after Keep (I-2).
    static let contactCards: [ContactCard] = [
        ContactCard(identifier: "ui-contact-vale", fullName: "Robyn Vale", givenName: "Robyn", familyName: "Vale", nickname: "", hasPicture: true),
        ContactCard(identifier: "ui-contact-reyes", fullName: "Tomas Reyes", givenName: "Tomas", familyName: "Reyes", nickname: "", hasPicture: false),
        ContactCard(identifier: "ui-contact-okafor", fullName: "Robyn Okafor", givenName: "Robyn", familyName: "Okafor", nickname: "Robin", hasPicture: false),
        ContactCard(identifier: "ui-contact-quinn", fullName: "Dara Quinn", givenName: "Dara", familyName: "Quinn", nickname: "", hasPicture: true),
    ]

    /// Under `-uiTesting-seedContactLink`, after `-uiTesting-seedPeople`: Lena is linked to "Robyn Okafor", as a restore to
    /// a new phone leaves a person whose contact the app has not been allowed to see yet. The card has no picture.
    static func linkLenaToAContact(store: ExtractionStore, links: ContactLinkActions) throws {
        guard let lena = try store.entities.entities(type: .person).first(where: { $0.title == "Lena" })?.id,
              let card = contactCards.first(where: { $0.identifier == "ui-contact-okafor" }) else { return }
        try waitFor { try await links.link(PersonID(rawValue: lena.rawValue), to: card) }
    }

    /// The colour of each card's generated picture, for the cards with `hasPicture`.
    private static let contactPictureColours: [String: Int] = ["ui-contact-vale": 0x5A7D9A, "ui-contact-quinn": 0x9A7D5A]

    /// `-uiTesting-contacts <full|limited|notAsked|denied>` picks the access. Without it (or with an unknown value) the
    /// app has not asked and a request is refused, so a test that does not name contacts sees none. `notAsked` named
    /// on purpose answers a request with `full`. The pictures are small generated JPEGs written under `folder`.
    static func contactsDirectory(arguments: [String], folder: URL) throws -> ScriptedContactsDirectory {
        let named = arguments.firstIndex(of: "-uiTesting-contacts").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            .flatMap(ContactsAccess.init(rawValue:))
        let access = named ?? .notAsked
        let afterRequest: ContactsAccess = named == nil ? .denied : (access == .notAsked ? .full : access)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var pictures: [String: Data] = [:]
        for (identifier, rgb) in contactPictureColours {
            let url = folder.appending(path: "\(identifier).jpg")
            try GeneratedPhoto.write(to: url, width: 96, height: 96, rgb: rgb)
            pictures[identifier] = try Data(contentsOf: url)
        }
        return ScriptedContactsDirectory(cards: contactCards, pictures: pictures, access: access, accessAfterRequest: afterRequest)
    }
}
