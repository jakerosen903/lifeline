import Foundation

/// Repairs that earlier versions of the app made necessary. Each one is safe to run again: a
/// second run finds nothing to do. The app runs them once at launch and shows `notice` once.
public enum ArchiveRepair {
    public struct Report: Sendable, Equatable {
        /// Stories that had the same title and are now one, with how many copies there were.
        public var joinedStories: [StoryRepository.MergedTitle] = []
        /// Places and things that had the same name and are now one ("Ohio." and "Ohio").
        public var joinedEntities: [StoryRepository.MergedTitle] = []
        /// Collections that had the same title and are now one.
        public var joinedCollections: [StoryRepository.MergedTitle] = []
        /// Chapters with no title and no memory. They held nothing, so the notice leaves them out.
        public var removedChapters = 0

        /// One sentence for the person, or nil when nothing was joined.
        public var notice: String? {
            let all = joinedStories + joinedEntities + joinedCollections
            switch all.count {
            case 0: return nil
            case 1: return "Joined \(all[0].copies) copies of “\(all[0].title)”."
            default:
                return all.count == joinedStories.count
                    ? "Joined copies of \(all.count) stories that had the same title."
                    : "Joined copies of \(all.count) things that had the same name."
            }
        }
    }

    @discardableResult
    public static func run(_ store: ExtractionStore) throws -> Report {
        Report(joinedStories: try store.stories.mergeDuplicateTitles(),
               joinedEntities: try store.entities.mergeDuplicateTitles(),
               joinedCollections: try store.chapters.mergeDuplicateCollections(),
               removedChapters: try store.chapters.deleteEmptyUntitled())
    }
}
