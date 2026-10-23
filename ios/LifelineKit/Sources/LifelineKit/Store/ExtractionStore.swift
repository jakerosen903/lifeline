import Foundation

/// The repositories extraction and confirmation read and write. One value to pass around.
public struct ExtractionStore: Sendable {
    public var candidates: CandidateRepository
    public var sessions: SessionRepository
    public var people: PeopleRepository
    public var memories: MemoryRepository
    public var profile: ProfileRepository

    public init(candidates: CandidateRepository, sessions: SessionRepository, people: PeopleRepository,
                memories: MemoryRepository, profile: ProfileRepository) {
        self.candidates = candidates; self.sessions = sessions; self.people = people; self.memories = memories; self.profile = profile
    }

    public init(_ db: AppDatabase) {
        self.init(candidates: CandidateRepository(db), sessions: SessionRepository(db), people: PeopleRepository(db),
                  memories: MemoryRepository(db), profile: ProfileRepository(db))
    }
}
