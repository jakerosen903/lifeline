import Foundation

/// The repositories extraction and confirmation read and write. One value to pass around.
public struct ExtractionStore: Sendable {
    public var candidates: CandidateRepository
    public var sessions: SessionRepository
    public var people: PeopleRepository
    public var memories: MemoryRepository
    public var profile: ProfileRepository
    public var chapters: ChapterRepository
    public var curiosity: CuriosityRepository
    public var embeddings: EmbeddingRepository
    public var stories: StoryRepository
    public var pairs: DuplicatePairRepository
    public var entities: EntityRepository
    public var tags: DomainTagRepository
    public var photos: PhotoRepository
    public var personLinks: PersonLinkRepository

    public init(candidates: CandidateRepository, sessions: SessionRepository, people: PeopleRepository,
                memories: MemoryRepository, profile: ProfileRepository, chapters: ChapterRepository, curiosity: CuriosityRepository,
                embeddings: EmbeddingRepository, stories: StoryRepository, pairs: DuplicatePairRepository,
                entities: EntityRepository, tags: DomainTagRepository, photos: PhotoRepository, personLinks: PersonLinkRepository) {
        self.candidates = candidates; self.sessions = sessions; self.people = people; self.memories = memories; self.profile = profile
        self.chapters = chapters; self.curiosity = curiosity; self.embeddings = embeddings; self.stories = stories; self.pairs = pairs
        self.entities = entities; self.tags = tags; self.photos = photos; self.personLinks = personLinks
    }

    public init(_ db: AppDatabase) {
        self.init(candidates: CandidateRepository(db), sessions: SessionRepository(db), people: PeopleRepository(db),
                  memories: MemoryRepository(db), profile: ProfileRepository(db), chapters: ChapterRepository(db), curiosity: CuriosityRepository(db),
                  embeddings: EmbeddingRepository(db), stories: StoryRepository(db), pairs: DuplicatePairRepository(db),
                  entities: EntityRepository(db), tags: DomainTagRepository(db), photos: PhotoRepository(db),
                  personLinks: PersonLinkRepository(db))
    }
}
