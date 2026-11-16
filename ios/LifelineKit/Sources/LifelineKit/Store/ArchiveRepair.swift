import Foundation

/// Repairs that earlier versions of the app made necessary. Each one is safe to run again: a
/// second run finds nothing to do. The app runs them once at launch and shows `notice` once.
public enum ArchiveRepair {
    public struct Report: Sendable, Equatable {
        /// Stories that had the same title and are now one, with how many copies there were.
        public var joinedStories: [StoryRepository.MergedTitle] = []
        /// Chapters with no title and no memory. They held nothing, so the notice leaves them out.
        public var removedChapters = 0

        /// One sentence for the person, or nil when no story was joined.
        public var notice: String? {
            switch joinedStories.count {
            case 0: nil
            case 1: "Joined \(joinedStories[0].copies) copies of “\(joinedStories[0].title)”."
            default: "Joined copies of \(joinedStories.count) stories that had the same title."
            }
        }
    }

    @discardableResult
    public static func run(_ store: ExtractionStore) throws -> Report {
        Report(joinedStories: try store.stories.mergeDuplicateTitles(),
               removedChapters: try store.chapters.deleteEmptyUntitled())
    }
}
